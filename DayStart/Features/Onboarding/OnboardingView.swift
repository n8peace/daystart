import SwiftUI
import StoreKit
import CoreLocation
import EventKit


struct ContentToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var accessoryContent: (() -> AnyView)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(BananaTheme.ColorToken.text)
                    
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(BananaTheme.ColorToken.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if isOn, let accessoryContent = accessoryContent {
                accessoryContent()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BananaTheme.ColorToken.card)
                .stroke(BananaTheme.ColorToken.border.opacity(0.2), lineWidth: 1)
        )
    }
}

struct MockProduct {
    let id: String
    let displayName: String
    let description: String
    let price: Double
    let displayPrice: String
    let type: ProductType
    
    enum ProductType {
        case autoRenewable
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    
    private let logger = DebugLogger.shared
    @State private var name = ""
    @State private var selectedTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var selectedDays: Set<WeekDay> = Set(WeekDay.allCases) // All days by default
    @State private var includeWeather = false
    @State private var includeNews = true
    @State private var includeSports = true
    @State private var includeStocks = true
    @State private var stockSymbols = "^GSPC, ^DJI, BTC-USD"
    @State private var includeCalendar = false
    @State private var includeQuotes = true
    @State private var selectedQuoteType: QuotePreference = .goodFeelings
    @State private var selectedVoice: VoiceOption? = nil
    @State private var selectedProduct: Product?
    @State private var showRestoreError = false
    @State private var restoreErrorMessage = ""
    
    // Permission states
    @State private var locationPermissionStatus: PermissionStatus = .notDetermined
    @State private var calendarPermissionStatus: PermissionStatus = .notDetermined
    @State private var showingLocationError = false
    @State private var showingCalendarError = false
    
    // Animation states
    @State private var animationTrigger = false
    @State private var heroScale: CGFloat = 1.0
    @State private var textOpacity: Double = 1.0  // Start visible for first page
    @State private var onboardingStartTime = Date()
    
    // Date formatter
    private var shortTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    private let totalPages = 11
    
    enum PermissionStatus {
        case notDetermined, granted, denied
    }
    
    // MARK: - Computed Properties
    var progressPercentage: Double {
        Double(currentPage + 1) / Double(totalPages)
    }
    
    var progressText: String {
        "\(Int(progressPercentage * 100))% Complete"
    }
    
    var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isVoiceSelected: Bool {
        selectedVoice != nil
    }
    
    var canNavigateFromLocationPage: Bool {
        locationPermissionStatus != .notDetermined
    }
    
    var canNavigateFromCalendarPage: Bool {
        calendarPermissionStatus != .notDetermined
    }
    
    var canNavigateFromCurrentPage: Bool {
        if currentPage == 5 { return canNavigateFromLocationPage }
        if currentPage == 6 { return canNavigateFromCalendarPage }
        return true // All other pages can always navigate
    }
    
    // MARK: - Permission Status Mapping Helpers
    
