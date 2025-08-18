import SwiftUI
import StoreKit
import CoreLocation

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

struct Product {
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
    
    private let logger = DebugLogger.shared
    @State private var name = ""
    @State private var selectedTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var selectedDays: Set<WeekDay> = Set([.monday, .tuesday, .wednesday, .thursday, .friday])
    @State private var includeWeather = false
    @State private var includeNews = true
    @State private var includeSports = true
    @State private var includeStocks = true
    @State private var stockSymbols = "SPY, DIA, BTC-USD"
    @State private var includeCalendar = false
    @State private var includeQuotes = true
    @State private var selectedQuoteType: QuotePreference = .inspirational
    @State private var selectedVoice: VoiceOption? = nil
    @State private var dayStartLength = 3
    @State private var selectedProduct: Product?
    
    // Permission states
    @State private var locationPermissionStatus: PermissionStatus = .notDetermined
    @State private var calendarPermissionStatus: PermissionStatus = .notDetermined
    @State private var showingLocationError = false
    @State private var showingCalendarError = false
    
    // Animation states
    @State private var animationTrigger = false
    @State private var heroScale: CGFloat = 1.0
    @State private var textOpacity: Double = 1.0  // Start visible for first page
    
    // Date formatter
    private var shortTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    private let totalPages = 10
    
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
                .onAppear {
                    logger.log("🎓 New onboarding view appeared", level: .info)
                    logger.logUserAction("Onboarding started", details: ["initialPage": currentPage])
                    
                    // Ensure first page animations start properly with a slight delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        startPageAnimation()
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
                            .font(.system(size: min(30, geometry.size.width * 0.08)))
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
                            .font(.system(size: min(32, geometry.size.width * 0.08), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Most people start their day feeling lost and overwhelmed.")
                            .font(.system(size: min(18, geometry.size.width * 0.045), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // Pain points grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    PainPointCard(icon: "❌", text: "Unsure where to start", geometry: geometry)
                    PainPointCard(icon: "❌", text: "Overwhelmed by the day", geometry: geometry)
                    PainPointCard(icon: "❌", text: "No motivation to rise", geometry: geometry)
                    PainPointCard(icon: "❌", text: "Same boring routine", geometry: geometry)
                }
                .padding(.horizontal, geometry.size.width * 0.08)
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
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
                    FeaturePreviewCard(icon: "☁️", title: "Weather", subtitle: "Dress right", geometry: geometry)
                    FeaturePreviewCard(icon: "📅", title: "Calendar", subtitle: "Never miss", geometry: geometry)
                }
                .padding(.horizontal, geometry.size.width * 0.08)
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
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
                        .font(.system(size: min(100, geometry.size.width * 0.2)))
                        .scaleEffect(animationTrigger ? 1.2 : 0.9)
                        .rotationEffect(.degrees(animationTrigger ? 15 : -15))
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animationTrigger)
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Let's Make This Personal")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Your AI will greet you by name each morning")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
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
                        .padding(.horizontal, geometry.size.width * 0.08)
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
                            .foregroundColor(BananaTheme.ColorToken.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
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
                        Text("When Do You Rise?")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("We'll have your briefing ready when you wake up")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Time picker and days selection
                VStack(spacing: geometry.size.height * 0.04) {
                    // Time picker
                    VStack(spacing: 16) {
                        Text("Briefing Time")
                            .font(.system(size: min(18, geometry.size.width * 0.045), weight: .semibold))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .opacity(textOpacity)
                        
                        HStack {
                            Spacer()
                            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: min(120, geometry.size.height * 0.15))
                                .clipped()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(textOpacity)
                    }
                    
                    // Days selection
                    VStack(spacing: 16) {
                        Text("Which Days?")
                            .font(.system(size: min(18, geometry.size.width * 0.045), weight: .semibold))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .opacity(textOpacity)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                            ForEach(WeekDay.allCases, id: \.id) { day in
                                Button(action: {
                                    let wasSelected = selectedDays.contains(day)
                                    if wasSelected {
                                        selectedDays.remove(day)
                                    } else {
                                        selectedDays.insert(day)
                                    }
                                    impactFeedback()
                                }) {
                                    VStack(spacing: 4) {
                                        Text(String(day.name.prefix(1)))
                                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .bold))
                                            .foregroundColor(selectedDays.contains(day) ? .white : BananaTheme.ColorToken.text)
                                        
                                        Text(day.name)
                                            .font(.system(size: min(10, geometry.size.width * 0.025), weight: .medium))
                                            .foregroundColor(selectedDays.contains(day) ? .white : BananaTheme.ColorToken.secondaryText)
                                    }
                                    .frame(width: min(40, geometry.size.width * 0.1), height: min(50, geometry.size.height * 0.06))
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedDays.contains(day) ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                                            .stroke(selectedDays.contains(day) ? Color.clear : BananaTheme.ColorToken.border, lineWidth: 1)
                                    )
                                }
                                .scaleEffect(selectedDays.contains(day) ? 1.05 : 1.0)
                                .animation(.spring(response: 0.3), value: selectedDays.contains(day))
                            }
                        }
                        .padding(.horizontal, geometry.size.width * 0.08)
                        .opacity(textOpacity)
                    }
                    
