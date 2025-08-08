import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    @State private var name = ""
    @State private var selectedTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var selectedDays: Set<WeekDay> = Set(WeekDay.allCases)
    @State private var includeWeather = true
    @State private var includeNews = true
    @State private var includeSports = false
    @State private var includeStocks = true
    @State private var stockSymbols = "AAPL, TSLA, SPY"
    @State private var includeQuotes = true
    @State private var quotePreference: QuotePreference = .inspirational
    @State private var selectedVoice: VoiceOption = .voice1
    @State private var dayStartLength = 5
    @State private var themePreference: ThemePreference = .system
    
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    private let pages = OnboardingPage.allPages
    
    var body: some View {
        ZStack {
            // Background
            OnboardingGradientBackground()
            
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(for: pages[index], at: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                
                // Navigation buttons
                navigationButtons
            }
        }
        .onAppear {
            setupInitialValues()
        }
    }
    
    // MARK: - Progress Indicator
    private var progressIndicator: some View {
        VStack(spacing: BananaTheme.Spacing.md) {
            HStack {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentPage ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border)
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentPage ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                    
                    if index < pages.count - 1 {
                        Rectangle()
                            .fill(index < currentPage ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border)
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
            }
            .padding(.horizontal, BananaTheme.Spacing.xl)
            
            Text("Step \(currentPage + 1) of \(pages.count)")
                .font(BananaTheme.Typography.caption)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
        }
        .padding(.top, BananaTheme.Spacing.lg)
    }
    
    // MARK: - Page View
    @ViewBuilder
    private func pageView(for page: OnboardingPage, at index: Int) -> some View {
        ScrollView {
            VStack(spacing: BananaTheme.Spacing.lg) {
                Spacer(minLength: BananaTheme.Spacing.md)
                
                // Page icon
                Image(systemName: page.icon)
                    .font(.system(size: 60))
                    .foregroundColor(BananaTheme.ColorToken.primary)
                    .padding(.bottom, BananaTheme.Spacing.sm)
                
                // Title and description
                VStack(spacing: BananaTheme.Spacing.sm) {
                    Text(page.title)
                        .font(BananaTheme.Typography.title)
                        .foregroundColor(BananaTheme.ColorToken.primaryText)
                        .multilineTextAlignment(.center)
                        .adaptiveFontWeight(light: .semibold, dark: .medium)
                    
                    Text(page.description)
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BananaTheme.Spacing.md)
                }
                
                // Page content
                pageContent(for: page)
                    .padding(.horizontal, BananaTheme.Spacing.md)
                
                Spacer(minLength: BananaTheme.Spacing.xl)
            }
        }
    }
    
    // MARK: - Page Content
    @ViewBuilder
    private func pageContent(for page: OnboardingPage) -> some View {
        switch page {
        case .welcome:
            welcomeContent
        case .personalization:
            personalizationContent
        case .schedule:
            scheduleContent
        case .content:
            contentPreferencesContent
        case .voice:
            voiceAndLengthContent
        case .theme:
            themeSelectionContent
        case .permissions:
            permissionsContent
        case .complete:
            completionContent
        }
    }
    
    // MARK: - Welcome Content
    private var welcomeContent: some View {
        VStack(spacing: BananaTheme.Spacing.lg) {
            Text("🌅")
                .font(.system(size: 80))
            
            Text("Welcome to DayStart!")
                .font(BananaTheme.Typography.title2)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
                .multilineTextAlignment(.center)
            
            Text("Your personalized morning briefing, tailored just for you")
                .font(BananaTheme.Typography.body)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .bananaCardStyle()
        .padding(.horizontal)
    }
    
    // MARK: - Personalization Content
    private var personalizationContent: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            Text("What should we call you?")
                .font(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            TextField("Your name (optional)", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(BananaTheme.Typography.body)
            
            Text("We'll use this to personalize your briefings")
                .font(BananaTheme.Typography.caption)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
        }
        .bananaCardStyle()
    }
    
    // MARK: - Schedule Content
    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            Text("When would you like your briefings?")
                .font(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            HStack {
                Text("Time")
                    .font(BananaTheme.Typography.body)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
                
                Spacer()
                
                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accentColor(BananaTheme.ColorToken.primary)
            }
            
            Divider()
            
            Text("Days")
                .font(BananaTheme.Typography.body)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: BananaTheme.Spacing.sm) {
                ForEach(WeekDay.allCases, id: \.id) { weekDay in
                    OnboardingDayButton(
                        weekDay: weekDay,
                        isSelected: selectedDays.contains(weekDay)
                    ) {
                        toggleDay(weekDay)
                    }
                }
            }
        }
        .bananaCardStyle()
    }
    
    // MARK: - Content Preferences Content
    private var contentPreferencesContent: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            Text("What would you like to hear about?")
                .font(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            VStack(spacing: BananaTheme.Spacing.sm) {
                OnboardingToggleRow(
                    title: "Weather",
                    icon: "cloud.sun",
                    description: "Local weather conditions",
                    isOn: $includeWeather
                )
                
                OnboardingToggleRow(
                    title: "News",
                    icon: "newspaper",
                    description: "Top headlines and stories",
                    isOn: $includeNews
                )
                
                OnboardingToggleRow(
                    title: "Sports",
                    icon: "sportscourt",
                    description: "Latest sports updates",
                    isOn: $includeSports
                )
                
                OnboardingToggleRow(
                    title: "Stocks",
                    icon: "chart.line.uptrend.xyaxis",
                    description: "Market updates for your symbols",
                    isOn: $includeStocks
                )
                
                if includeStocks {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stock Symbols")
                            .font(BananaTheme.Typography.caption)
                            .foregroundColor(BananaTheme.ColorToken.primaryText)
                        
                        TextField("AAPL, TSLA, SPY", text: $stockSymbols)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(BananaTheme.Typography.body)
                    }
                    .padding(.leading, BananaTheme.Spacing.lg)
                }
                
                OnboardingToggleRow(
                    title: "Daily Quote",
                    icon: "quote.bubble",
                    description: "Inspiration to start your day",
                    isOn: $includeQuotes
                )
                
                if includeQuotes {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quote Style")
                            .font(BananaTheme.Typography.caption)
                            .foregroundColor(BananaTheme.ColorToken.primaryText)
                        
                        Picker("Quote Preference", selection: $quotePreference) {
                            ForEach(QuotePreference.allCases, id: \.rawValue) { preference in
                                Text(preference.name).tag(preference)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .padding(.leading, BananaTheme.Spacing.lg)
                }
            }
        }
        .bananaCardStyle()
    }
    
    // MARK: - Voice and Length Content
    private var voiceAndLengthContent: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            Text("Customize your experience")
                .font(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            VStack(spacing: BananaTheme.Spacing.md) {
                HStack {
                    Text("Voice")
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.primaryText)
                    
                    Spacer()
                    
                    Picker("Voice", selection: $selectedVoice) {
                        ForEach(VoiceOption.allCases, id: \.rawValue) { voice in
                            Text(voice.name).tag(voice)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .accentColor(BananaTheme.ColorToken.primary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                    HStack {
                        Text("Briefing Length")
                            .font(BananaTheme.Typography.body)
                            .foregroundColor(BananaTheme.ColorToken.primaryText)
                        
                        Spacer()
                        
                        Text("\(dayStartLength) minutes")
                            .font(BananaTheme.Typography.body)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(dayStartLength) },
                            set: { dayStartLength = Int($0) }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    .accentColor(BananaTheme.ColorToken.primary)
                }
            }
        }
        .bananaCardStyle()
    }
    
    // MARK: - Theme Selection Content
    private var themeSelectionContent: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            Text("Choose your preferred appearance")
                .font(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            VStack(spacing: BananaTheme.Spacing.sm) {
                ForEach(ThemePreference.allCases, id: \.self) { preference in
                    OnboardingThemeOption(
                        preference: preference,
                        isSelected: themePreference == preference
                    ) {
                        themePreference = preference
                        themeManager.setTheme(preference)
                    }
                }
            }
        }
        .bananaCardStyle()
    }
    
    // MARK: - Permissions Content
    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            Text("Enable notifications")
                .font(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
            
            VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                Label("Get notified when your briefing is ready", systemImage: "bell")
                    .font(BananaTheme.Typography.body)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
                
                Label("Never miss your scheduled DayStart", systemImage: "clock")
                    .font(BananaTheme.Typography.body)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
                
                Label("Customize notification times", systemImage: "gear")
                    .font(BananaTheme.Typography.body)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
            }
            
            Text("You can change this later in Settings")
                .font(BananaTheme.Typography.caption)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .padding(.top, BananaTheme.Spacing.sm)
        }
        .bananaCardStyle()
    }
    
    // MARK: - Completion Content
    private var completionContent: some View {
        VStack(spacing: BananaTheme.Spacing.lg) {
            Text("🎉")
                .font(.system(size: 80))
            
            Text("You're all set!")
                .font(BananaTheme.Typography.title2)
                .foregroundColor(BananaTheme.ColorToken.primaryText)
                .multilineTextAlignment(.center)
            
            Text("Your personalized DayStart briefings will be delivered according to your schedule.")
                .font(BananaTheme.Typography.body)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: BananaTheme.Spacing.sm) {
                Text("Your Settings:")
                    .font(BananaTheme.Typography.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
                    .fontWeight(.medium)
                
                Text("• Time: \(formattedTime)")
                Text("• Days: \(selectedDaysString)")
                Text("• Voice: \(selectedVoice.name)")
                Text("• Length: \(dayStartLength) minutes")
            }
            .font(BananaTheme.Typography.caption)
            .foregroundColor(BananaTheme.ColorToken.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bananaCardStyle()
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: BananaTheme.Spacing.md) {
            if currentPage > 0 {
                Button("Back") {
                    withAnimation {
                        currentPage -= 1
                    }
                }
                .bananaSecondaryButton()
            }
            
            // Skip button on first few pages
            if currentPage < 3 {
                Button("Skip Setup") {
                    completeOnboarding()
                }
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .font(BananaTheme.Typography.body)
            }
            
            Spacer()
            
            Button(currentPage == pages.count - 1 ? "Get Started" : "Next") {
                if currentPage == pages.count - 1 {
                    completeOnboarding()
                } else {
                    withAnimation {
                        currentPage += 1
                    }
                }
            }
            .bananaPrimaryButton()
        }
        .padding(.horizontal, BananaTheme.Spacing.lg)
        .padding(.bottom, BananaTheme.Spacing.lg)
    }
    
    // MARK: - Helper Functions
    private func setupInitialValues() {
        themePreference = themeManager.themePreference
    }
    
    private func toggleDay(_ weekDay: WeekDay) {
        if selectedDays.contains(weekDay) {
            selectedDays.remove(weekDay)
        } else {
            selectedDays.insert(weekDay)
        }
    }
    
    private func completeOnboarding() {
        // Save all settings
        let userPreferences = UserPreferences.shared
        
        // Create schedule
        userPreferences.schedule = DayStartSchedule(
            time: selectedTime,
            repeatDays: selectedDays,
            skipTomorrow: false
        )
        
        // Create settings
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
            includeCalendar: false,
            includeQuotes: includeQuotes,
            quotePreference: quotePreference,
            selectedVoice: selectedVoice,
            dayStartLength: dayStartLength,
            themePreference: themePreference
        )
        
        // Apply theme immediately
        themeManager.setTheme(themePreference)
        
        // Schedule notifications
        Task {
            await NotificationScheduler.shared.scheduleNotifications(for: userPreferences.schedule)
        }
        
        DebugLogger.shared.logUserAction("Complete Onboarding", details: [
            "name": name,
            "scheduledTime": selectedTime,
            "selectedDays": selectedDays.count,
            "contentOptions": [includeWeather, includeNews, includeSports, includeStocks, includeQuotes]
        ])
        
        onComplete()
    }
    
    // MARK: - Computed Properties
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: selectedTime)
    }
    
    private var selectedDaysString: String {
        selectedDays.sorted { $0.rawValue < $1.rawValue }
            .map { $0.name }
            .joined(separator: ", ")
    }
}

