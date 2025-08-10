import SwiftUI
import StoreKit

struct OnboardingView: View {
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    
    private let logger = DebugLogger.shared
    @State private var name = ""
    @State private var textInputTask: Task<Void, Never>?
    @State private var selectedTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var selectedDays: Set<WeekDay> = Set([.monday, .tuesday, .wednesday, .thursday, .friday])
    @State private var includeWeather = false
    @State private var includeNews = true  // Auto-selected
    @State private var includeSports = true  // Auto-selected
    @State private var includeStocks = true  // Auto-selected
    @State private var stockSymbols = "SPY, DIA, BTC-USD"
    @State private var includeCalendar = false
    @State private var includeQuotes = true
    @State private var selectedQuoteType: QuotePreference = .inspirational
    @State private var selectedVoice: VoiceOption? = nil
    @State private var dayStartLength = 5
    @State private var showingPaywall = false
    @State private var selectedProduct: Product?
    
    // Permission states
    @State private var isRequestingLocationPermission = false
    @State private var isRequestingCalendarPermission = false
    @State private var showingLocationPermissionDialog = false
    @State private var showingCalendarPermissionDialog = false
    
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    private let totalPages = 5
    
    var progressPercentage: Double {
        Double(currentPage + 1) / Double(totalPages)
    }
    