                    // Preview
                    if !selectedDays.isEmpty {
                        Text("Your briefing will be ready every \(selectedDaysSummary) at \(shortTimeFormatter.string(from: selectedTime))")
                            .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA
                Button(action: {
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
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
                            .opacity(textOpacity)
                        
                        Text("Choose what matters to you most")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
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
                .padding(.horizontal, geometry.size.width * 0.08)
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 6: Weather Permission (60%)
    private var weatherPermissionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
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
                            .frame(width: min(140, geometry.size.width * 0.3))
                        
                        VStack(spacing: 8) {
                            Text("🌤️")
                                .font(.system(size: min(50, geometry.size.width * 0.1)))
                                .scaleEffect(animationTrigger ? 1.1 : 0.9)
                            
                            Image(systemName: "location.fill")
                                .font(.system(size: min(20, geometry.size.width * 0.05)))
                                .foregroundColor(BananaTheme.ColorToken.primary)
                                .scaleEffect(animationTrigger ? 1.2 : 0.8)
                        }
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                    }
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Know Before You Go")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Get dressed right for the day ahead")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // Benefits
                VStack(spacing: 16) {
                    PermissionBenefitRow(icon: "🌡️", text: "Temperature & forecast", geometry: geometry)
                    PermissionBenefitRow(icon: "👕", text: "Outfit suggestions", geometry: geometry)
                    PermissionBenefitRow(icon: "☔", text: "Rain & storm alerts", geometry: geometry)
                }
                .opacity(textOpacity)
                
                // Error state
                if showingLocationError {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Location access needed for weather updates")
                                .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                                .foregroundColor(.red)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                        
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    }
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .transition(.opacity.combined(with: .scale))
                }
                
                Spacer(minLength: geometry.size.height * 0.08)
                