// MARK: - Onboarding Page Definition
enum OnboardingPage: CaseIterable {
    case welcome
    case personalization
    case schedule
    case content
    case voice
    case theme
    case permissions
    case complete
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to DayStart"
        case .personalization:
            return "Let's personalize your experience"
        case .schedule:
            return "Set your schedule"
        case .content:
            return "Choose your content"
        case .voice:
            return "Voice & timing"
        case .theme:
            return "Pick your style"
        case .permissions:
            return "Stay informed"
        case .complete:
            return "Ready to start!"
        }
    }
    
    var description: String {
        switch self {
        case .welcome:
            return "Start every morning with a personalized briefing tailored to your interests"
        case .personalization:
            return "Help us make your briefings feel personal"
        case .schedule:
            return "When and how often would you like your briefings?"
        case .content:
            return "Select the topics that matter most to you"
        case .voice:
            return "Choose your preferred voice and briefing length"
        case .theme:
            return "Select the appearance that suits you best"
        case .permissions:
            return "Allow notifications so you never miss your briefing"
        case .complete:
            return "Everything is configured and ready to go"
        }
    }
    
    var icon: String {
        switch self {
        case .welcome:
            return "sun.max"
        case .personalization:
            return "person.circle"
        case .schedule:
            return "clock"
        case .content:
            return "list.bullet"
        case .voice:
            return "speaker.wave.2"
        case .theme:
            return "paintbrush"
        case .permissions:
            return "bell"
        case .complete:
            return "checkmark.circle"
        }
    }
    
    static var allPages: [OnboardingPage] {
        return OnboardingPage.allCases
    }
}