    private func mapLocationStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorizedWhenInUse, .authorizedAlways:
            return .granted
        @unknown default:
            return .notDetermined
        }
    }
    
    private func mapCalendarStatus() -> PermissionStatus {
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        
        switch authStatus {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorized:
            return .granted
        case .fullAccess:
            return .granted
        case .writeOnly:
            return .granted
        @unknown default:
            return .notDetermined
        }
    }
    
    // MARK: - Permission Status Synchronization
    
    private func syncPermissionStatuses() {
        // Sync location permission status
        let currentLocationStatus = LocationManager.shared.authorizationStatus
        locationPermissionStatus = mapLocationStatus(currentLocationStatus)
        
        // Sync calendar permission status  
        calendarPermissionStatus = mapCalendarStatus()
        
        // Update include flags based on current permissions
        includeWeather = (locationPermissionStatus == .granted)
        includeCalendar = (calendarPermissionStatus == .granted)
        
        logger.log("Synced permission statuses - Location: \(locationPermissionStatus), Calendar: \(calendarPermissionStatus)", level: .info)
    }
    
    var selectedDaysSummary: String {
        let sortedDays = selectedDays.sorted { $0.rawValue < $1.rawValue }
        
        if selectedDays.count == 7 {
            return "day"
        } else if selectedDays.count == 0 {
            return "No days selected"
        } else if selectedDays == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            return "Weekdays"
        } else if selectedDays == Set([.saturday, .sunday]) {
            return "Weekends"
        } else if selectedDays.count == 1 {
            return sortedDays.first!.name
        } else {
            return sortedDays.map { $0.name }.joined(separator: ", ")
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            BananaTheme.ColorToken.background
                .ignoresSafeArea()
            
            // Gradient overlay
            DayStartGradientBackground()
                .opacity(0.15)
            
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: progressPercentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: BananaTheme.ColorToken.primary))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                    .padding(.horizontal)
                    .padding(.top, BananaTheme.Spacing.md)
                
                // Progress text
                Text(progressText)
                    .font(BananaTheme.Typography.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .padding(.top, BananaTheme.Spacing.sm)
                
                // Page content
                TabView(selection: $currentPage) {
                    painPointPage.tag(0)
                    valueDemoPage.tag(1)
                    namePersonalizationPage.tag(2)
                    scheduleSetupPage.tag(3)
                    contentSelectionPage.tag(4)
                    weatherPermissionPage.tag(5)
                    calendarPermissionPage.tag(6)
                    voiceSelectionPage.tag(7)
                    finalPreviewPage.tag(8)
                    paywallPage.tag(9)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                .allowsHitTesting(canNavigateFromCurrentPage)
                .overlay(
                    // Gesture blocking overlay for permission pages when permissions are undetermined
                    ((currentPage == 5 || currentPage == 6) && !canNavigateFromCurrentPage) ? 
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle()) // Ensures the entire area is tappable
                            .gesture(
                                DragGesture()
                                    .onEnded { value in
                                        let swipeThreshold: CGFloat = 50
                                        
                                        if value.translation.width < -swipeThreshold {
                                            // Forward swipe - trigger permission request immediately
                                            if currentPage == 5 && locationPermissionStatus == .notDetermined {
                                                logger.logUserAction("Location permission auto-requested on blocked swipe")
                                                impactFeedback()
                                                Task {
                                                    await requestLocationPermission()
                                                }
                                            } else if currentPage == 6 && calendarPermissionStatus == .notDetermined {
                                                logger.logUserAction("Calendar permission auto-requested on blocked swipe")
                                                impactFeedback()
                                                Task {
                                                    await requestCalendarPermission()
                                                }
                                            }
                                        } else if value.translation.width > swipeThreshold {
                                            // Backward swipe - always allow
                                            if currentPage == 6 {
                                                logger.logUserAction("Calendar to location backward swipe (overlay)")
                                                impactFeedback()
                                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                                    currentPage = 5
                                                }
                                            } else if currentPage == 5 {
                                                logger.logUserAction("Location to content backward swipe (overlay)")
                                                impactFeedback()
                                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                                    currentPage = 4
                                                }
                                            }
                                        }
                                    }
                            )
                            .onTapGesture {
                                // Handle taps on overlay - trigger permission request immediately
                                if currentPage == 5 && locationPermissionStatus == .notDetermined {
                                    logger.logUserAction("Location permission auto-requested on tap")
                                    impactFeedback()
                                    Task {
                                        await requestLocationPermission()
                                    }
                                } else if currentPage == 6 && calendarPermissionStatus == .notDetermined {
                                    logger.logUserAction("Calendar permission auto-requested on tap")
                                    impactFeedback()
                                    Task {
                                        await requestCalendarPermission()
                                    }
                                }
                            }
                    : nil
                )
                .onAppear {
                    logger.log("🎓 New onboarding view appeared", level: .info)
                    logger.logUserAction("Onboarding started", details: ["initialPage": currentPage])
                    
                    // Sync permission statuses with actual system state
                    syncPermissionStatuses()
                    
                    // Phase 2: Fetch products for dynamic pricing
                    Task {
                        do {
                            try await purchaseManager.fetchProductsForDisplay()
                        } catch {
                            logger.logError(error, context: "Failed to fetch products for display")
                        }
                    }
                    
                    // Ensure first page animations start properly with a slight delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        startPageAnimation()
                    }
                }
                .onReceive(LocationManager.shared.$authorizationStatus) { newStatus in
                    let newLocationStatus = mapLocationStatus(newStatus)
                    if newLocationStatus != locationPermissionStatus {
                        logger.log("Location permission status changed: \(locationPermissionStatus) → \(newLocationStatus)", level: .info)
                        locationPermissionStatus = newLocationStatus
                        
                        // Update weather inclusion based on new status
                        includeWeather = (newLocationStatus == .granted)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Re-sync calendar status when app becomes active (after permission dialogs)
                    let newCalendarStatus = mapCalendarStatus()
                    if newCalendarStatus != calendarPermissionStatus {
                        logger.log("Calendar permission status changed when app became active: \(calendarPermissionStatus) → \(newCalendarStatus)", level: .info)
                        calendarPermissionStatus = newCalendarStatus
                        
                        // Update calendar inclusion based on new status
                        includeCalendar = (newCalendarStatus == .granted)
                    }
                }
                .onReceive(purchaseManager.$purchaseState) { purchaseState in
                    if case .purchased = purchaseState {
                        // Only auto-complete if user has progressed past paywall (indicating fresh purchase)
                        // AND has been in onboarding for at least 2 seconds (prevents immediate completion on app launch)
                        if currentPage > 8 && Date().timeIntervalSince(onboardingStartTime) > 2.0 {
                            logger.log("✅ Purchase detected during onboarding, completing flow", level: .info)
                            onComplete()
                        } else {
                            logger.log("🔍 Purchase detected but user hasn't progressed through onboarding or insufficient time elapsed (page: \(currentPage), time: \(Date().timeIntervalSince(onboardingStartTime))s)", level: .debug)
                        }
                    }
                }
                .onChange(of: currentPage) { oldPage, newPage in
                    AudioPlayerManager.shared.stopVoicePreview()
                    hideKeyboard()
                    
                    // Reset animations first
                    textOpacity = 0.0
                    animationTrigger = false
                    
                    // Start animations with delay to ensure reset takes effect
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        startPageAnimation()
                    }
                    
                    logger.logUserAction("Onboarding page changed", details: [
                        "fromPage": oldPage,
                        "toPage": newPage,
                        "pageName": getPageName(for: newPage)
                    ])
                }
            }
        }
        .alert("Restore Failed", isPresented: $showRestoreError) {
            Button("OK") { }
        } message: {
            Text(restoreErrorMessage)
        }
    }
    
    // MARK: - Page 1: Pain Point Hook (10%)
    private var painPointPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.04) {
                    // Animated emoji transformation
                    HStack(spacing: 20) {
                        Text("😴")
                            .font(.system(size: min(80, geometry.size.width * 0.15)))
                            .scaleEffect(animationTrigger ? 0.8 : 1.2)
                            .opacity(animationTrigger ? 0.3 : 1.0)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: min(30, geometry.size.width * 0.10)))
                            .foregroundColor(BananaTheme.ColorToken.primary)
                            .scaleEffect(animationTrigger ? 1.2 : 0.8)
                        
                        Text("😊")
                            .font(.system(size: min(80, geometry.size.width * 0.15)))
                            .scaleEffect(animationTrigger ? 1.2 : 0.8)
                            .opacity(animationTrigger ? 1.0 : 0.3)
                    }
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Mornings Suck. We Get It.")
                            .font(.system(size: min(32, geometry.size.width * 0.10), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text("Most people start their day feeling lost and overwhelmed.")
                            .font(.system(size: min(18, geometry.size.width * 0.045), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // Pain points grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    PainPointCard(icon: "❌", text: "Unsure where to start", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Pain point card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 1 
                            }
                        }
                    PainPointCard(icon: "❌", text: "Overwhelmed by the day", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Pain point card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 1 
                            }
                        }
                    PainPointCard(icon: "❌", text: "No motivation to rise", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Pain point card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 1 
                            }
                        }
                    PainPointCard(icon: "❌", text: "Same boring routine", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Pain point card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 1 
                            }
                        }
                }
                .padding(.horizontal, geometry.size.width * 0.10)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.08)
                
                // CTA Button
                Button(action: { 
                    logger.logUserAction("Pain point CTA tapped")
                    impactFeedback()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                        currentPage = 1 
                    }
                }) {
                    Text("Transform My Mornings")
                        .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            LinearGradient(
                                colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 2: Value Demo (20%)
    private var valueDemoPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
                    animatedPhoneView(geometry: geometry)
                    
                    valueDemoText(geometry: geometry)
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Feature preview cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    FeaturePreviewCard(icon: "📰", title: "News", subtitle: "Stay informed", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Feature preview card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 2 
                            }
                        }
                    FeaturePreviewCard(icon: "☁️", title: "Weather", subtitle: "Dress right", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Feature preview card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 2 
                            }
                        }
                    FeaturePreviewCard(icon: "📅", title: "Calendar", subtitle: "Never miss", geometry: geometry)
                        .onTapGesture {
                            logger.logUserAction("Feature preview card tapped")
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 2 
                            }
                        }
                }
                .padding(.horizontal, geometry.size.width * 0.10)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Social proof
                HStack(spacing: 8) {
                    ForEach(0..<5) { _ in
                        Image(systemName: "star.fill")
                            .foregroundColor(BananaTheme.ColorToken.primary)
                            .font(.system(size: min(16, geometry.size.width * 0.04)))
                    }
                    Text("Join others who start better")
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA
                Button(action: {
                    logger.logUserAction("Value demo CTA tapped")
                    impactFeedback()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                        currentPage = 2 
                    }
                }) {
                    Text("See How It Works")
                        .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            LinearGradient(
                                colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 3: Name Personalization (30%)
    private var namePersonalizationPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
                    // Greeting animation
                    Text("👋")
                        .font(.system(size: min(100, geometry.size.width * 0.25)))
                        .scaleEffect(animationTrigger ? 1.2 : 0.9)
                        .rotationEffect(.degrees(animationTrigger ? 15 : -15))
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animationTrigger)
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Let's Make This Personal")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text("Your AI will greet you by name each morning")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // Name input
                VStack(spacing: geometry.size.height * 0.03) {
                    TextField("What should I call you?", text: $name)
                        .font(.system(size: min(24, geometry.size.width * 0.06), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(BananaTheme.ColorToken.card)
                                .stroke(isNameValid ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border, lineWidth: 2)
                        )
                        .padding(.horizontal, geometry.size.width * 0.10)
                        .submitLabel(.done)
                        .onSubmit {
                            if isNameValid {
                                impactFeedback()
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                    currentPage = 3
                                }
                            }
                        }
                        .opacity(textOpacity)
                    
                    // Preview
                    if !name.isEmpty {
                        Text("Good morning \(name)! Ready to conquer today?")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.08)
                
                // CTA Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        logger.logUserAction("Name personalization CTA tapped", details: ["hasName": !name.isEmpty])
                        impactFeedback()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 3
                        }
                    }) {
                        Text(isNameValid ? "That's Perfect!" : "Continue")
                            .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(56, geometry.size.height * 0.07))
                            .background(
                                LinearGradient(
                                    colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .scaleEffect(animationTrigger ? 1.05 : 1.0)
                    
                    // Skip button
                    Button(action: {
                        logger.logUserAction("Name personalization skipped")
                        impactFeedback()
                        name = "" // Clear name if they skip
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 3
                        }
                    }) {
                        Text("Skip for now")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 4: Schedule Setup (40%)
    private var scheduleSetupPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
                    // Clock with sunrise animation
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.3), Color.yellow.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: min(120, geometry.size.width * 0.25))
                        
                        Text("⏰")
                            .font(.system(size: min(60, geometry.size.width * 0.12)))
                            .scaleEffect(animationTrigger ? 1.1 : 0.9)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                        
                        // Sunrise rays
                        ForEach(0..<8) { index in
                            Rectangle()
                                .fill(Color.orange.opacity(0.6))
                                .frame(width: 3, height: 20)
                                .offset(y: -50)
                                .rotationEffect(.degrees(Double(index) * 45))
                                .opacity(animationTrigger ? 1.0 : 0.3)
                                .animation(.easeInOut(duration: 2.0).repeatForever().delay(Double(index) * 0.1), value: animationTrigger)
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Set Your Daily Wake Time")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text("We'll deliver your daily briefing every morning")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Time picker section
                VStack(spacing: geometry.size.height * 0.03) {
                    // Time picker
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: min(140, geometry.size.height * 0.18))
                                .clipped()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(textOpacity)
                        
                        // Note about customization
                        VStack(spacing: 8) {
                            Text("Daily briefings, 7 days a week")
                                .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                                .foregroundColor(BananaTheme.ColorToken.text)
                                .multilineTextAlignment(.center)
                            
                            Text("You can customize which days later in Settings")
                                .font(.system(size: min(12, geometry.size.width * 0.03), weight: .regular))
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .opacity(textOpacity)
                        .padding(.horizontal, geometry.size.width * 0.08)
                    }
                    
                    // Preview
                    Text("Your briefing will be ready every day at \(shortTimeFormatter.string(from: selectedTime))")
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, geometry.size.width * 0.10)
                        .opacity(textOpacity)
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA
                Button(action: {
                    // All days are always selected now
                    logger.logUserAction("Schedule setup CTA tapped")
                    impactFeedback()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                        currentPage = 4
                    }
                }) {
                    Text("Lock It In!")
                        .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            LinearGradient(
                                colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 5: Content Selection (50%)
    private var contentSelectionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
                    // Floating content icons
                    floatingIconsView(geometry: geometry)
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("What Gets You Pumped?")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text("Choose what matters to you most")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.02)
                
                // Content selection toggles
                VStack(spacing: 14) {
                    ContentToggleRow(
                        icon: "📰",
                        title: "News",
                        subtitle: "Latest headlines and updates",
                        isOn: $includeNews
                    )
                    
                    ContentToggleRow(
                        icon: "🏈",
                        title: "Sports",
                        subtitle: "Scores and highlights",
                        isOn: $includeSports
                    )
                    
                    ContentToggleRow(
                        icon: "📈",
                        title: "Stocks",
                        subtitle: "Market updates and prices",
                        isOn: $includeStocks
                        // TEMPORARILY REMOVED: Stock symbols text field
                        // Will be added back later if needed
                        /*
                        accessoryContent: {
                            AnyView(
                                TextField("SPY, AAPL, BTC-USD", text: $stockSymbols)
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(BananaTheme.ColorToken.background)
                                            .stroke(BananaTheme.ColorToken.border.opacity(0.3), lineWidth: 1)
                                    )
                                    .submitLabel(.done)
                                    .onSubmit { hideKeyboard() }
                            )
                        }
                        */
                    )
                    
                    ContentToggleRow(
                        icon: "💬",
                        title: "Motivational Quotes",
                        subtitle: "Daily inspiration and wisdom",
                        isOn: $includeQuotes
                        // TEMPORARILY REMOVED: Quote type picker
                        // Will be added back later if needed
                        /*
                        accessoryContent: {
                            AnyView(
                                HStack(spacing: 8) {
                                    ForEach([QuotePreference.inspirational, QuotePreference.philosophical, QuotePreference.stoic], id: \.self) { preference in
                                        Button(action: {
                                            selectedQuoteType = preference
                                            impactFeedback()
                                        }) {
                                            Text(preference.rawValue.capitalized)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(selectedQuoteType == preference ? BananaTheme.ColorToken.background : BananaTheme.ColorToken.text)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(selectedQuoteType == preference ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.background)
                                                        .stroke(BananaTheme.ColorToken.border.opacity(selectedQuoteType == preference ? 0 : 0.3), lineWidth: 1)
                                                )
                                        }
                                    }
                                    Spacer()
                                }
                            )
                        }
                        */
                    )
                }
                .padding(.horizontal, geometry.size.width * 0.10)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.03)
                
                // CTA
                Button(action: {
                    logger.logUserAction("Content selection CTA tapped")
                    impactFeedback()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                        currentPage = 5
                    }
                }) {
                    Text("Perfect Mix!")
                        .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            LinearGradient(
                                colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 6: Location Permission (60%)
    private var weatherPermissionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.04) {
                    // Weather animation with location
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: min(120, geometry.size.width * 0.25))
                        
                        VStack(spacing: 6) {
                            Text("🌤️")
                                .font(.system(size: min(40, geometry.size.width * 0.08)))
                                .scaleEffect(animationTrigger ? 1.1 : 0.9)
                            
                            Image(systemName: "location.fill")
                                .font(.system(size: min(16, geometry.size.width * 0.04)))
                                .foregroundColor(BananaTheme.ColorToken.primary)
                                .scaleEffect(animationTrigger ? 1.2 : 0.8)
                        }
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                    }
                    
                    VStack(spacing: geometry.size.height * 0.015) {
                        Text("Location Permission")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text(locationPermissionStatus == .notDetermined ? 
                             "We'll ask for your location to add local weather to your DayStart" :
                             locationPermissionStatus == .granted ?
                             "Location access enabled! Weather will be included in your DayStart" :
                             "Location access disabled. Weather will not be included")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                    
                    // Benefits
                    VStack(spacing: 12) {
                        PermissionBenefitRow(icon: "🌡️", text: "Temperature & forecast", geometry: geometry)
                        PermissionBenefitRow(icon: "👕", text: "Outfit suggestions", geometry: geometry)
                        PermissionBenefitRow(icon: "☔", text: "Rain & storm alerts", geometry: geometry)
                        PermissionBenefitRow(icon: "📰", text: "Localized news & sports", geometry: geometry)
                    }
                    .opacity(textOpacity)
                    
                    // Optional message
                    Text("This is completely optional - feel free to allow or deny based on your preference")
                        .font(.system(size: min(13, geometry.size.width * 0.032), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, geometry.size.width * 0.10)
                        .opacity(textOpacity)
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA Button
                Button(action: {
                    if locationPermissionStatus == .notDetermined {
                        logger.logUserAction("Location permission request triggered by button")
                        impactFeedback()
                        Task {
                            await requestLocationPermission()
                        }
                    } else {
                        // Permission already determined, navigate to next page
                        logger.logUserAction("Location permission page navigation", details: ["status": "\(locationPermissionStatus)"])
                        impactFeedback()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 6
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: locationPermissionStatus == .granted ? "checkmark.circle.fill" : 
                              locationPermissionStatus == .denied ? "xmark.circle.fill" : "location.fill")
                        Text(locationPermissionStatus == .granted ? "Next" : 
                             locationPermissionStatus == .denied ? "Next" : "Continue")
                    }
                    .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(56, geometry.size.height * 0.07))
                    .background(
                        LinearGradient(
                            colors: locationPermissionStatus == .granted ? [Color.green, Color.green.opacity(0.8)] :
                                    locationPermissionStatus == .denied ? [Color.red, Color.red.opacity(0.8)] :
                                    [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: (locationPermissionStatus == .granted ? Color.green : 
                                  locationPermissionStatus == .denied ? Color.red : 
                                  BananaTheme.ColorToken.primary).opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
            .overlay(alignment: .bottom) {
                // Apple Weather attribution pinned to bottom; does not affect layout
                HStack(spacing: 6) {
                    Button(action: {
                        if let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Powered by  Weather")
                            .font(.system(size: min(11, geometry.size.width * 0.028), weight: .semibold))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .opacity(textOpacity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(8, geometry.safeAreaInsets.bottom + 8))
            }
        }
    }
    
    // MARK: - Page 7: Calendar Permission (70%)
    private var calendarPermissionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.04) {
                    // Calendar animation with events
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [BananaTheme.ColorToken.primary.opacity(0.3), BananaTheme.ColorToken.accent.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: min(100, geometry.size.width * 0.22), height: min(85, geometry.size.height * 0.10))
                        
                        VStack(spacing: 6) {
                            Text("📅")
                                .font(.system(size: min(32, geometry.size.width * 0.08)))
                                .scaleEffect(animationTrigger ? 1.1 : 0.9)
                            
                            // Animated event dots
                            HStack(spacing: 3) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(BananaTheme.ColorToken.primary)
                                        .frame(width: 5, height: 5)
                                        .scaleEffect(animationTrigger ? 1.2 : 0.8)
                                        .animation(.easeInOut(duration: 1.0).repeatForever().delay(Double(index) * 0.2), value: animationTrigger)
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.015) {
                        Text("Calendar Permission")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text(calendarPermissionStatus == .notDetermined ? 
                             "We'll ask to access your calendar to include today's events in your DayStart" :
                             calendarPermissionStatus == .granted ?
                             "Calendar access enabled! Your events will be included in your DayStart" :
                             "Calendar access disabled. Events will not be included")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                    
                    // Benefits
                    VStack(spacing: 12) {
                        PermissionBenefitRow(icon: "🕰️", text: "Upcoming events overview", geometry: geometry)
                        PermissionBenefitRow(icon: "💼", text: "Meeting preparation tips", geometry: geometry)
                        PermissionBenefitRow(icon: "📅", text: "Schedule optimization", geometry: geometry)
                    }
                    .opacity(textOpacity)
                    
                    // Optional message
                    Text("This is completely optional - feel free to allow or deny based on your preference")
                        .font(.system(size: min(13, geometry.size.width * 0.032), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, geometry.size.width * 0.10)
                        .opacity(textOpacity)
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA Button
                Button(action: {
                    if calendarPermissionStatus == .notDetermined {
                        logger.logUserAction("Calendar permission request triggered by button")
                        impactFeedback()
                        Task {
                            await requestCalendarPermission()
                        }
                    } else {
                        // Permission already determined, navigate to next page
                        logger.logUserAction("Calendar permission page navigation", details: ["status": "\(calendarPermissionStatus)"])
                        impactFeedback()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 7
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: calendarPermissionStatus == .granted ? "checkmark.circle.fill" : 
                              calendarPermissionStatus == .denied ? "xmark.circle.fill" : "calendar")
                        Text(calendarPermissionStatus == .granted ? "Next" : 
                             calendarPermissionStatus == .denied ? "Next" : "Continue")
                    }
                    .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(56, geometry.size.height * 0.07))
                    .background(
                        LinearGradient(
                            colors: calendarPermissionStatus == .granted ? [Color.green, Color.green.opacity(0.8)] :
                                    calendarPermissionStatus == .denied ? [Color.red, Color.red.opacity(0.8)] :
                                    [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: (calendarPermissionStatus == .granted ? Color.green : 
                                  calendarPermissionStatus == .denied ? Color.red : 
                                  BananaTheme.ColorToken.primary).opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 8: Voice Selection (80%)
    private var voiceSelectionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.03) {
                    // Microphone with sound waves
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BananaTheme.ColorToken.primary.opacity(0.3), BananaTheme.ColorToken.accent.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: min(120, geometry.size.width * 0.25))
                        
                        Text("🎤")
                            .font(.system(size: min(50, geometry.size.width * 0.10)))
                            .scaleEffect(animationTrigger ? 1.1 : 0.9)
                        
                        // Sound wave lines
                        ForEach(0..<4) { index in
                            soundWaveLine(for: index)
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.015) {
                        Text("Choose Your Voice")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text("The voice that starts your day right")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                    
                    // Voice selection cards - compact layout
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(VoiceOption.allCases, id: \.rawValue) { voice in
                            VoiceCard(
                                voice: voice,
                                isSelected: selectedVoice == voice,
                                geometry: geometry,
                                onSelect: {
                                    selectedVoice = voice
                                    AudioPlayerManager.shared.previewVoice(voice)
                                    impactFeedback()
                                    logger.logUserAction("Voice selected", details: ["voice": voice.name])
                                }
                            )
                        }
                    }
                    .padding(.horizontal, geometry.size.width * 0.10)
                    .opacity(textOpacity)
                    
                    // Voice preview - compact
                    if selectedVoice != nil {
                        Text("\"Good morning! Your briefing will sound like this...\"")
                            .font(.system(size: min(13, geometry.size.width * 0.032), weight: .medium, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .italic()
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // CTA Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        logger.logUserAction("Voice selection CTA tapped")
                        impactFeedback()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 8
                        }
                    }) {
                        Text("Continue")
                            .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(56, geometry.size.height * 0.07))
                            .background(
                                LinearGradient(
                                    colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .scaleEffect(animationTrigger ? 1.05 : 1.0)
                    
                    // Skip button
                    Button(action: {
                        logger.logUserAction("Voice selection skipped")
                        impactFeedback()
                        // Keep default voice selection
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 8
                        }
                    }) {
                        Text("Use default voice")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 9: Final Preview (90%)
    private var finalPreviewPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.03) {
                    // Sparkle animation - smaller
                    HStack(spacing: 15) {
                        ForEach(["✨", "🎆", "✨"], id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: min(35, geometry.size.width * 0.07)))
                                .scaleEffect(animationTrigger ? 1.2 : 0.8)
                                .rotationEffect(.degrees(animationTrigger ? 15 : -15))
                                .animation(.easeInOut(duration: 1.0).repeatForever().delay(Double(["✨", "🎆", "✨"].firstIndex(of: emoji) ?? 0) * 0.3), value: animationTrigger)
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.015) {
                        Text("Your Morning Transformation")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, geometry.size.width * 0.05)
                            .opacity(textOpacity)
                        
                        Text("Tomorrow morning will be different...")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.10)
                            .opacity(textOpacity)
                    }
                    
                    // Preview summary - compact layout
                    VStack(spacing: 12) {
                        PreviewSummaryCard(
                            icon: "👋",
                            title: name.isEmpty ? "Personal greeting" : "Good morning \(name)!",
                            geometry: geometry
                        )
                        
                        PreviewSummaryCard(
                            icon: "⏰",
                            title: "Ready at \(shortTimeFormatter.string(from: selectedTime))",
                            geometry: geometry
                        )
                        
                        PreviewSummaryCard(
                            icon: "🎤",
                            title: selectedVoice?.name ?? "Your chosen voice",
                            geometry: geometry
                        )
                        
                        let selectedContent = [includeNews ? "News" : nil, includeWeather ? "Weather" : nil, includeSports ? "Sports" : nil, includeStocks ? "Stocks" : nil, includeCalendar ? "Calendar" : nil, includeQuotes ? "Quotes" : nil].compactMap { $0 }
                        
                        PreviewSummaryCard(
                            icon: "📊",
                            title: "\(selectedContent.joined(separator: ", ")) & more",
                            geometry: geometry
                        )
                    }
                    .padding(.horizontal, geometry.size.width * 0.10)
                    .opacity(textOpacity)
                    
                    // Anticipation text - compact
                    Text("Your personalized briefing is almost ready...")
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium, design: .rounded))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, geometry.size.width * 0.10)
                        .opacity(textOpacity)
                        .italic()
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA Button
                Button(action: {
                    logger.logUserAction("Final preview CTA tapped")
                    impactFeedback()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                        currentPage = 9
                    }
                }) {
                    Text("Make It Happen!")
                        .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            LinearGradient(
                                colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationTrigger ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.10)
                .padding(.bottom, max(44, geometry.safeAreaInsets.bottom + 24))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 10: Hard Paywall (100%)
    private var paywallPage: some View {
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 700 // iPhone 13 mini is 812pt
            let topSpacing = isCompactHeight ? geometry.size.height * 0.02 : geometry.size.height * 0.08
            let sectionSpacing = isCompactHeight ? geometry.size.height * 0.02 : geometry.size.height * 0.04
            
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        Spacer(minLength: topSpacing)
                        
                        VStack(spacing: sectionSpacing) {
                            // Premium star with pulsing animation
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: min(80, geometry.size.width * 0.20))
                                    .scaleEffect(animationTrigger ? 1.1 : 0.9)
                                
                                Text("🌟")
                                    .font(.system(size: min(45, geometry.size.width * 0.09)))
                                    .scaleEffect(animationTrigger ? 1.2 : 1.0)
                            }
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                            
                            VStack(spacing: isCompactHeight ? 8 : geometry.size.height * 0.02) {
                                Text("Unlock Your Better Mornings")
                                    .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                                    .foregroundColor(BananaTheme.ColorToken.text)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .padding(.horizontal, geometry.size.width * 0.05)
                                    .opacity(textOpacity)
                                
                                Text("Skip the scrolling, get briefed")
                                    .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, geometry.size.width * 0.10)
                                    .opacity(textOpacity)
                            }
                        }
                        
                        Spacer(minLength: isCompactHeight ? 12 : geometry.size.height * 0.04)
                
                // Pricing options - optimized for conversion
                if purchaseManager.isLoadingProducts {
                    // Loading state
                    VStack(spacing: isCompactHeight ? 12 : 20) {
                        ProgressView()
                            .scaleEffect(isCompactHeight ? 1.2 : 1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: BananaTheme.ColorToken.primary))
                        
                        Text("Loading pricing options...")
                            .font(.system(size: isCompactHeight ? 14 : min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    .frame(height: isCompactHeight ? 120 : 200)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, geometry.size.width * 0.10)
                    .opacity(textOpacity)
                } else if purchaseManager.availableProducts.isEmpty {
                    // Error state - no products loaded
                    VStack(spacing: isCompactHeight ? 12 : 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: isCompactHeight ? 30 : 40))
                            .foregroundColor(.orange)
                        
                        Text("Unable to load pricing")
                            .font(.system(size: isCompactHeight ? 16 : min(18, geometry.size.width * 0.045), weight: .semibold))
                            .foregroundColor(BananaTheme.ColorToken.text)
                        
                        Button("Retry") {
                            Task {
                                do {
                                    try await purchaseManager.fetchProductsForDisplay()
                                    if selectedProduct == nil {
                                        selectedProduct = getProduct(for: "daystart_annual_subscription")
                                    }
                                } catch {
                                    logger.logError(error, context: "Retry fetch products failed")
                                }
                            }
                        }
                        .padding(.horizontal, isCompactHeight ? 16 : 20)
                        .padding(.vertical, isCompactHeight ? 6 : 8)
                        .background(BananaTheme.ColorToken.primary)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .cornerRadius(isCompactHeight ? 10 : 12)
                    }
                    .frame(height: isCompactHeight ? 120 : 200)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, geometry.size.width * 0.10)
                    .opacity(textOpacity)
                } else {
                    // Use HStack for wider screens, VStack for narrow
                    Group {
                        if geometry.size.width > 500 {
                            HStack(spacing: 12) {
                                PricingCard(
                                    title: "Annual Pass",
                            price: getProduct(for: "daystart_annual_subscription")?.displayPrice ?? "$39.99/year",
                            subtitle: nil,
                            badge: "🔥 Most Popular",
                            trialText: getTrialText(for: getProduct(for: "daystart_annual_subscription")) ?? "7-Day Free Trial",
                            renewalText: "renews annually",
                            savings: getSavingsText(annual: getProduct(for: "daystart_annual_subscription"), monthly: getProduct(for: "daystart_monthly_subscription")),
                            isSelected: selectedProduct?.id == "daystart_annual_subscription",
                            geometry: geometry,
                            animationTrigger: animationTrigger,
                            action: {
                                selectedProduct = getProduct(for: "daystart_annual_subscription")
                                impactFeedback()
                            }
                        )
                        
                        PricingCard(
                            title: "Monthly Pass",
                            price: getProduct(for: "daystart_monthly_subscription")?.displayPrice ?? "$4.99/month",
                            subtitle: nil,
                            badge: nil,
                            trialText: getTrialText(for: getProduct(for: "daystart_monthly_subscription")) ?? "3-Day Free Trial",
                            renewalText: "renews monthly",
                            savings: nil,
                            isSelected: selectedProduct?.id == "daystart_monthly_subscription",
                            geometry: geometry,
                            animationTrigger: animationTrigger,
                            action: {
                                selectedProduct = getProduct(for: "daystart_monthly_subscription")
                                impactFeedback()
                            }
                        )
                            }
                        } else {
                            VStack(spacing: 12) {
                                PricingCard(
                                    title: "Annual Pass",
                                    price: getProduct(for: "daystart_annual_subscription")?.displayPrice ?? "$39.99/year",
                                    subtitle: nil,
                                    badge: "🔥 Most Popular",
                                    trialText: getTrialText(for: getProduct(for: "daystart_annual_subscription")) ?? "7-Day Free Trial",
                                    renewalText: "renews annually",
                                    savings: getSavingsText(annual: getProduct(for: "daystart_annual_subscription"), monthly: getProduct(for: "daystart_monthly_subscription")),
                                    isSelected: selectedProduct?.id == "daystart_annual_subscription",
                                    geometry: geometry,
                                    animationTrigger: animationTrigger,
                                    action: {
                                        selectedProduct = getProduct(for: "daystart_annual_subscription")
                                        impactFeedback()
                                    }
                                )
                                
                                PricingCard(
                                    title: "Monthly Pass",
                                    price: getProduct(for: "daystart_monthly_subscription")?.displayPrice ?? "$4.99/month",
                                    subtitle: nil,
                                    badge: nil,
                                    trialText: getTrialText(for: getProduct(for: "daystart_monthly_subscription")) ?? "3-Day Free Trial",
                                    renewalText: "renews monthly",
                                    savings: nil,
                                    isSelected: selectedProduct?.id == "daystart_monthly_subscription",
                                    geometry: geometry,
                                    animationTrigger: animationTrigger,
                                    action: {
                                        selectedProduct = getProduct(for: "daystart_monthly_subscription")
                                        impactFeedback()
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, geometry.size.width * 0.10)
                    .opacity(textOpacity)
                }
                    }
                }
                .clipped()
                
                // Fixed bottom action area
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.1)
                    
                    VStack(spacing: isCompactHeight ? 16 : 24) {
                        // Adaptive "Limited Time Offer" badge
                        if !isCompactHeight {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                Text("Limited Time Offer")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(BananaTheme.ColorToken.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(BananaTheme.ColorToken.primary.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(BananaTheme.ColorToken.primary.opacity(0.3), lineWidth: 1)
                            )
                            .opacity(textOpacity)
                        }
                        
                        // CTA Button Group
                        VStack(spacing: 8) {
                            Button(action: {
                                logger.logUserAction("Paywall CTA tapped", details: [
                                    "selectedProduct": selectedProduct?.id ?? "none",
                                    "hasName": !name.isEmpty,
                                    "includeWeather": includeWeather,
                                    "includeNews": includeNews,
                                    "includeSports": includeSports,
                                    "includeStocks": includeStocks,
                                    "includeCalendar": includeCalendar,
                                    "includeQuotes": includeQuotes,
                                    "selectedVoice": selectedVoice?.name ?? "none"
                                ])
                                
                                // Start purchase flow and trigger job creation
                                startPurchaseFlow()
                            }) {
                                VStack(spacing: isCompactHeight ? 2 : 4) {
                                    Text(getCTAText(for: selectedProduct))
                                        .font(.system(size: isCompactHeight ? 18 : min(22, geometry.size.width * 0.055), weight: .bold))
                                        .foregroundColor(BananaTheme.ColorToken.background)
                                    
                                    if let product = selectedProduct {
                                        Text(getCTASubtext(for: product))
                                            .font(.system(size: isCompactHeight ? 12 : min(14, geometry.size.width * 0.035), weight: .medium))
                                            .foregroundColor(BananaTheme.ColorToken.background.opacity(0.9))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: isCompactHeight ? 56 : max(64, geometry.size.height * 0.08))
                            }
                            .buttonStyle(InstantResponseStyle())
                            .background(
                                LinearGradient(
                                    colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .cornerRadius(25)
                                .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: isCompactHeight ? 12 : 20)
                            )
                            .scaleEffect(animationTrigger ? 1.02 : 1.0)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animationTrigger)
                            .opacity(textOpacity)
                            .disabled(purchaseManager.isLoadingProducts || selectedProduct == nil)
                            
                            Text("Auto-renews until canceled. Cancel anytime in Settings.")
                                .font(.system(size: isCompactHeight ? 10 : 11, weight: .regular))
                                .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .opacity(textOpacity)
                        }
                        
                        // Legal links - smaller and less prominent
                        HStack(spacing: isCompactHeight ? 12 : 16) {
                            Button("Terms") {
                                if let url = URL(string: "https://daystart.bananaintelligence.ai/terms") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Text("•")
                            Button("Privacy") {
                                if let url = URL(string: "https://daystart.bananaintelligence.ai/privacy") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            Text("•")
                            Button("Restore") {
                                Task {
                                    do {
                                        try await PurchaseManager.shared.restorePurchases()
                                    } catch {
                                        logger.logError(error, context: "Failed to restore purchases")
                                        await MainActor.run {
                                            restoreErrorMessage = "No previous purchase found. Please subscribe to continue."
                                            showRestoreError = true
                                        }
                                    }
                                }
                            }
                        }
                        .font(.system(size: isCompactHeight ? 10 : 11, weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.6))
                        .opacity(textOpacity)
                    }
                    .padding(.horizontal, geometry.size.width * 0.10)
                    .padding(.top, isCompactHeight ? 12 : 20)
                    .padding(.bottom, max(isCompactHeight ? 16 : 24, geometry.safeAreaInsets.bottom))
                }
                .background(
                    LinearGradient(
                        colors: [
                            BananaTheme.ColorToken.background,
                            BananaTheme.ColorToken.background.opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .onAppear {
            // Fetch products if not already loaded
            if purchaseManager.availableProducts.isEmpty {
                Task {
                    do {
                        try await purchaseManager.fetchProductsForDisplay()
                        // Set default selection to annual product after loading
                        if selectedProduct == nil {
                            selectedProduct = getProduct(for: "daystart_annual_subscription")
                        }
                    } catch {
                        logger.logError(error, context: "Failed to fetch products on paywall appear")
                    }
                }
            } else {
                // Products already loaded, just set default selection
                if selectedProduct == nil {
                    selectedProduct = getProduct(for: "daystart_annual_subscription")
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func startPageAnimation() {
        // Ensure content is visible
        withAnimation(.easeInOut(duration: 0.6)) {
            textOpacity = 1.0
        }
        
        // Trigger scale and other animations
        withAnimation(.easeInOut(duration: 1.0).delay(0.2)) {
            animationTrigger.toggle()
        }
        
        // Trigger hero scale animation for first page
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.4)) {
            heroScale = 1.02
        }
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func getPageName(for page: Int) -> String {
        switch page {
        case 0: return "Pain Point"
        case 1: return "Value Demo"
        case 2: return "Name Personalization"
        case 3: return "Schedule Setup"
        case 4: return "Content Selection"
        case 5: return "Location Permission"
        case 6: return "Calendar Permission"
        case 7: return "Voice Selection"
        case 8: return "Final Preview"
        case 9: return "Paywall"
        default: return "Unknown"
        }
    }
    
    private func startPurchaseFlow() {
        logger.log("🛒 Starting purchase flow from paywall", level: .info)
        
        Task {
            do {
                guard let product = selectedProduct else {
                    logger.log("❌ No product selected", level: .error)
                    return
                }
                
                // Use real StoreKit purchase (works in both debug and production)
                logger.log("💳 Initiating StoreKit purchase", level: .info)
                try await PurchaseManager.shared.purchase(productId: product.id)
                
                await MainActor.run {
                    logger.log("✅ Purchase flow completed successfully", level: .info)
                    
                    // CRITICAL: Start Welcome DayStart processing immediately after purchase
                    startWelcomeDayStartProcessing()
                    
                    // Complete onboarding directly after purchase
                    completeOnboarding()
                }
            } catch {
                await MainActor.run {
                    logger.logError(error, context: "Purchase flow failed")
                    // TODO: Show error alert to user
                    // For now, just log the error
                }
            }
        }
    }
    
    private func startWelcomeDayStartProcessing() {
        logger.log("🚀 Starting Welcome DayStart processing immediately after purchase", level: .info)
        
        // Save settings first so they're available for job creation
        saveOnboardingSettings()
        
        // Set flag to auto-start welcome DayStart when HomeView appears
        UserDefaults.standard.set(true, forKey: "shouldAutoStartWelcome")
        
        // CRITICAL: Create the first job immediately after successful paywall conversion
        Task {
            do {
                // For welcome DayStart, get tomorrow's weather and calendar events
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: tomorrow)
                
                // 1. Create welcome job for today only
                let jobResponse = try await SupabaseClient.shared.createJob(
                    for: Date(),
                    with: UserPreferences.shared.settings,
                    schedule: UserPreferences.shared.schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar,
                    isWelcome: true
                )
                
                logger.log("✅ ONBOARDING: Welcome job created successfully with ID: \(jobResponse.jobId ?? "unknown")", level: .info)
                
                // 2. Create initial schedule jobs starting from tomorrow
                let jobsCreated = try await SupabaseClient.shared.createInitialScheduleJobs(
                    schedule: UserPreferences.shared.schedule,
                    preferences: UserPreferences.shared.settings,
                    excludeToday: true
                )
                
                logger.log("📅 ONBOARDING: Created \(jobsCreated) future scheduled jobs", level: .info)
                
                // 3. Immediately trigger processing of the welcome job
                if let jobId = jobResponse.jobId {
                    do {
                        try await SupabaseClient.shared.invokeProcessJob(jobId: jobId)
                        logger.log("🚀 ONBOARDING: Triggered immediate processing of welcome job", level: .info)
                    } catch {
                        // Non-critical - job will be picked up by cron if this fails
                        logger.logError(error, context: "Failed to trigger immediate job processing (will be processed by cron)")
                    }
                }
                
                // Start the welcome countdown for UI purposes
                WelcomeDayStartScheduler.shared.scheduleWelcomeDayStart()
                logger.log("🎉 Welcome DayStart scheduled - user's first briefing is being prepared", level: .info)
                
            } catch {
                logger.logError(error, context: "CRITICAL: Failed to create first job after paywall conversion")
                // Continue with flow even if job creation fails
            }
        }
    }
    
    private func saveOnboardingSettings() {
        logger.log("💾 Saving onboarding settings", level: .info)
        
        let userPreferences = UserPreferences.shared
        
        userPreferences.schedule = DayStartSchedule(
            time: selectedTime,
            repeatDays: selectedDays,
            skipTomorrow: false
        )
        
        let processedStockSymbols = stockSymbols
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && UserSettings.isValidStockSymbol($0) }
        
        userPreferences.settings = UserSettings(
            preferredName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            includeWeather: includeWeather,
            includeNews: includeNews,
            includeSports: includeSports,
            includeStocks: includeStocks,
            stockSymbols: processedStockSymbols,
            includeCalendar: includeCalendar,
            includeQuotes: includeQuotes,
            quotePreference: selectedQuoteType,
            selectedVoice: selectedVoice ?? .voice1,
            dayStartLength: 3, // Default 3 minutes
            themePreference: .system
        )
        userPreferences.saveSettings()
        
        logger.log("✅ Onboarding settings saved successfully", level: .info)
    }
    
    private func completeOnboarding() {
        logger.log("🎓 Completing onboarding flow", level: .info)
        
        // Log final completion
        logger.logUserAction("Onboarding completed", details: [
            "name": name.isEmpty ? "[empty]" : name,
            "scheduledTime": shortTimeFormatter.string(from: selectedTime),
            "selectedDays": selectedDays.map(\.name).joined(separator: ", "),
            "includeWeather": includeWeather,
            "includeNews": includeNews,
            "includeSports": includeSports,
            "includeStocks": includeStocks,
            "includeCalendar": includeCalendar,
            "includeQuotes": includeQuotes,
            "selectedVoice": selectedVoice?.name ?? "[none]"
        ])
        
        // Start welcome DayStart for existing subscribers who skip paywall
        WelcomeDayStartScheduler.shared.scheduleWelcomeDayStart()
        logger.log("🎉 Welcome DayStart scheduled for existing subscriber", level: .info)
        
        // Complete onboarding - settings already saved and job already processing
        onComplete()
    }
    
    // MARK: - Product Helpers (Phase 2)
    
    private func getProduct(for id: String) -> Product? {
        return purchaseManager.availableProducts.first { $0.id == id }
    }
    
    private func getTrialText(for product: Product?) -> String? {
        guard let product = product,
              let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer else {
            return nil
        }
        
        switch introOffer.period.unit {
        case .day:
            return "\(introOffer.period.value)-Day Free Trial"
        case .week:
            return "\(introOffer.period.value)-Week Free Trial"
        case .month:
            return "\(introOffer.period.value)-Month Free Trial"
        case .year:
            return "\(introOffer.period.value)-Year Free Trial"
        @unknown default:
            return "Free Trial"
        }
    }
    
    private func getMonthlyPrice(for product: Product?) -> String? {
        guard let product = product,
              let subscription = product.subscription else {
            return nil
        }
        
        // Phase 3: Use NSDecimalNumber for precise financial calculations
        let price = NSDecimalNumber(decimal: product.price)
        let periodValue = NSDecimalNumber(value: subscription.subscriptionPeriod.value)
        let monthlyPrice = price.dividing(by: periodValue)
        
        return monthlyPrice.doubleValue.formatted(.currency(code: product.priceFormatStyle.currencyCode))
    }
    
    private func getSavingsText(annual: Product?, monthly: Product?) -> String? {
        guard let annual = annual,
              let monthly = monthly,
              let annualSubscription = annual.subscription else {
            return nil
        }
        
        // Phase 3: Use NSDecimalNumber for precise financial calculations
        let annualPrice = NSDecimalNumber(decimal: annual.price)
        let monthlyPrice = NSDecimalNumber(decimal: monthly.price)
        let twelve = NSDecimalNumber(value: 12)
        
        // Calculate total annual cost if paying monthly
        let totalAnnualCost = monthlyPrice.multiplying(by: twelve)
        
        // Calculate savings
        let savings = totalAnnualCost.subtracting(annualPrice)
        let savingsPercentage = savings.dividing(by: totalAnnualCost).multiplying(by: NSDecimalNumber(value: 100))
        
        // Only return savings text if there are actual savings
        guard savingsPercentage.doubleValue > 0 else { return nil }
        
        let roundedSavings = Int(savingsPercentage.doubleValue.rounded())
        return "Save \(roundedSavings)%"
    }
    
    private func getCTAText(for product: Product?) -> String {
        guard let product = product,
              let subscription = product.subscription,
              subscription.introductoryOffer != nil else {
            return "Continue"
        }
        return "Start Free Trial"
    }
    
    private func getCTASubtext(for product: Product?) -> String {
        guard let product = product else { return "" }
        
        if product.id.contains("annual") {
            return "then \(product.displayPrice) annually"
        } else if product.id.contains("monthly") {
            return "then \(product.displayPrice) monthly"
        }
        return "then \(product.displayPrice) auto-renews"
    }
    
    // MARK: - Permission Handling
    
    private func requestLocationPermission() async {
        let locationManager = LocationManager.shared
        let granted = await locationManager.requestLocationPermission()
        
        await MainActor.run {
            // Status will be updated automatically via onReceive monitoring
            // Just update the include weather preference based on result
            includeWeather = granted
            impactFeedback()
            
            // Force sync in case of timing issues
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                syncPermissionStatuses()
            }
        }
        
        logger.log("Location permission request completed: \(granted)", level: .info)
    }
    
    private func requestCalendarPermission() async {
        let calendarManager = CalendarManager.shared
        let granted = await calendarManager.requestCalendarAccess()
        
        await MainActor.run {
            // Status will be updated automatically via onReceive monitoring when app becomes active
            // Just update the include calendar preference based on result
            includeCalendar = granted
            impactFeedback()
            
            // Force sync in case of timing issues
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                syncPermissionStatuses()
            }
        }
        
        logger.log("Calendar permission request completed: \(granted)", level: .info)
    }
    
    // MARK: - Helper Views
    private func soundWaveLine(for index: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(BananaTheme.ColorToken.primary.opacity(0.6))
            .frame(width: 4, height: CGFloat(20 + index * 10))
            .offset(x: CGFloat(30 + index * 8))
            .scaleEffect(y: animationTrigger ? 1.0 + Double(index) * 0.2 : 0.6)
            .animation(.easeInOut(duration: 0.8).repeatForever().delay(Double(index) * 0.1), value: animationTrigger)
    }
    
    private func animatedPhoneView(geometry: GeometryProxy) -> some View {
        ZStack {
            phoneShape(geometry: geometry)
            soundWaves(geometry: geometry)
        }
    }
    
    private func phoneShape(geometry: GeometryProxy) -> some View {
        let phoneWidth = min(120, geometry.size.width * 0.25)
        let phoneHeight = min(180, geometry.size.height * 0.22)
        let screenWidth = min(100, geometry.size.width * 0.21)
        let screenHeight = min(160, geometry.size.height * 0.19)
        
        return RoundedRectangle(cornerRadius: 25)
            .fill(BananaTheme.ColorToken.primary)
            .frame(width: phoneWidth, height: phoneHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black)
                    .frame(width: screenWidth, height: screenHeight)
            )
    }
    
    private func soundWaves(geometry: GeometryProxy) -> some View {
        ForEach(0..<3) { index in
            soundWave(index: index, geometry: geometry)
        }
    }
    
    private func soundWave(index: Int, geometry: GeometryProxy) -> some View {
        let baseSize = 60 + (index * 40)
        let relativeSizeMultiplier = 0.12 + Double(index) * 0.08
        let relativeSize = geometry.size.width * relativeSizeMultiplier
        let waveSize = min(Double(baseSize), relativeSize)
        
        let scale = animationTrigger ? 1.0 + Double(index) * 0.2 : 0.8
        let opacity = animationTrigger ? 0.3 : 0.7
        let animation = Animation.easeInOut(duration: 1.2).repeatForever().delay(Double(index) * 0.2)
        
        return Circle()
            .stroke(BananaTheme.ColorToken.accent, lineWidth: 3)
            .frame(width: waveSize)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(animation, value: animationTrigger)
    }
    
    private func valueDemoText(geometry: GeometryProxy) -> some View {
        VStack(spacing: geometry.size.height * 0.02) {
            mainTitle(geometry: geometry)
            subtitle(geometry: geometry)
        }
    }
    
    private func mainTitle(geometry: GeometryProxy) -> some View {
        let fontSize = min(28, geometry.size.width * 0.07)
        
        return Text("Your AI Morning Companion")
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(BananaTheme.ColorToken.text)
            .multilineTextAlignment(.center)
            .opacity(textOpacity)
    }
    
    private func subtitle(geometry: GeometryProxy) -> some View {
        let fontSize = min(16, geometry.size.width * 0.04)
        let padding = geometry.size.width * 0.10
        
        return Text("A personalized audio briefing that makes every morning better")
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(BananaTheme.ColorToken.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, padding)
            .opacity(textOpacity)
    }
    
    private func floatingIconsView(geometry: GeometryProxy) -> some View {
        let emojis = ["📰", "☁️", "📅", "📈"]
        let fontSize = min(40, geometry.size.width * 0.10)
        
        return HStack(spacing: 20) {
            ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                let scale = animationTrigger ? 1.1 : 0.9
                let delay = Double(index) * 0.2
                let animation = Animation.easeInOut(duration: 1.2).repeatForever().delay(delay)
                
                Text(emoji)
                    .font(.system(size: fontSize))
                    .scaleEffect(scale)
                    .animation(animation, value: animationTrigger)
            }
        }
    }
}

// MARK: - Supporting Views

struct PainPointCard: View {
    let icon: String
    let text: String
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: min(24, geometry.size.width * 0.06)))
            
            Text(text)
                .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(height: min(80, geometry.size.height * 0.1))
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BananaTheme.ColorToken.card)
                .stroke(BananaTheme.ColorToken.border, lineWidth: 1)
        )
    }
}