                // Permission button or skip
                VStack(spacing: 16) {
                    if locationPermissionStatus != .granted {
                        Button(action: {
                            Task {
                                await requestLocationPermission()
                            }
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Enable Weather")
                            }
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
                    } else {
                        Button(action: {
                            includeWeather = true
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 6
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Weather Enabled!")
                            }
                            .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(56, geometry.size.height * 0.07))
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                        }
                    }
                    
                    Button(action: {
                        includeWeather = false
                        impactFeedback()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 6
                        }
                    }) {
                        Text("Skip Weather")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 7: Calendar Permission (70%)
    private var calendarPermissionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
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
                            .frame(width: min(120, geometry.size.width * 0.25), height: min(100, geometry.size.height * 0.12))
                        
                        VStack(spacing: 8) {
                            Text("📅")
                                .font(.system(size: min(40, geometry.size.width * 0.08)))
                                .scaleEffect(animationTrigger ? 1.1 : 0.9)
                            
                            // Animated event dots
                            HStack(spacing: 4) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(BananaTheme.ColorToken.primary)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(animationTrigger ? 1.2 : 0.8)
                                        .animation(.easeInOut(duration: 1.0).repeatForever().delay(Double(index) * 0.2), value: animationTrigger)
                                }
                            }
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Never Miss a Beat")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Your meetings and events in your briefing")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // Benefits
                VStack(spacing: 16) {
                    PermissionBenefitRow(icon: "🕰️", text: "Upcoming events overview", geometry: geometry)
                    PermissionBenefitRow(icon: "💼", text: "Meeting preparation tips", geometry: geometry)
                    PermissionBenefitRow(icon: "📅", text: "Schedule optimization", geometry: geometry)
                }
                .opacity(textOpacity)
                
                // Error state
                if showingCalendarError {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Calendar access required for events")
                                .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                                .foregroundColor(.red)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                        
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    }
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .transition(.opacity.combined(with: .scale))
                }
                
                Spacer(minLength: geometry.size.height * 0.08)
                
                // Permission button or skip
                VStack(spacing: 16) {
                    if calendarPermissionStatus != .granted {
                        Button(action: {
                            Task {
                                await requestCalendarPermission()
                            }
                        }) {
                            HStack {
                                Image(systemName: "calendar")
                                Text("Connect Calendar")
                            }
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
                    } else {
                        Button(action: {
                            includeCalendar = true
                            impactFeedback()
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                                currentPage = 7
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Calendar Connected!")
                            }
                            .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(56, geometry.size.height * 0.07))
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                        }
                    }
                    
                    Button(action: {
                        includeCalendar = false
                        impactFeedback()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                            currentPage = 7
                        }
                    }) {
                        Text("Skip Calendar")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 8: Voice Selection (80%)
    private var voiceSelectionPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
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
                            .frame(width: min(140, geometry.size.width * 0.3))
                        
                        Text("🎤")
                            .font(.system(size: min(60, geometry.size.width * 0.12)))
                            .scaleEffect(animationTrigger ? 1.1 : 0.9)
                        
                        // Sound wave lines
                        ForEach(0..<4) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(BananaTheme.ColorToken.primary.opacity(0.6))
                                .frame(width: 4, height: CGFloat(20 + index * 10))
                                .offset(x: CGFloat(30 + index * 8))
                                .scaleEffect(y: animationTrigger ? 1.0 + Double(index) * 0.2 : 0.6)
                                .animation(.easeInOut(duration: 0.8).repeatForever().delay(Double(index) * 0.1), value: animationTrigger)
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Choose Your Voice")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("The voice that starts your day right")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Voice selection cards
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
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
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .opacity(textOpacity)
                    
                    // Voice preview
                    if selectedVoice != nil {
                        VStack(spacing: 12) {
                            Text("Preview")
                                .font(.system(size: min(16, geometry.size.width * 0.04), weight: .semibold))
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            Text("\"Good morning! Your briefing will sound like this...\"")
                                .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium, design: .rounded))
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, geometry.size.width * 0.08)
                                .italic()
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                    
                    // Length slider
                    VStack(spacing: 12) {
                        HStack {
                            Text("Perfect length")
                                .font(.system(size: min(16, geometry.size.width * 0.04), weight: .semibold))
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            Spacer()
                            
                            Text("\(dayStartLength) minutes")
                                .font(.system(size: min(16, geometry.size.width * 0.04), weight: .bold))
                                .foregroundColor(BananaTheme.ColorToken.primary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(dayStartLength) },
                                set: { dayStartLength = Int($0) }
                            ),
                            in: 2...5,
                            step: 1
                        )
                        .accentColor(BananaTheme.ColorToken.primary)
                        
                        Text("Perfect for your commute")
                            .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .opacity(textOpacity)
                }
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA
                Button(action: {
                    logger.logUserAction("Voice selection CTA tapped")
                    impactFeedback()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { 
                        currentPage = 8
                    }
                }) {
                    Text("Love It!")
                        .font(.system(size: min(20, geometry.size.width * 0.05), weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(56, geometry.size.height * 0.07))
                        .background(
                            LinearGradient(
                                colors: isVoiceSelected ? [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent] : [Color.gray, Color.gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: isVoiceSelected ? BananaTheme.ColorToken.primary.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                }
                .disabled(!isVoiceSelected)
                .scaleEffect(animationTrigger && isVoiceSelected ? 1.05 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 9: Final Preview (90%)
    private var finalPreviewPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.08)
                
                VStack(spacing: geometry.size.height * 0.05) {
                    // Sparkle animation
                    HStack(spacing: 20) {
                        ForEach(["✨", "🎆", "✨"], id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: min(50, geometry.size.width * 0.1)))
                                .scaleEffect(animationTrigger ? 1.2 : 0.8)
                                .rotationEffect(.degrees(animationTrigger ? 15 : -15))
                                .animation(.easeInOut(duration: 1.0).repeatForever().delay(Double(["✨", "🎆", "✨"].firstIndex(of: emoji) ?? 0) * 0.3), value: animationTrigger)
                        }
                    }
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Your Morning Transformation")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Tomorrow morning will be different...")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Preview summary
                VStack(spacing: 20) {
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Anticipation text
                Text("Your personalized briefing is almost ready...")
                    .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium, design: .rounded))
                    .foregroundColor(BananaTheme.ColorToken.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, geometry.size.width * 0.08)
                    .opacity(textOpacity)
                    .italic()
                
                Spacer(minLength: geometry.size.height * 0.06)
                
                // CTA
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
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.bottom, max(24, geometry.size.height * 0.03))
                .opacity(textOpacity)
            }
        }
    }
    
    // MARK: - Page 10: Hard Paywall (100%)
    private var paywallPage: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: geometry.size.height * 0.06)
                
                VStack(spacing: geometry.size.height * 0.04) {
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
                            .frame(width: min(120, geometry.size.width * 0.25))
                            .scaleEffect(animationTrigger ? 1.1 : 0.9)
                        
                        Text("🌟")
                            .font(.system(size: min(60, geometry.size.width * 0.12)))
                            .scaleEffect(animationTrigger ? 1.2 : 1.0)
                    }
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                    
                    VStack(spacing: geometry.size.height * 0.02) {
                        Text("Unlock Your Better Mornings")
                            .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                            .opacity(textOpacity)
                        
                        Text("Join thousands who've transformed their mornings")
                            .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, geometry.size.width * 0.08)
                            .opacity(textOpacity)
                    }
                }
                
                Spacer(minLength: geometry.size.height * 0.03)
                
                // Pricing options - optimized for conversion
                VStack(spacing: 12) {
                    PricingCard(
                        title: "Annual Pass",
                        price: "$39.99/year",
                        subtitle: "Just $3.33/month",
                        badge: "🔥 Most Popular",
                        trialText: "7-Day Free Trial",
                        savings: "Save 33%",
                        isSelected: selectedProduct?.id == "annual",
                        geometry: geometry,
                        action: {
                            selectedProduct = Product(id: "annual", displayName: "Annual Pass", description: "Annual subscription", price: 39.99, displayPrice: "$39.99", type: .autoRenewable)
                            impactFeedback()
                        }
                    )
                    
                    PricingCard(
                        title: "Monthly Pass",
                        price: "$4.99/month",
                        subtitle: nil,
                        badge: nil,
                        trialText: "3-Day Free Trial",
                        savings: nil,
                        isSelected: selectedProduct?.id == "monthly",
                        geometry: geometry,
                        action: {
                            selectedProduct = Product(id: "monthly", displayName: "Monthly Pass", description: "Monthly subscription", price: 4.99, displayPrice: "$4.99", type: .autoRenewable)
                            impactFeedback()
                        }
                    )
                }
                .padding(.horizontal, geometry.size.width * 0.08)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.03)
                
                // Urgency banner
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.red)
                    Text("Limited Time: \(selectedProduct?.id == "annual" ? "7-Day" : "3-Day") Free Trial")
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .bold))
                        .foregroundColor(.red)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Main CTA
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
                    VStack(spacing: 4) {
                        Text("Start Free Trial")
                            .font(.system(size: min(22, geometry.size.width * 0.055), weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Then \(selectedProduct?.displayPrice ?? "$3.33")/month")
                            .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: max(64, geometry.size.height * 0.08))
                    .background(
                        LinearGradient(
                            colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: BananaTheme.ColorToken.primary.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .scaleEffect(animationTrigger ? 1.02 : 1.0)
                .padding(.horizontal, geometry.size.width * 0.08)
                .opacity(textOpacity)
                
                Spacer(minLength: geometry.size.height * 0.04)
                
                // Legal links
                HStack(spacing: 16) {
                    Button("Terms") {
                        // Open terms
                    }
                    Text("•")
                    Button("Privacy") {
                        // Open privacy
                    }
                    Text("•")
                    Button("Restore") {
                        // Restore purchases
                    }
                }
                .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .padding(.bottom, max(20, geometry.size.height * 0.025))
                .opacity(textOpacity)
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
        case 5: return "Weather Permission"
        case 6: return "Calendar Permission"
        case 7: return "Voice Selection"
        case 8: return "Final Preview"
        case 9: return "Paywall"
        default: return "Unknown"
        }
    }
    
    private func startPurchaseFlow() {
        logger.log("🛒 Starting purchase flow from paywall", level: .info)
        
        // In a real implementation, this would:
        // 1. Initiate StoreKit purchase
        // 2. Handle purchase result
        // 3. If successful, call completeOnboarding()
        // 4. If failed, show error and stay on paywall
        
        // For now, simulate successful purchase and complete onboarding
        Task {
            // Simulate purchase delay
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await MainActor.run {
                logger.log("✅ Purchase flow completed successfully", level: .info)
                completeOnboarding()
            }
        }
    }
    
    private func completeOnboarding() {
        logger.log("🎓 Starting onboarding completion process", level: .info)
        
        // Log all collected settings
        logger.logUserAction("Onboarding settings collected", details: [
            "name": name.isEmpty ? "[empty]" : name,
            "scheduledTime": shortTimeFormatter.string(from: selectedTime),
            "selectedDays": selectedDays.map(\.name).joined(separator: ", "),
            "includeWeather": includeWeather,
            "includeNews": includeNews,
            "includeSports": includeSports,
            "includeStocks": includeStocks,
            "stockSymbols": stockSymbols.isEmpty ? "[none]" : stockSymbols,
            "includeCalendar": includeCalendar,
            "includeQuotes": includeQuotes,
            "selectedQuoteType": selectedQuoteType.name,
            "selectedVoice": selectedVoice?.name ?? "[none]",
            "dayStartLength": dayStartLength
        ])
        
        // Save settings
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
            dayStartLength: dayStartLength,
            themePreference: .system
        )
        userPreferences.saveSettings()
        
        // CRITICAL: Create the first job immediately after successful paywall conversion
        Task {
            do {
                let snapshot = await SnapshotBuilder.shared.buildSnapshot()
                
                let jobResult = try await SupabaseClient.shared.createJob(
                    for: Date(),
                    with: userPreferences.settings,
                    schedule: userPreferences.schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar
                )
                
                logger.log("✅ ONBOARDING: First job created successfully", level: .info)
                
                // Start the welcome countdown for UI purposes
                WelcomeDayStartScheduler.shared.scheduleWelcomeDayStart()
                logger.log("🎉 Welcome DayStart scheduled - user's first briefing is being prepared", level: .info)
                
            } catch {
                logger.logError(error, context: "CRITICAL: Failed to create first job after paywall conversion")
                // Still proceed with onboarding completion even if job creation fails
                // The user has paid, so we should complete the flow
            }
        }
        
        // Complete onboarding immediately - job creation happens in background
        onComplete()
    }
    
    // MARK: - Permission Handling
    
    private func requestLocationPermission() async {
        let locationManager = LocationManager.shared
        
        // Check current status
        let currentStatus = locationManager.authorizationStatus
        
        if currentStatus == .denied || currentStatus == .restricted {
            await MainActor.run {
                locationPermissionStatus = .denied
                showingLocationError = true
            }
            return
        }
        
        let granted = await locationManager.requestLocationPermission()
        
        await MainActor.run {
            if granted {
                locationPermissionStatus = .granted
                showingLocationError = false
            } else {
                locationPermissionStatus = .denied
                showingLocationError = true
            }
        }
    }
    
    private func requestCalendarPermission() async {
        let calendarManager = CalendarManager.shared
        let granted = await calendarManager.requestCalendarAccess()
        
        await MainActor.run {
            if granted {
                calendarPermissionStatus = .granted
                showingCalendarError = false
            } else {
                calendarPermissionStatus = .denied
                showingCalendarError = true
            }
        }
    }
    
    // MARK: - Helper Views
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
        let padding = geometry.size.width * 0.08
        
        return Text("A personalized audio briefing that makes every morning better")
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(BananaTheme.ColorToken.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, padding)
            .opacity(textOpacity)
    }
    
    private func floatingIconsView(geometry: GeometryProxy) -> some View {
        let emojis = ["📰", "☁️", "📅", "📈"]
        let fontSize = min(40, geometry.size.width * 0.08)
        
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
                    .font(.system(size: min(40, geometry.size.width * 0.08)))
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
        .padding(.horizontal, geometry.size.width * 0.08)
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
    let savings: String?
    let isSelected: Bool
    let geometry: GeometryProxy
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: min(12, geometry.size.width * 0.03), weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: min(18, geometry.size.width * 0.045), weight: .bold))
                        .foregroundColor(BananaTheme.ColorToken.text)
                    
                    Text(price)
                        .font(.system(size: min(24, geometry.size.width * 0.06), weight: .bold))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: min(14, geometry.size.width * 0.035), weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    
                    if let savings = savings {
                        Text(savings)
                            .font(.system(size: min(12, geometry.size.width * 0.03), weight: .bold))
                            .foregroundColor(Color.green)
                    }
                    
                    Text(trialText)
                        .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? BananaTheme.ColorToken.primary.opacity(0.1) : BananaTheme.ColorToken.card)
                    .stroke(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border, lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: isSelected ? BananaTheme.ColorToken.primary.opacity(0.2) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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