// MARK: - Supporting Views
struct OnboardingToggleRow: View {
    let title: String
    let icon: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon)
                    .font(BananaTheme.Typography.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
                
                Text(description)
                    .font(BananaTheme.Typography.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(BananaTheme.ColorToken.primary)
        }
    }
}

struct OnboardingDayButton: View {
    let weekDay: WeekDay
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(weekDay.name)
                .font(BananaTheme.Typography.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : BananaTheme.ColorToken.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BananaTheme.Spacing.sm)
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

struct OnboardingThemeOption: View {
    let preference: ThemePreference
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: BananaTheme.Spacing.md) {
                ThemePreviewIcon(preference: preference)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preference.displayName)
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.primaryText)
                    
                    Text(themeDescription)
                        .font(BananaTheme.Typography.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(BananaTheme.ColorToken.primary)
                }
            }
            .padding(.vertical, BananaTheme.Spacing.sm)
            .padding(.horizontal, BananaTheme.Spacing.md)
            .background(isSelected ? BananaTheme.ColorToken.primary.opacity(0.1) : Color.clear)
            .cornerRadius(BananaTheme.CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.sm)
                    .stroke(
                        isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var themeDescription: String {
        switch preference {
        case .system:
            return "Follows your device settings"
        case .light:
            return "Always light appearance"
        case .dark:
            return "Always dark appearance"
        }
    }
}

// MARK: - Preview
#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OnboardingView(onComplete: {})
                .previewDisplayName("Light Mode")
                .preferredColorScheme(.light)
            
            OnboardingView(onComplete: {})
                .previewDisplayName("Dark Mode")
                .preferredColorScheme(.dark)
        }
    }
}
#endif