    var selectedDaysSummary: String {
        let sortedDays = selectedDays.sorted { $0.rawValue < $1.rawValue }
        
        // Check for common patterns
        if selectedDays.count == 7 {
            return "All days"
        } else if selectedDays.count == 0 {
            return "No days selected"
        } else if selectedDays == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            return "Weekdays"
        } else if selectedDays == Set([.saturday, .sunday]) {
            return "Weekends"
        } else if selectedDays.count == 1 {
            return sortedDays.first!.name
        } else {
            // For custom selections, list the days
            return sortedDays.map { $0.name }.joined(separator: ", ")
        }
    }
    
    var body: some View {
        ZStack {
            // Opaque background to prevent home screen showing through
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
                Text("\(Int(progressPercentage * 100))% Complete")
                    .font(BananaTheme.Typography.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .padding(.top, BananaTheme.Spacing.sm)
                
                // Page content
                TabView(selection: $currentPage) {
                    painPointPage
                        .tag(0)
                    
                    solutionPersonalizationPage
                        .tag(1)
                    
                    contentSelectionPage
                        .tag(2)
                    
                    voiceExperiencePage
                        .tag(3)
                    
                    paywallPage
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                .sensoryFeedback(.selection, trigger: currentPage) { _, _ in
                    false // Disable all haptic feedback during page transitions
                }
                .onAppear {
                    logger.log("🎓 Onboarding view appeared", level: .info)
                    logger.logUserAction("Onboarding started", details: ["initialPage": currentPage])
                }
                .onChange(of: currentPage) { newPage in
                    // Stop any playing voice preview when navigating between pages
                    AudioPlayerManager.shared.stopVoicePreview()
                    
                    logger.logUserAction("Onboarding page changed", details: [
                        "fromPage": currentPage,
                        "toPage": newPage,
                        "pageName": getPageName(for: newPage)
                    ])
                }
            }
        }
    }
    
    // MARK: - Page 1: Pain Point Introduction
    private var painPointPage: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: BananaTheme.Spacing.xl) {
                // Animated emoji transition
                VStack(spacing: BananaTheme.Spacing.md) {
                    Text("😴")
                        .font(.system(size: 100))
                        .scaleEffect(1.2)
                        .animation(
                            Animation.easeInOut(duration: 2)
                                .repeatForever(autoreverses: true),
                            value: currentPage
                        )
                    
                    Text("Mornings Suck. We Get It.")
                        .adaptiveFont(BananaTheme.Typography.largeTitle)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Most people are filled with unorganized dread in the morning.")
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BananaTheme.Spacing.lg)
                }
                
                // Pain points
                VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
                    PainPointRow(text: "Unsure where to start")
                    PainPointRow(text: "Overwhelmed by the day ahead")
                    PainPointRow(text: "No motivation to get up")
                    PainPointRow(text: "Same boring routine")
                }
                .padding(.horizontal, BananaTheme.Spacing.xl)
            }
            
            Spacer()
            
            // CTA Button
            Button(action: { 
                logger.logUserAction("Pain point CTA tapped")
                withAnimation { currentPage = 1 }
            }) {
                Text("Let's Fix This")
                    .adaptiveFont(BananaTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
            }
            .bananaPrimaryButton()
            .padding(.horizontal, BananaTheme.Spacing.xl)
            .padding(.bottom, BananaTheme.Spacing.xl)
        }
    }
    
    // MARK: - Page 2: Solution & Personalization
    private var solutionPersonalizationPage: some View {
        ScrollView {
            VStack(spacing: BananaTheme.Spacing.xl) {
                Spacer(minLength: BananaTheme.Spacing.xl)
                
                // Animated phone with sound waves
                ZStack {
                    Image(systemName: "iphone")
                        .font(.system(size: 80))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 30))
                        .foregroundColor(BananaTheme.ColorToken.accent)
                        .offset(x: 50, y: -20)
                        .scaleEffect(1.2)
                        .animation(
                            Animation.easeInOut(duration: 1)
                                .repeatForever(autoreverses: true),
                            value: currentPage
                        )
                }
                .padding(.bottom)
                
                VStack(spacing: BananaTheme.Spacing.md) {
                    Text("Your Personal Morning Briefing")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .multilineTextAlignment(.center)
                    
                    Text("Have a personalized start to the day ready for you when you wake up.")
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, BananaTheme.Spacing.xl)
                
                // Personalization inputs
                VStack(spacing: BananaTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                        HStack {
                            Text("Your Name")
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            Spacer(minLength: BananaTheme.Spacing.md)
                            
                            TextField("Optional", text: Binding(
                                get: { name },
                                set: { newValue in
                                    textInputTask?.cancel()
                                    let sanitized = String(newValue.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
                                    name = sanitized
                                }
                            ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(BananaTheme.Typography.body)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                        HStack {
                            Text("When should your personalized briefing be ready?")
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            Spacer()
                            
                            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                        Text("Which days?")
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            ForEach(WeekDay.allCases, id: \.id) { day in
                                Button(action: {
                                    let wasSelected = selectedDays.contains(day)
                                    if wasSelected {
                                        selectedDays.remove(day)
                                        logger.logUserAction("Day deselected", details: ["day": day.name])
                                    } else {
                                        selectedDays.insert(day)
                                        logger.logUserAction("Day selected", details: ["day": day.name])
                                    }
                                }) {
                                    Text(day.name)
                                        .font(.caption)
                                        .fontWeight(selectedDays.contains(day) ? .bold : .regular)
                                        .foregroundColor(selectedDays.contains(day) ? .white : BananaTheme.ColorToken.text)
                                        .frame(width: 30, height: 30)
                                        .background(selectedDays.contains(day) ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                                        .clipShape(Circle())
                                }
                                
                                if day != WeekDay.allCases.last {
                                    Spacer()
                                }
                            }
                        }
                        
                        // Days Selected summary
                        HStack {
                            Text("Days Selected:")
                                .font(BananaTheme.Typography.caption)
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            
                            Text(selectedDaysSummary)
                                .font(BananaTheme.Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(BananaTheme.ColorToken.primary)
                        }
                        .padding(.top, BananaTheme.Spacing.xs)
                    }
                }
                .padding(.horizontal, BananaTheme.Spacing.xl)
                
                Text("DayStart creates a personalized audio briefing just for you - like having a trusted friend catch you up on everything that matters")
                    .font(BananaTheme.Typography.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BananaTheme.Spacing.xl)
                
                Spacer(minLength: BananaTheme.Spacing.xl)
                
                // Bottom spacer for better scrolling  
                Spacer(minLength: 60)
            }
        }
        .overlay(
            VStack {
                Spacer()
                
                // Gradient backdrop for navigation buttons
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            BananaTheme.ColorToken.background.opacity(0),
                            BananaTheme.ColorToken.background.opacity(0.8),
                            BananaTheme.ColorToken.background
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .overlay(
                    VStack {
                        Spacer()
                        navigationButtons
                    }
                )
            }
        )
    }
    
    // MARK: - Page 3: Content Selection
    private var contentSelectionPage: some View {
        ScrollView {
            VStack(spacing: BananaTheme.Spacing.xl) {
                Spacer(minLength: BananaTheme.Spacing.xl)
                
                
                VStack(spacing: BananaTheme.Spacing.md) {
                    Text("What gets you started ☕")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .multilineTextAlignment(.center)
                    
                    Text("Choose what to include in your personalized morning briefing.")
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Content toggles
                VStack(spacing: BananaTheme.Spacing.md) {
                    ContentToggleRow(
                        icon: "sun.max.fill",
                        title: "Weather",
                        subtitle: "Start dressed for success",
                        isOn: $includeWeather
                    )
                    .onChange(of: includeWeather) { enabled in
                        if enabled {
                            Task {
                                await requestLocationPermission()
                            }
                        }
                    }
                    
                    ContentToggleRow(
                        icon: "newspaper.fill",
                        title: "News",
                        subtitle: "Stay informed, not overwhelmed",
                        isOn: $includeNews
                    )
                    
                    ContentToggleRow(
                        icon: "sportscourt.fill",
                        title: "Sports",
                        subtitle: "Hot dog eating and others",
                        isOn: $includeSports
                    )
                    
                    ContentToggleRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Stocks",
                        subtitle: "Your portfolio at a glance",
                        isOn: $includeStocks
                    )
                    
                    if includeStocks {
                        VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                            TextField("Enter symbols: SPY, DIA, BTC-USD", text: Binding(
                                get: { stockSymbols },
                                set: { newValue in
                                    textInputTask?.cancel()
                                    let sanitized = String(newValue.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
                                    stockSymbols = sanitized
                                }
                            ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(BananaTheme.Typography.body)
                                .padding(.leading, BananaTheme.Spacing.xl)
                        }
                        .transition(.slide)
                    }
                    
                    ContentToggleRow(
                        icon: "calendar.circle.fill",
                        title: "Calendar",
                        subtitle: "Your events and meetings",
                        isOn: $includeCalendar
                    )
                    .onChange(of: includeCalendar) { enabled in
                        if enabled {
                            Task {
                                await requestCalendarPermission()
                            }
                        }
                    }
                    
                    // Daily Wisdom with integrated Quote Style picker
                    VStack(spacing: 0) {
                        VStack(spacing: BananaTheme.Spacing.sm) {
                            HStack {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.title2)
                                    .foregroundColor(BananaTheme.ColorToken.primary)
                                    .frame(width: 40)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Daily Wisdom")
                                        .adaptiveFont(BananaTheme.Typography.headline)
                                        .foregroundColor(BananaTheme.ColorToken.text)
                                    
                                    Text("Motivation that actually helps")
                                        .font(BananaTheme.Typography.caption)
                                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $includeQuotes)
                                    .labelsHidden()
                                    .tint(BananaTheme.ColorToken.primary)
                            }
                            
                            if includeQuotes {
                                HStack {
                                    Spacer().frame(width: 40) // Align with content above
                                    
                                    Text("Quote Style")
                                        .foregroundColor(BananaTheme.ColorToken.text)
                                    
                                    Spacer()
                                    
                                    Picker("Quote Style", selection: $selectedQuoteType) {
                                        ForEach(QuotePreference.allCases, id: \.self) { preference in
                                            Text(preference.name).tag(preference)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .accentColor(BananaTheme.ColorToken.primary)
                                }
                                .transition(.slide)
                            }
                        }
                        .padding(.vertical, BananaTheme.Spacing.sm)
                        .padding(.horizontal, BananaTheme.Spacing.md)
                        .background(BananaTheme.ColorToken.card)
                        .cornerRadius(BananaTheme.CornerRadius.md)
                    }
                }
                .padding(.horizontal, BananaTheme.Spacing.lg)
                
                Spacer(minLength: BananaTheme.Spacing.xl)
                
                // Bottom spacer to prevent content being covered
                Spacer(minLength: 110)
            }
        }
        .overlay(
            VStack {
                Spacer()
                
                // Gradient backdrop for navigation buttons
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            BananaTheme.ColorToken.background.opacity(0),
                            BananaTheme.ColorToken.background.opacity(0.8),
                            BananaTheme.ColorToken.background
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .overlay(
                    VStack {
                        Spacer()
                        navigationButtons
                    }
                )
            }
        )
    }
    
    // MARK: - Page 4: Voice & Experience
    private var voiceExperiencePage: some View {
        ScrollView {
            VStack(spacing: BananaTheme.Spacing.xl) {
                Spacer(minLength: BananaTheme.Spacing.xl)
                
                // Voice waveform animation
                Image(systemName: "waveform")
                    .font(.system(size: 80))
                    .foregroundColor(BananaTheme.ColorToken.primary)
                    .scaleEffect(x: 1.2, y: 1, anchor: .center)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: currentPage
                    )
                    .padding(.bottom)
                
                VStack(spacing: BananaTheme.Spacing.md) {
                    Text("Your Perfect Morning Voice")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .multilineTextAlignment(.center)
                    
                    Text("Choose how you want to start your day")
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Voice selection
                VStack(spacing: BananaTheme.Spacing.lg) {
                    Text("Select Voice")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: BananaTheme.Spacing.md) {
                        ForEach(VoiceOption.allCases, id: \.rawValue) { voice in
                            VoiceSelectionCard(
                                voice: voice,
                                isSelected: selectedVoice == voice,
                                onSelect: {
                                    logger.logUserAction("Voice selected in onboarding", details: [
                                        "voice": voice.name,
                                        "voiceRawValue": voice.rawValue
                                    ])
                                    selectedVoice = voice
                                    AudioPlayerManager.shared.previewVoice(voice)
                                }
                            )
                        }
                    }
                    
                    // Briefing length
                    VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
                        HStack {
                            Text("Briefing Length")
                                .adaptiveFont(BananaTheme.Typography.headline)
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            Spacer()
                            
                            Text("\(dayStartLength) minutes")
                                .font(BananaTheme.Typography.body)
                                .foregroundColor(BananaTheme.ColorToken.primary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(dayStartLength) },
                                set: { dayStartLength = Int($0) }
                            ),
                            in: 2...10,
                            step: 1
                        )
                        .accentColor(BananaTheme.ColorToken.primary)
                    }
                }
                .padding(.horizontal, BananaTheme.Spacing.lg)
                
                
                
                Spacer(minLength: BananaTheme.Spacing.xl)
                
                // Additional bottom spacing for voice page
                Spacer(minLength: 20)
            }
        }
        .overlay(
            VStack {
                Spacer()
                
                // Gradient backdrop for navigation buttons
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            BananaTheme.ColorToken.background.opacity(0),
                            BananaTheme.ColorToken.background.opacity(0.8),
                            BananaTheme.ColorToken.background
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .overlay(
                    VStack {
                        Spacer()
                        navigationButtons
                    }
                )
            }
        )
    }
    
    // MARK: - Page 5: Paywall
    private var paywallPage: some View {
        ScrollView {
            VStack(spacing: BananaTheme.Spacing.md) {
                // Premium badge
                VStack(spacing: BananaTheme.Spacing.md) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Unlock Your Better Mornings")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .multilineTextAlignment(.center)
                    
                    Text("Join others who've transformed their mornings")
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, BananaTheme.Spacing.xl)
                
                // Compact social proof - commented out until we have more reviews
                // HStack {
                //     ForEach(0..<5) { _ in
                //         Image(systemName: "star.fill")
                //             .foregroundColor(BananaTheme.ColorToken.primary)
                //             .font(.caption)
                //     }
                //     Text("4.8 from 5,000+ reviews")
                //         .font(BananaTheme.Typography.caption)
                //         .foregroundColor(BananaTheme.ColorToken.secondaryText)
                // }
                
                // Compact pricing options
                VStack(spacing: BananaTheme.Spacing.sm) {
                    PricingOptionCard(
                        title: "Annual Pass",
                        price: "$39.99/year",
                        subtitle: "Just $3.33/month",
                        trialText: "7-day free trial",
                        isMostPopular: true,
                        isSelected: selectedProduct?.id == "annual",
                        action: {
                            // Select annual product
                        }
                    )
                    
                    PricingOptionCard(
                        title: "Monthly Pass",
                        price: "$4.99/month",
                        subtitle: nil,
                        trialText: "3-day free trial",
                        isMostPopular: false,
                        isSelected: selectedProduct?.id == "monthly",
                        action: {
                            // Select monthly product
                        }
                    )
                }
                .padding(.horizontal, BananaTheme.Spacing.lg)
                
                // CTA Button (moved higher)
                Button(action: {
                    // Start purchase flow
                    completeOnboarding()
                }) {
                    Text("Start Free Trial")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                }
                .bananaPrimaryButton()
                .padding(.horizontal, BananaTheme.Spacing.xl)
                
                // Compact features list
                VStack(alignment: .leading, spacing: BananaTheme.Spacing.xs) {
                    FeatureRow(text: "A personal briefing every day")
                    FeatureRow(text: "High quality AI voices")
                    FeatureRow(text: "Advanced AI customization")
                    FeatureRow(text: "Better starts to the day, DayStarts")
                }
                .padding(.horizontal, BananaTheme.Spacing.xl)
                
                // Legal links
                HStack(spacing: BananaTheme.Spacing.md) {
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
                .font(BananaTheme.Typography.caption)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .padding(.bottom, BananaTheme.Spacing.xl)
            }
        }
    }
    
    // MARK: - Navigation
    private var navigationButtons: some View {
        HStack {
            if currentPage > 0 && currentPage < totalPages - 1 {
                Button(action: {
                    withAnimation {
                        currentPage -= 1
                    }
                }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(BananaTheme.Typography.body)
                }
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            
            Spacer()
            
            if currentPage < totalPages - 1 {
                Button(action: {
                    withAnimation {
                        currentPage += 1
                    }
                }) {
                    Text(currentPage == 0 ? "Let's Fix This" : currentPage == 3 ? "Finalize Setup" : currentPage == 2 ? "Almost There!" : "Customize My Briefing")
                        .adaptiveFont(BananaTheme.Typography.headline)
                }
                .bananaPrimaryButton()
                .disabled(currentPage == 3 && selectedVoice == nil)
                .opacity(currentPage == 3 && selectedVoice == nil ? 0.5 : 1.0)
            }
        }
        .padding(.horizontal, BananaTheme.Spacing.xl)
        .padding(.bottom, BananaTheme.Spacing.xl)
    }
    
    // MARK: - Helper Functions
    
    private func getPageName(for page: Int) -> String {
        switch page {
        case 0: return "Pain Point"
        case 1: return "Personalization"
        case 2: return "Content Selection"
        case 3: return "Voice Experience"
        case 4: return "Paywall"
        default: return "Unknown"
        }
    }
    
    private func getButtonText(for page: Int) -> String {
        switch page {
        case 0: return "Let's Fix This"
        case 1: return "Customize My Briefing"
        case 2: return "Almost There!"
        case 3: return "Finalize Setup"
        default: return "Continue"
        }
    }
    
    private func completeOnboarding() {
        logger.log("🎓 Starting onboarding completion process", level: .info)
        
        // Log all collected settings
        logger.logUserAction("Onboarding settings collected", details: [
            "name": name.isEmpty ? "[empty]" : name,
            "scheduledTime": DateFormatter.shortTime.string(from: selectedTime),
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
        
        // Schedule notifications
        Task {
            await NotificationScheduler.shared.scheduleNotifications(for: userPreferences.schedule)
        }
        
        // Request permissions for enabled features
        Task {
            await requestRequiredPermissions()
            
            // Schedule welcome DayStart for 10 minutes from now
            WelcomeDayStartScheduler.shared.scheduleWelcomeDayStart()
            logger.log("🎉 Welcome DayStart scheduled for new user", level: .info)
            
            onComplete()
        }
    }
    
    // MARK: - Permission Handling
    
    private func requestRequiredPermissions() async {
        var permissionsNeeded: [String] = []
        
        // Check what permissions we need based on selected features
        if includeWeather {
            permissionsNeeded.append("location for weather")
        }
        if includeCalendar {
            permissionsNeeded.append("calendar access")
        }
        
        // Request location permission if weather is enabled
        if includeWeather {
            await requestLocationPermission()
        }
        
        // Request calendar permission if calendar is enabled
        if includeCalendar {
            await requestCalendarPermission()
        }
    }
    
    func cleanup() {
        textInputTask?.cancel()
    }
    
    private func requestLocationPermission() async {
        let locationManager = LocationManager.shared
        let granted = await locationManager.requestLocationPermission()
        
        if !granted {
            // If permission denied, disable weather feature
            await MainActor.run {
                includeWeather = false
            }
        }
    }
    
    private func requestCalendarPermission() async {
        let calendarManager = CalendarManager.shared
        let granted = await calendarManager.requestCalendarAccess()
        
        if !granted {
            // If permission denied, disable calendar feature
            await MainActor.run {
                includeCalendar = false
            }
        }
    }
}

// MARK: - Supporting Views

struct PainPointRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: BananaTheme.Spacing.sm) {
            Text("❌")
                .font(.title3)
            Text(text)
                .font(BananaTheme.Typography.body)
                .foregroundColor(BananaTheme.ColorToken.text)
        }
    }
}

struct ContentTypeIcon: View {
    let icon: String
    let color: Color
    
    var body: some View {
        Image(systemName: icon)
            .font(.title2)
            .foregroundColor(color)
            .frame(width: 50, height: 50)
            .background(color.opacity(0.1))
            .cornerRadius(BananaTheme.CornerRadius.sm)
    }
}

struct ContentToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(BananaTheme.ColorToken.primary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .adaptiveFont(BananaTheme.Typography.headline)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Text(subtitle)
                    .font(BananaTheme.Typography.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(BananaTheme.ColorToken.primary)
        }
        .padding(.vertical, BananaTheme.Spacing.sm)
        .padding(.horizontal, BananaTheme.Spacing.md)
        .background(BananaTheme.ColorToken.card)
        .cornerRadius(BananaTheme.CornerRadius.md)
    }
}