struct FeaturePreviewCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 6) {
            Text(icon)
                .font(.system(size: min(30, geometry.size.width * 0.075)))
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: min(14, geometry.size.width * 0.035), weight: .bold))
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Text(subtitle)
                    .font(.system(size: min(10, geometry.size.width * 0.025), weight: .medium))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
        }
        .frame(height: min(90, geometry.size.height * 0.11))
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BananaTheme.ColorToken.card)
                .stroke(BananaTheme.ColorToken.primary.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ContentSelectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isSelected: Bool
    let geometry: GeometryProxy
    
    var body: some View {
        Button(action: {
            isSelected.toggle()
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }) {
            VStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: min(40, geometry.size.width * 0.10)))
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: min(16, geometry.size.width * 0.04), weight: .bold))
                        .foregroundColor(isSelected ? .white : BananaTheme.ColorToken.text)
                    
                    Text(subtitle)
                        .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.9) : BananaTheme.ColorToken.secondaryText)
                }
            }
            .frame(height: min(100, geometry.size.height * 0.12))
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                    .stroke(isSelected ? Color.clear : BananaTheme.ColorToken.border, lineWidth: 1)
            )
            .shadow(color: isSelected ? BananaTheme.ColorToken.primary.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct PermissionBenefitRow: View {
    let icon: String
    let text: String
    let geometry: GeometryProxy
    
    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: min(20, geometry.size.width * 0.05)))
            
            Text(text)
                .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.text)
            
            Spacer()
        }
        .padding(.horizontal, geometry.size.width * 0.10)
    }
}

