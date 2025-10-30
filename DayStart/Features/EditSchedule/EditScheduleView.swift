import SwiftUI
import CoreLocation

struct EditScheduleView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var userPreferences: UserPreferences
    
    @State private var selectedTime: Date
    @State private var selectedDays: Set<WeekDay>
    @State private var skipTomorrow: Bool
    @State private var preferredName: String
    @State private var includeWeather: Bool
    @State private var includeNews: Bool
    @State private var includeSports: Bool
    @State private var includeStocks: Bool
    @State private var includeCalendar: Bool
    @State private var includeQuotes: Bool
    @State private var quotePreference: QuotePreference
    @State private var stockSymbolItems: [StockSymbolItem] = []
    @State private var selectedSports: [SportType] = []
    @State private var selectedVoice: VoiceOption
    @State private var showResetConfirmation = false
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showVoicePicker = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var textInputTask: Task<Void, Never>?
    @State private var showFeedbackSheet = false
    @State private var toastMessage: String = ""
    @State private var showToast = false
    @State private var showingLocationDeniedAlert = false
    @State private var showingCalendarDeniedAlert = false
    @State private var showingDiscardAlert = false
    
    private let logger = DebugLogger.shared
    
    private var isLocked: Bool {
        if let next = userPreferences.schedule.nextOccurrence {
            return userPreferences.isWithinLockoutPeriod(of: next)
        }
        return false
    }
    
    private var previewNextOccurrence: Date? {
        let previewSchedule = DayStartSchedule(
            time: selectedTime,
            repeatDays: selectedDays,
            skipTomorrow: skipTomorrow
        )
        return previewSchedule.nextOccurrence
    }
    
    private var isTomorrowInSchedule: Bool {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let tomorrowWeekday = calendar.component(.weekday, from: tomorrow)
        guard let tomorrowWeekDay = WeekDay(weekday: tomorrowWeekday) else { return false }
        return selectedDays.contains(tomorrowWeekDay)
    }
    
    private func previewDescription(for nextTime: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextOccurrenceDay = calendar.startOfDay(for: nextTime)
        
        if nextOccurrenceDay == today {
            return "Today's DayStart"
        } else if nextOccurrenceDay == tomorrow {
            return "Tomorrow's DayStart"
        } else {
            return "Next DayStart"
        }
    }
    
    // Detect if there are unsaved changes compared to persisted preferences
    private var hasUnsavedChanges: Bool {
        // Compare schedule fields - use effective time to handle timezone-independent comparison
        let timeChanged = abs(selectedTime.timeIntervalSince(userPreferences.schedule.effectiveTime)) > 1.0
        let daysChanged = selectedDays != userPreferences.schedule.repeatDays
        // let skipTomorrowChanged = skipTomorrow != userPreferences.schedule.skipTomorrow // Skip tomorrow disabled
        
        // Compare settings fields
        let nameChanged = preferredName != userPreferences.settings.preferredName
        let weatherChanged = includeWeather != userPreferences.settings.includeWeather
        let newsChanged = includeNews != userPreferences.settings.includeNews
        let sportsChanged = includeSports != userPreferences.settings.includeSports
        let selectedSportsChanged = selectedSports != userPreferences.settings.selectedSports
        let stocksChanged = includeStocks != userPreferences.settings.includeStocks
        let calendarChanged = includeCalendar != userPreferences.settings.includeCalendar
        let quotesChanged = includeQuotes != userPreferences.settings.includeQuotes
        let quotePrefChanged = quotePreference != userPreferences.settings.quotePreference
        let voiceChanged = selectedVoice != userPreferences.settings.selectedVoice
        
        // Normalize stock symbols for comparison (uppercase, trimmed, no empties)
        let currentSymbols = stockSymbolItems
            .map { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        let savedSymbols = userPreferences.settings.stockSymbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        let symbolsChanged = currentSymbols != savedSymbols
        
        return timeChanged
            || daysChanged
            // || skipTomorrowChanged // Skip tomorrow disabled
            || nameChanged
            || weatherChanged
            || newsChanged
            || sportsChanged
            || selectedSportsChanged
            || stocksChanged
            || calendarChanged
            || quotesChanged
            || quotePrefChanged
            || voiceChanged
            || symbolsChanged
    }
    
    private var shouldHighlightSave: Bool {
        return hasUnsavedChanges && !isLocked
    }
    
    init() {
        let prefs = UserPreferences.shared
        _selectedTime = State(initialValue: prefs.schedule.effectiveTime)
        _selectedDays = State(initialValue: prefs.schedule.repeatDays)
        _skipTomorrow = State(initialValue: false) // Always false - skip tomorrow feature disabled
        _preferredName = State(initialValue: prefs.settings.preferredName)
        _includeWeather = State(initialValue: prefs.settings.includeWeather)
        _includeNews = State(initialValue: prefs.settings.includeNews)
        _includeSports = State(initialValue: prefs.settings.includeSports)
        _includeStocks = State(initialValue: prefs.settings.includeStocks)
        _selectedSports = State(initialValue: prefs.settings.selectedSports)
        _includeCalendar = State(initialValue: prefs.settings.includeCalendar)
        _includeQuotes = State(initialValue: prefs.settings.includeQuotes)
        _quotePreference = State(initialValue: prefs.settings.quotePreference)
        _stockSymbolItems = State(initialValue: prefs.settings.stockSymbols.asStockSymbolItems)
        _selectedVoice = State(initialValue: prefs.settings.selectedVoice)
    }
    
    var body: some View {
        NavigationView {
            Form {
                if isLocked {
                    lockoutBanner
                }
                
                generalSettingsSection
                scheduleSection
                contentSection
                advancedSection
                footerSection
            }
            .navigationTitle("Edit & Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(
                Group {
                    if showToast {
                        toastView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showToast)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation {
                                        showToast = false
                                    }
                                }
                            }
                    }
                }
            )
            .onAppear {
                logger.log("⚙️ Edit Schedule view appeared", level: .info)
                logger.logUserAction("Settings opened", details: [
                    "isLocked": isLocked,
                    "nextOccurrence": userPreferences.schedule.nextOccurrence?.description ?? "none",
                    "selectedVoice": selectedVoice.name
                ])
            }
            .toolbar(content: {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        if hasUnsavedChanges {
                            showingDiscardAlert = true
                        } else {
                            dismissTask?.cancel()
                            dismissTask = Task {
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(BananaTheme.ColorToken.text)
                    }
                }
                if shouldHighlightSave {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: {
                            logger.logUserAction("Save EditSchedule - toolbar save button")
                            saveChanges()
                            dismissTask?.cancel()
                            dismissTask = Task {
                                // Small delay to ensure UI updates propagate
                                try? await Task.sleep(for: .milliseconds(100))
                                await MainActor.run {
                                    presentationMode.wrappedValue.dismiss()
                                }
                            }
                        }) {
                            Image(systemName: "checkmark")
                                .foregroundColor(BananaTheme.ColorToken.accent)
                        }
                        .tint(BananaTheme.ColorToken.primary)
                    }
                }
            })
        }
        .sheet(isPresented: $showVoicePicker) {
            VoicePickerView(selectedVoice: $selectedVoice)
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackSheetView(
                onCancel: {
                    showFeedbackSheet = false
                },
                onSubmit: { category, message, email, includeDiagnostics in
                    Task {
                        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                        let deviceModel = UIDevice.current.model
                        let osVersion = UIDevice.current.systemVersion
                        let payload = SupabaseClient.AppFeedbackPayload(
                            category: category,
                            message: message,
                            include_diagnostics: includeDiagnostics,
                            history_id: nil, // No active DayStart in settings
                            app_version: appVersion,
                            build: build,
                            device_model: deviceModel,
                            os_version: osVersion,
                            email: email
                        )
                        do {
                            let ok = try await SupabaseClient.shared.submitAppFeedback(payload)
                            await MainActor.run {
                                showFeedbackSheet = false
                                if ok {
                                    toastMessage = "Thanks for the feedback"
                                    logger.logUserAction("Feedback submitted from EditSchedule", details: ["category": category])
                                } else {
                                    toastMessage = "Couldn't send feedback. Please try again."
                                    logger.log("Feedback submission returned false", level: .error)
                                }
                                showToast = true
                            }
                        } catch {
                            await MainActor.run {
                                showFeedbackSheet = false
                                toastMessage = "Couldn't send feedback. Please try again."
                                showToast = true
                            }
                            logger.log("Failed to submit feedback: \(error.localizedDescription)", level: .error)
                            
                            // Enhanced error logging for debugging  
                            logger.log("Error type: \(type(of: error))", level: .error)
                        }
                    }
                }
            )
        }
        .onDisappear {
            dismissTask?.cancel()
            textInputTask?.cancel()
        }
        .alert("Location Access Required", isPresented: $showingLocationDeniedAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Weather updates require location access. You can enable this in Settings > DayStart > Location.")
        }
        .alert("Calendar Access Required", isPresented: $showingCalendarDeniedAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Calendar events require calendar access. You can enable this in Settings > DayStart > Calendars.")
        }
        .alert("Unsaved Changes", isPresented: $showingDiscardAlert) {
            Button("Save Changes", role: .none) {
                logger.logUserAction("Save EditSchedule - unsaved changes alert")
                saveChanges()
                dismissTask?.cancel()
                dismissTask = Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    await MainActor.run {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            Button("Discard Changes", role: .destructive) {
                logger.logUserAction("Discard EditSchedule changes")
                dismissTask?.cancel()
                dismissTask = Task {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            Button("Cancel", role: .cancel) {
                logger.logUserAction("Cancel discard EditSchedule changes")
            }
        } message: {
            Text("You have unsaved changes. Would you like to save them before leaving?")
        }
    }
    
    private var lockoutBanner: some View {
        Section {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text("Settings Locked")
                        .adaptiveFont(BananaTheme.Typography.headline)
                    Text("Changes disabled within 4 hours of next DayStart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var generalSettingsSection: some View {
        Section(header: Text("General Settings")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Your Name")
                    TextField("Your name", text: Binding(
                        get: { preferredName },
                        set: { newValue in
                            textInputTask?.cancel()
                            // Apply character filtering and limit
                            let filtered = UserSettings.sanitizeName(newValue)
                            preferredName = String(filtered.prefix(UserSettings.maxNameLength))
                        }
                    ))
                        .multilineTextAlignment(.trailing)
                        .disabled(isLocked)
                }
                
                // Show character count when approaching limit
                if preferredName.count > 40 {
                    HStack {
                        Spacer()
                        Text("\(preferredName.count)/\(UserSettings.maxNameLength)")
                            .font(.caption)
                            .foregroundColor(preferredName.count >= UserSettings.maxNameLength ? .orange : BananaTheme.ColorToken.secondaryText)
                    }
                }
            }
            
            Button(action: { showVoicePicker = true }) {
                HStack {
                    Text("Voice")
                    Spacer()
                    Text(selectedVoice.name)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    Image(systemName: "chevron.right")
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isLocked)
            
        }
    }
    
    private var scheduleSection: some View {
        Section(header: Text("Schedule")) {
            // Scheduled Time Row (matches ContentCard structure exactly)
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(BananaTheme.ColorToken.accent)
                    .frame(width: 20)
                
                Text("Scheduled DayStart")
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Spacer()
                
                DatePicker(
                    "",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .disabled(isLocked || selectedDays.isEmpty)
                .opacity(selectedDays.isEmpty ? 0.6 : 1.0)
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            
            // Day selection and caption (separate Form row like ContentCard expandable content)
            VStack(spacing: 12) {
                // Day chips
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(WeekDay.allCases) { day in
                        DayToggleChip(
                            day: day,
                            isSelected: Binding(
                                get: { selectedDays.contains(day) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedDays.insert(day)
                                    } else {
                                        selectedDays.remove(day)
                                    }
                                }
                            ),
                            isDisabled: isLocked,
                            hasUnsavedChanges: hasUnsavedChanges
                        )
                    }
                    Spacer()
                }
                
                // Caption
                if !selectedDays.isEmpty {
                    HStack {
                        Spacer()
                        Text("Repeats \(formatScheduleDays(selectedDays))")
                            .font(.caption.weight(.medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        Spacer()
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("Select at least one day to enable DayStart")
                            .font(.caption)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        Spacer()
                    }
                }
            }
            .listRowSeparator(.hidden)
        }
    }
    
    private var contentSection: some View {
        Section(header: Text("Content")) {
            ForEach(ContentType.allCases) { contentType in
                ContentCard(
                    type: contentType,
                    isEnabled: Binding(
                        get: { 
                            switch contentType {
                            case .weather: return includeWeather
                            case .calendar: return includeCalendar
                            case .quotes: return includeQuotes
                            case .news: return includeNews
                            case .sports: return includeSports
                            case .stocks: return includeStocks
                            }
                        },
                        set: { enabled in
                            switch contentType {
                            case .weather:
                                includeWeather = enabled
                                if enabled {
                                    Task {
                                        await requestLocationPermission()
                                    }
                                }
                            case .calendar:
                                includeCalendar = enabled
                                if enabled {
                                    Task {
                                        await requestCalendarPermission()
                                    }
                                }
                            case .quotes:
                                includeQuotes = enabled
                            case .news:
                                includeNews = enabled
                            case .sports:
                                includeSports = enabled
                            case .stocks:
                                includeStocks = enabled
                            }
                        }
                    ),
                    isDisabled: isLocked
                ) {
                    // Expandable settings for each content type
                    switch contentType {
                    case .quotes:
                        QuoteSettingsView(
                            quotePreference: $quotePreference,
                            isDisabled: isLocked
                        )
                    case .sports:
                        SportsSelector(
                            selectedSports: $selectedSports,
                            isDisabled: isLocked
                        )
                    case .stocks:
                        StockSymbolsEditor(
                            stockSymbolItems: $stockSymbolItems,
                            isDisabled: isLocked
                        )
                    default:
                        EmptyView()
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
    }
    
    
    
    private var advancedSection: some View {
        Section(header: Text("Advanced")) {
            // Account Management
            AccountManagementRow()
            
            HStack {
                Text("Theme")
                Spacer()
                Picker("", selection: $themeManager.themePreference) {
                    ForEach(ThemePreference.allCases, id: \.self) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accentColor(BananaTheme.ColorToken.secondaryText)
            }
            
            #if DEBUG
            Button(action: {
                showResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.red)
                    Text("Reset Onboarding")
                        .foregroundColor(.red)
                }
            }
            #endif
        }
        #if DEBUG
        .alert("Reset Onboarding?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetOnboarding()
            }
        } message: {
            Text("This will clear all your settings and show the onboarding flow again.")
        }
        #endif
    }
    
    // MARK: - Toast View
    
    private var toastView: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: toastMessage.contains("Thanks") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(toastMessage.contains("Thanks") ? .green : .orange)
                    .font(.system(size: 16))
                
                Text(toastMessage)
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showToast = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(BananaTheme.ColorToken.card)
                    .stroke(BananaTheme.ColorToken.primary.opacity(0.3), lineWidth: 1)
                    .shadow(color: BananaTheme.ColorToken.text.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
    
    private var footerSection: some View {
        Section {
            VStack(spacing: 12) {
                Button(action: { showFeedbackSheet = true }) {
                    Text("Submit Feedback")
                        .foregroundColor(BananaTheme.ColorToken.primary)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Legal links - use Text with onTapGesture to avoid Form row issues
                HStack(spacing: 12) {
                    Text("Terms")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.8))
                        .onTapGesture {
                            if let url = URL(string: "https://daystart.bananaintelligence.ai/terms") {
                                UIApplication.shared.open(url)
                            }
                        }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.8))
                    
                    Text("Privacy")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.8))
                        .onTapGesture {
                            if let url = URL(string: "https://daystart.bananaintelligence.ai/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.8))
                    
                    HStack(spacing: 3) {
                        Text(" Weather")
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.8))
                    .onTapGesture {
                        if let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button(action: {
                    if let url = URL(string: "https://bananaintelligence.ai/") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Powered by 🍌🧠 Banana Intelligence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                if let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                   let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    #if DEBUG
    private func resetOnboarding() {
        // Clear all user preferences
        userPreferences.hasCompletedOnboarding = false
        userPreferences.settings = UserSettings.default
        userPreferences.schedule = DayStartSchedule()
        userPreferences.history = []
        
        // Clear theme preference
        themeManager.setTheme(.system)
        
        // Dismiss this view
        dismissTask?.cancel()
        dismissTask = Task {
            presentationMode.wrappedValue.dismiss()
        }
    }
    #endif
    
    private func getEnabledFeaturesCount() -> Int {
        var count = 0
        if includeWeather { count += 1 }
        if includeNews { count += 1 }
        if includeSports { count += 1 }
        if includeStocks { count += 1 }
        if includeCalendar { count += 1 }
        if includeQuotes { count += 1 }
        return count
    }
    
    /// Format schedule days for display
    private func formatScheduleDays(_ days: Set<WeekDay>) -> String {
        if days.count == 7 {
            return "daily"
        } else if days.count == 5 && !days.contains(.saturday) && !days.contains(.sunday) {
            return "weekdays"
        } else if days.count == 2 && days.contains(.saturday) && days.contains(.sunday) {
            return "weekends"
        } else if days.count == 6 && days.contains(.saturday) && !days.contains(.sunday) {
            return "weekdays + Saturday"
        } else if days.count == 6 && !days.contains(.saturday) && days.contains(.sunday) {
            return "weekdays + Sunday"
        } else if days.isEmpty {
            return "no days selected"
        } else {
            return days.sorted(by: { $0.rawValue < $1.rawValue }).map(\.shortName).joined(separator: ", ")
        }
    }
    
    private func saveChanges() {
        let startTime = logger.startPerformanceTimer()
        logger.log("💾 Saving settings changes", level: .info)
        
        // Log what changed
        let voiceChanged = selectedVoice != userPreferences.settings.selectedVoice
        
        // More robust time comparison - check if times differ by more than 1 second
        let timeChanged: Bool = {
            let currentTime = userPreferences.schedule.effectiveTime
            let timeDifference = abs(selectedTime.timeIntervalSince(currentTime))
            let hasTimeChanged = timeDifference > 1.0 // 1 second threshold
            
            logger.log("🕐 Time comparison: selected=\(DateFormatter.shortTime.string(from: selectedTime)), current=\(DateFormatter.shortTime.string(from: currentTime)), diff=\(timeDifference)s, changed=\(hasTimeChanged)", level: .debug)
            
            return hasTimeChanged
        }()
        
        let daysChanged = selectedDays != userPreferences.schedule.repeatDays
        
        logger.logUserAction("Save EditSchedule changes", details: [
            "voiceChanged": voiceChanged,
            "timeChanged": timeChanged, 
            "daysChanged": daysChanged,
            "newVoice": selectedVoice.name,
            "newTime": DateFormatter.shortTime.string(from: selectedTime),
            "selectedDaysCount": selectedDays.count,
            "featuresEnabled": getEnabledFeaturesCount()
        ])
        
        DebugLogger.shared.logUserAction("Save EditSchedule changes")
        
        // Schedule - use timezone-independent time setting
        var newSchedule = DayStartSchedule(
            time: selectedTime, // Keep for backwards compatibility
            repeatDays: selectedDays,
            skipTomorrow: false // Always false - skip tomorrow feature disabled
        )
        newSchedule.setTime(from: selectedTime) // Store timezone-independent components
        userPreferences.schedule = newSchedule
        
        // Settings (mutate only fields we expose here)
        var settings = userPreferences.settings
        settings.preferredName = preferredName
        settings.includeWeather = includeWeather
        settings.includeNews = includeNews
        settings.includeSports = includeSports
        settings.selectedSports = selectedSports
        
        // Debug logging for sports settings
        logger.log("🏈 Sports settings: includeSports=\(includeSports), selectedSports=\(selectedSports.map(\.rawValue))", level: .debug)
        settings.includeStocks = includeStocks
        
        // Sync stockSymbolItems to stockSymbols and filter/validate
        let validSymbols = stockSymbolItems.asStringArray.filter { UserSettings.isValidStockSymbol($0) }
        
        settings.stockSymbols = validSymbols
        
        settings.includeCalendar = includeCalendar
        settings.includeQuotes = includeQuotes
        settings.quotePreference = quotePreference
        settings.selectedVoice = selectedVoice
        userPreferences.settings = settings
        userPreferences.saveSettings()
        
        DebugLogger.shared.log("✅ Settings saved successfully", level: .info)
        logger.endPerformanceTimer(startTime, operation: "Settings save")
    }
    
    // MARK: - Permission Handling
    
    private func requestLocationPermission() async {
        let locationManager = LocationManager.shared
        
        // Check if already denied - if so, just show alert
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            await MainActor.run {
                includeWeather = false
                showingLocationDeniedAlert = true
            }
            return
        }
        
        let granted = await locationManager.requestLocationPermission()
        
        if !granted {
            // If permission denied, disable weather feature and show alert
            await MainActor.run {
                includeWeather = false
                showingLocationDeniedAlert = true
            }
        }
    }
    
    private func requestCalendarPermission() async {
        let calendarManager = CalendarManager.shared
        let granted = await calendarManager.requestCalendarAccess()
        
        if !granted {
            // If permission denied, disable calendar feature and show alert
            await MainActor.run {
                includeCalendar = false
                showingCalendarDeniedAlert = true
            }
        }
    }
}

struct DayToggleChip: View {
    let day: WeekDay
    @Binding var isSelected: Bool
    let isDisabled: Bool
    let hasUnsavedChanges: Bool
    
    var body: some View {
        Button(action: { isSelected.toggle() }) {
            Text(day.name)
                .font(.caption)
                .fontWeight(.regular)
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                        .overlay(
                            hasUnsavedChanges ? Circle()
                                .stroke(BananaTheme.ColorToken.accent, lineWidth: 2)
                            : nil
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct VoiceSelectionButton: View {
    let voice: VoiceOption
    let isSelected: Bool
    let isDisabled: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            Button(action: onSelect) {
                VStack(spacing: 4) {
                    Image(systemName: "person.wave.2")
                        .font(.title2)
                    Text(voice.name)
                        .font(.caption)
                        .fontWeight(isSelected ? .bold : .regular)
                }
                .foregroundColor(isSelected ? BananaTheme.ColorToken.background : BananaTheme.ColorToken.text)
                .frame(width: 60, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDisabled)
            
            Button(action: {
                AudioPlayerManager.shared.previewVoice(voice)
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.accent)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDisabled)
        }
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct StockSymbolsEditor: View {
    @Binding var stockSymbolItems: [StockSymbolItem]
    let isDisabled: Bool
    
    // 🔥 AWESOME VALIDATION SYSTEM - PRESERVED! 🔥
    @StateObject private var validationService = StockValidationService.shared
    @State private var validationResultsById: [UUID: StockValidationResult] = [:]
    @State private var isValidatingById: [UUID: Bool] = [:]
    
    private let logger = DebugLogger.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stock Symbols (\(stockSymbolItems.count) of 5)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                // 🎯 FIXED: Use stable item IDs, not array indices!
                ForEach(stockSymbolItems) { item in
                    StockSymbolRow(
                        symbol: createBinding(for: item),
                        isDisabled: isDisabled,
                        validationResult: validationResultsById[item.id],
                        isValidating: isValidatingById[item.id] ?? false,
                        onDelete: { removeSymbol(item) },
                        onValidationNeeded: { symbol in
                            validateSymbol(symbol, for: item.id) // 🔍 Validation preserved!
                        }
                    )
                    .id(item.id) // 🎯 STABLE IDENTITY - No more UI confusion!
                }
            }
            
            if stockSymbolItems.count < 5 {
                Button(action: addSymbol) {
                    Label("Add Symbol", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                .buttonStyle(BorderlessButtonStyle()) // Prevent Form from intercepting taps
                .disabled(isDisabled)
                .padding(.top, 16) // Add extra spacing to prevent overlap
            }
        }
    }
    
    // 🎯 FIXED: Create binding for specific item, not index
    private func createBinding(for item: StockSymbolItem) -> Binding<String> {
        return Binding(
            get: {
                return item.symbol
            },
            set: { newValue in
                // 🎯 FIXED: Find item by ID, not index
                if let index = stockSymbolItems.firstIndex(where: { $0.id == item.id }) {
                    let formatted = String(newValue.uppercased().prefix(16))
                    
                    stockSymbolItems[index].symbol = formatted
                    
                    // 🔍 Trigger awesome validation!
                    if !formatted.isEmpty {
                        validateSymbol(formatted, for: item.id)
                    }
                }
            }
        )
    }
    
    // 🎯 FIXED: Clean addition - no more UI confusion
    private func addSymbol() {
        guard stockSymbolItems.count < 5 else { return }
        // Avoid multiple empty rows which cause confusing shared state
        guard !stockSymbolItems.contains(where: { $0.symbol.isEmpty }) else { return }
        logger.logUserAction("Add stock symbol slot", details: ["currentCount": stockSymbolItems.count])
        let newItem = StockSymbolItem(symbol: "")
        stockSymbolItems.append(newItem)
    }
    
    // 🎯 FIXED: Clean removal - only removes specific item
    private func removeSymbol(_ item: StockSymbolItem) {
        logger.logUserAction("Remove stock symbol", details: ["symbol": item.symbol, "id": item.id.uuidString])
        
        // Clean up validation state for this specific item id
        validationResultsById.removeValue(forKey: item.id)
        isValidatingById.removeValue(forKey: item.id)
        
        // Remove by ID, not index - bulletproof!
        stockSymbolItems.removeAll { $0.id == item.id }
    }
    
    // 🔥 AWESOME VALIDATION SYSTEM - COMPLETELY PRESERVED! 🔥
    private func validateSymbol(_ symbol: String, for id: UUID) {
        guard !symbol.isEmpty else {
            validationResultsById.removeValue(forKey: id)
            isValidatingById.removeValue(forKey: id)
            return
        }
        
        isValidatingById[id] = true
        
        validationService.validateSymbolAsync(symbol) { result in
            if let current = stockSymbolItems.first(where: { $0.id == id }), !current.symbol.isEmpty {
                validationResultsById[id] = result
            }
            isValidatingById[id] = false
            
            if !result.isValid {
                logger.log("❌ Invalid stock symbol: \(symbol) - \(result.error?.localizedDescription ?? "Unknown error")", level: .warning)
            } else {
            }
        }
    }
}

struct SportsSelector: View {
    @Binding var selectedSports: [SportType]
    let isDisabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sports (\(selectedSports.count) selected)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(SportType.allCases, id: \.self) { sport in
                    SportSelectionButton(
                        sport: sport,
                        isSelected: selectedSports.contains(sport),
                        isDisabled: isDisabled
                    ) {
                        toggleSport(sport)
                    }
                }
            }
            
            if selectedSports.count > 0 {
                Text(selectedSports.map(\.displayName).joined(separator: ", ") + " selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
    
    private func toggleSport(_ sport: SportType) {
        if selectedSports.contains(sport) {
            selectedSports.removeAll { $0 == sport }
        } else {
            selectedSports.append(sport)
        }
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let totalHeight = rows.reduce(0) { result, row in
            result + row.maxHeight + (result > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        
        for row in rows {
            let totalWidth = row.subviews.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(row.subviews.count - 1)
            let leadingX = bounds.midX - totalWidth / 2 // Center the row
            var x = leadingX
            
            for subview in row.subviews {
                subview.view.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(subview.size)
                )
                x += subview.size.width + spacing
            }
            
            y += row.maxHeight + spacing
        }
    }
    
    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            
            if currentRow.subviews.isEmpty || 
               currentRow.totalWidth + spacing + size.width <= (proposal.width ?? CGFloat.greatestFiniteMagnitude) {
                currentRow.add(SubviewInfo(view: subview, size: size))
            } else {
                rows.append(currentRow)
                currentRow = Row()
                currentRow.add(SubviewInfo(view: subview, size: size))
            }
        }
        
        if !currentRow.subviews.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    private struct SubviewInfo {
        let view: LayoutSubview
        let size: CGSize
    }
    
    private struct Row {
        var subviews: [SubviewInfo] = []
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        mutating func add(_ subview: SubviewInfo) {
            totalWidth += subview.size.width
            if !subviews.isEmpty {
                totalWidth += 8 // spacing
            }
            maxHeight = max(maxHeight, subview.size.height)
            subviews.append(subview)
        }
    }
}

struct SportSelectionButton: View {
    let sport: SportType
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(sport.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.card)
                        .stroke(BananaTheme.ColorToken.primary.opacity(0.3), lineWidth: 1)
                )
        }
        .disabled(isDisabled)
        .buttonStyle(BorderlessButtonStyle())
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct StockSymbolRow: View {
    @Binding var symbol: String
    let isDisabled: Bool
    let validationResult: StockValidationResult?
    let isValidating: Bool
    let onDelete: () -> Void
    let onValidationNeeded: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("AAPL", text: $symbol)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .disabled(isDisabled)
                        .overlay(
                            // Validation indicator
                            HStack {
                                Spacer()
                                if isValidating {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .padding(.trailing, 8)
                                } else if let result = validationResult {
                                    Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.isValid ? .green : .red)
                                        .padding(.trailing, 8)
                                }
                            }
                        )
                        .onChange(of: symbol) { newValue in
                            if !newValue.isEmpty {
                                // Debounce validation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    if symbol == newValue { // Only validate if value hasn't changed
                                        onValidationNeeded(newValue)
                                    }
                                }
                            }
                        }
                    
                    if let result = validationResult, let companyName = result.companyName {
                        Text(companyName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                .buttonStyle(BorderlessButtonStyle()) // Prevent Form from intercepting taps
                .disabled(isDisabled)
                .contentShape(Rectangle()) // Constrain touch area to button bounds
                .padding(.leading, 8) // Add some spacing from the text field
            }
            
            // Error message
            if let result = validationResult, !result.isValid, let error = result.error {
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Account Management Component

struct AccountManagementRow: View {
    @StateObject private var purchaseManager = PurchaseManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Purchase Status")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Text(purchaseStatusText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            
            Spacer()
            
            Button(action: {
                Task {
                    if !purchaseManager.isPurchased {
                        // Guide user back to paywall
                        // In practice, this might restart onboarding or show paywall directly
                    } else {
                        // Restore purchases option
                        try? await purchaseManager.restorePurchases()
                    }
                }
            }) {
                Text(buttonText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            .disabled(purchaseManager.isLoading)
        }
    }
    
    private var purchaseStatusText: String {
        switch purchaseManager.purchaseState {
        case .purchased(let receiptId):
            return "Premium • ID: \(receiptId.prefix(8))..."
        case .notPurchased:
            return "Free version"
        case .unknown:
            return "Checking status..."
        }
    }
    
    private var buttonText: String {
        if purchaseManager.isLoading {
            return "..."
        }
        
        switch purchaseManager.purchaseState {
        case .purchased:
            return "Restore Purchases"
        case .notPurchased:
            return "Upgrade to Premium"
        case .unknown:
            return "..."
        }
    }
}

// MARK: - Content Card Component

struct ContentCard<ExpandableContent: View>: View {
    let type: ContentType
    @Binding var isEnabled: Bool
    let isDisabled: Bool
    @State private var isExpanded: Bool = false
    @ViewBuilder let expandableContent: () -> ExpandableContent
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(BananaTheme.ColorToken.accent)
                    .frame(width: 20)
                
                Text(type.displayName)
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Spacer()
                
                if type.hasExpandableSettings && isEnabled {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(isDisabled)
                }
                
                Toggle("", isOn: $isEnabled)
                    .tint(BananaTheme.ColorToken.primary)
                    .disabled(isDisabled)
            }
            .padding(.vertical, 8)
            
            // Expandable settings
            if type.hasExpandableSettings && isEnabled && isExpanded {
                VStack {
                    Divider()
                        .background(BananaTheme.ColorToken.primary.opacity(0.2))
                    
                    expandableContent()
                        .padding(.top, 8)
                }
                .transition(.opacity.combined(with: .slide))
            }
        }
    }
}

struct QuoteSettingsView: View {
    @Binding var quotePreference: QuotePreference
    let isDisabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Quote Style", selection: $quotePreference) {
                ForEach(QuotePreference.allCases, id: \.rawValue) { preference in
                    Text(preference.name).tag(preference)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .accentColor(BananaTheme.ColorToken.secondaryText)
            .disabled(isDisabled)
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