struct DayToggleButton: View {
    let day: WeekDay
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(String(day.name.prefix(3)))
                .font(BananaTheme.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? BananaTheme.ColorToken.background : BananaTheme.ColorToken.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(isSelected ? BananaTheme.ColorToken.primary : Color.clear)
                .cornerRadius(BananaTheme.CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.sm)
                        .stroke(BananaTheme.ColorToken.primary, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VoiceSelectionCard: View {
    let voice: VoiceOption
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: BananaTheme.Spacing.sm) {
            Button(action: onSelect) {
                VStack(spacing: BananaTheme.Spacing.sm) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.title)
                        .foregroundColor(isSelected ? BananaTheme.ColorToken.background : BananaTheme.ColorToken.primary)
                    
                    Text(voice.name)
                        .font(BananaTheme.Typography.caption)
                        .fontWeight(isSelected ? .bold : .regular)
                        .foregroundColor(isSelected ? BananaTheme.ColorToken.background : BananaTheme.ColorToken.text)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                .cornerRadius(BananaTheme.CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.md)
                        .stroke(BananaTheme.ColorToken.primary, lineWidth: isSelected ? 0 : 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct TestimonialCard: View {
    let quote: String
    let author: String
    
    var body: some View {
        VStack(spacing: BananaTheme.Spacing.sm) {
            Text("\"\(quote)\"")
                .font(BananaTheme.Typography.caption)
                .foregroundColor(BananaTheme.ColorToken.text)
                .multilineTextAlignment(.center)
                .italic()
            
            Text("— \(author)")
                .font(BananaTheme.Typography.caption2)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(BananaTheme.ColorToken.card)
        .cornerRadius(BananaTheme.CornerRadius.md)
    }
}

struct PricingOptionCard: View {
    let title: String
    let price: String
    let subtitle: String?
    let trialText: String
    let isMostPopular: Bool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: BananaTheme.Spacing.sm) {
                if isMostPopular {
                    Text("🔥 Most Popular")
                        .font(BananaTheme.Typography.caption)
                        .fontWeight(.bold)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .padding(.horizontal, BananaTheme.Spacing.md)
                        .padding(.vertical, BananaTheme.Spacing.xs)
                        .background(BananaTheme.ColorToken.primary)
                        .cornerRadius(BananaTheme.CornerRadius.sm)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.text)
                    
                    Text(price)
                        .adaptiveFont(BananaTheme.Typography.title2)
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(BananaTheme.Typography.caption)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    
                    Text(trialText)
                        .font(BananaTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(BananaTheme.ColorToken.accent)
                }
                .padding(.vertical, BananaTheme.Spacing.md)
            }
            .frame(maxWidth: .infinity)
            .background(isSelected ? BananaTheme.ColorToken.primary.opacity(0.4) : BananaTheme.ColorToken.card)
            .cornerRadius(BananaTheme.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.md)
                    .stroke(
                        isSelected ? Color.blue : BananaTheme.ColorToken.border,
                        lineWidth: isSelected ? 4 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.blue.opacity(0.5) : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: 0
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: BananaTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(BananaTheme.ColorToken.success)
                .font(.body)
            
            Text(text)
                .font(BananaTheme.Typography.body)
                .foregroundColor(BananaTheme.ColorToken.text)
            
            Spacer()
        }
    }
}



// MARK: - Extensions
private extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