struct VoiceCard: View {
    let voice: VoiceOption
    let isSelected: Bool
    let geometry: GeometryProxy
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: min(30, geometry.size.width * 0.06)))
                    .foregroundColor(isSelected ? .white : BananaTheme.ColorToken.primary)
                
                Text(voice.name)
                    .font(.system(size: min(12, geometry.size.width * 0.03), weight: .bold))
                    .foregroundColor(isSelected ? .white : BananaTheme.ColorToken.text)
                    .lineLimit(1)
                
                Text("Tap to select")
                    .font(.system(size: min(10, geometry.size.width * 0.025), weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : BananaTheme.ColorToken.secondaryText)
                    .lineLimit(1)
            }
            .frame(height: min(100, geometry.size.height * 0.12))
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                    .stroke(isSelected ? Color.clear : BananaTheme.ColorToken.border, lineWidth: 1)
            )
            .shadow(color: isSelected ? BananaTheme.ColorToken.primary.opacity(0.3) : Color.clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct PreviewSummaryCard: View {
    let icon: String
    let title: String
    let geometry: GeometryProxy
    
    var body: some View {
        HStack(spacing: 16) {
            Text(icon)
                .font(.system(size: min(24, geometry.size.width * 0.06)))
            
            Text(title)
                .font(.system(size: min(16, geometry.size.width * 0.04), weight: .semibold))
                .foregroundColor(BananaTheme.ColorToken.text)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: min(20, geometry.size.width * 0.04)))
                .foregroundColor(Color.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BananaTheme.ColorToken.card)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct PricingCard: View {
    let title: String
    let price: String
    let subtitle: String?
    let badge: String?
    let trialText: String
    let renewalText: String
    let savings: String?
    let isSelected: Bool
    let geometry: GeometryProxy
    let animationTrigger: Bool
    let action: () -> Void
    
    var body: some View {
        let isCompactHeight = geometry.size.height < 700
        
        Button(action: action) {
            VStack(spacing: isCompactHeight ? 4 : 8) {
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: isCompactHeight ? 9 : min(10, geometry.size.width * 0.025), weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, isCompactHeight ? 8 : 12)
                        .padding(.vertical, isCompactHeight ? 2 : 4)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(isCompactHeight ? 8 : 12)
                }
                
                VStack(spacing: isCompactHeight ? 1 : 2) {
                    Text(title)
                        .font(.system(size: isCompactHeight ? 16 : min(18, geometry.size.width * 0.045), weight: .bold))
                        .foregroundColor(BananaTheme.ColorToken.text)
                    
                    Text(price)
                        .font(.system(size: isCompactHeight ? 18 : min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: isCompactHeight ? 12 : min(14, geometry.size.width * 0.035), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    
                    if let savings = savings {
                        Text(savings)
                            .font(.system(size: isCompactHeight ? 11 : min(12, geometry.size.width * 0.03), weight: .bold))
                            .foregroundColor(Color.green)
                    }
                    
                    Text("\(trialText) • \(renewalText)")
                        .font(.system(size: isCompactHeight ? 10 : min(11, geometry.size.width * 0.028), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
            }
            .padding(isCompactHeight ? 8 : 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: isCompactHeight ? 12 : 16)
                    .fill(isSelected ? BananaTheme.ColorToken.primary.opacity(0.1) : BananaTheme.ColorToken.card)
                    .stroke(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border, lineWidth: isSelected ? (isCompactHeight ? 2 : 3) : 1)
            )
            .shadow(color: isSelected ? BananaTheme.ColorToken.primary.opacity(0.2) : Color.clear, radius: isCompactHeight ? 4 : 8, x: 0, y: isCompactHeight ? 2 : 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .scaleEffect(isSelected ? (animationTrigger ? 1.03 : 1.02) : 1.0)
        .animation(isSelected ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default, value: animationTrigger)
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let text: String
    let geometry: GeometryProxy
    
    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: min(16, geometry.size.width * 0.04)))
            
            Text(text)
                .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.text)
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

