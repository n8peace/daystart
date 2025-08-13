import SwiftUI

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
    @State private var selectedVoice: VoiceOption
    @State private var dayStartLength: Int
    @State private var showResetConfirmation = false
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showVoicePicker = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var textInputTask: Task<Void, Never>?
    
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
        // Compare schedule fields
        let timeChanged = selectedTime != userPreferences.schedule.time
        let daysChanged = selectedDays != userPreferences.schedule.repeatDays
        let skipTomorrowChanged = skipTomorrow != userPreferences.schedule.skipTomorrow
        
        // Compare settings fields
        let nameChanged = preferredName != userPreferences.settings.preferredName
        let weatherChanged = includeWeather != userPreferences.settings.includeWeather
        let newsChanged = includeNews != userPreferences.settings.includeNews
        let sportsChanged = includeSports != userPreferences.settings.includeSports
        let stocksChanged = includeStocks != userPreferences.settings.includeStocks
        let calendarChanged = includeCalendar != userPreferences.settings.includeCalendar
        let quotesChanged = includeQuotes != userPreferences.settings.includeQuotes
        let quotePrefChanged = quotePreference != userPreferences.settings.quotePreference
        let voiceChanged = selectedVoice != userPreferences.settings.selectedVoice
        let lengthChanged = dayStartLength != userPreferences.settings.dayStartLength
        
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
            || skipTomorrowChanged
            || nameChanged
            || weatherChanged
            || newsChanged
            || sportsChanged
            || stocksChanged
            || calendarChanged
            || quotesChanged
            || quotePrefChanged
            || voiceChanged
            || lengthChanged
            || symbolsChanged
    }
    
    private var shouldHighlightSave: Bool {
        return hasUnsavedChanges && !isLocked
    }
    
    init() {
        let prefs = UserPreferences.shared
        _selectedTime = State(initialValue: prefs.schedule.time)
        _selectedDays = State(initialValue: prefs.schedule.repeatDays)
        _skipTomorrow = State(initialValue: prefs.schedule.skipTomorrow)
        _preferredName = State(initialValue: prefs.settings.preferredName)
        _includeWeather = State(initialValue: prefs.settings.includeWeather)
        _includeNews = State(initialValue: prefs.settings.includeNews)
        _includeSports = State(initialValue: prefs.settings.includeSports)
        _includeStocks = State(initialValue: prefs.settings.includeStocks)
        _includeCalendar = State(initialValue: prefs.settings.includeCalendar)
        _includeQuotes = State(initialValue: prefs.settings.includeQuotes)
        _quotePreference = State(initialValue: prefs.settings.quotePreference)
        _stockSymbolItems = State(initialValue: prefs.settings.stockSymbols.asStockSymbolItems)
        _selectedVoice = State(initialValue: prefs.settings.selectedVoice)
        _dayStartLength = State(initialValue: prefs.settings.dayStartLength)
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
            }
            .navigationTitle("Edit & Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                logger.log("⚙️ Edit Schedule view appeared", level: .info)
                logger.logUserAction("Settings opened", details: [
                    "isLocked": isLocked,
                    "nextOccurrence": userPreferences.schedule.nextOccurrence?.description ?? "none",
                    "selectedVoice": selectedVoice.name
                ])
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismissTask?.cancel()
                        dismissTask = Task {
                            presentationMode.wrappedValue.dismiss()
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
            }
        }
        .sheet(isPresented: $showVoicePicker) {
            VoicePickerView(selectedVoice: $selectedVoice)
        }
        .onDisappear {
            dismissTask?.cancel()
            textInputTask?.cancel()
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
            HStack {
                Text("Your Name")
                TextField("Your name", text: Binding(
                    get: { preferredName },
                    set: { newValue in
                        textInputTask?.cancel()
                        let sanitized = String(newValue.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
                        preferredName = sanitized
                    }
                ))
                    .multilineTextAlignment(.trailing)
                    .disabled(isLocked)
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
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DayStart Length")
                    Spacer()
                    Text("\(dayStartLength) minutes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(dayStartLength) },
                        set: { dayStartLength = Int($0) }
                    ),
                    in: 2...10,
                    step: 1
                )
                .accentColor(BananaTheme.ColorToken.accent)
                .disabled(isLocked)
            }
        }
    }
    
    private var scheduleSection: some View {
        Section(header: Text("Schedule")) {
            VStack(alignment: .leading) {
                Text("Repeat Days")
                    .font(.subheadline)
                    .adaptiveFontWeight(light: .medium, dark: .semibold)
                
                HStack(spacing: 8) {
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
                }
                .padding(.vertical, 4)
                
                if selectedDays.isEmpty {
                    Text("Select at least one day to enable DayStart")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.primary)
                        .padding(.top, 4)
                }
            }
            
            DatePicker(
                "Scheduled DayStart",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .disabled(isLocked || selectedDays.isEmpty)
            .opacity(selectedDays.isEmpty ? 0.6 : 1.0)
            
            Toggle("Tomorrow's DayStart", isOn: Binding(
                get: { !skipTomorrow },
                set: { skipTomorrow = !$0 }
            ))
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked || selectedDays.isEmpty || !isTomorrowInSchedule)
                .opacity(selectedDays.isEmpty || !isTomorrowInSchedule ? 0.6 : 1.0)
            
            if !selectedDays.isEmpty, let nextTime = previewNextOccurrence {
                HStack {
                    Text(previewDescription(for: nextTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(nextTime, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if selectedDays.isEmpty {
                HStack {
                    Text("DayStart Disabled")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.primary)
                    Spacer()
                    Text("No days selected")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.primary)
                }
            }
        }
    }
    
    private var contentSection: some View {
        Section(header: Text("Content")) {
            Toggle("Weather", isOn: $includeWeather)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            Toggle("News", isOn: $includeNews)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            Toggle("Sports", isOn: $includeSports)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            Toggle("Stocks", isOn: $includeStocks)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            
            if includeStocks {
                StockSymbolsEditor(
                    stockSymbolItems: $stockSymbolItems,
                    isDisabled: isLocked
                )
                .padding(.leading)
            }
            
            Toggle("Calendar", isOn: $includeCalendar)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            Toggle("Motivational Quotes", isOn: $includeQuotes)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            
            if includeQuotes {
                Picker("Quote Style", selection: $quotePreference) {
                    ForEach(QuotePreference.allCases, id: \.rawValue) { preference in
                        Text(preference.name).tag(preference)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accentColor(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
                .padding(.leading)
            }
        }
    }
    
    
    
    private var advancedSection: some View {
        Section(header: Text("Advanced")) {
            HStack {
                Text("Theme")
                Spacer()
                Picker("", selection: $themeManager.themePreference) {
                    ForEach(ThemePreference.allCases, id: \.self) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accentColor(BananaTheme.ColorToken.primary)
            }
            
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
        }
        .alert("Reset Onboarding?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetOnboarding()
            }
        } message: {
            Text("This will clear all your settings and show the onboarding flow again.")
        }
    }
    
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
    
    private func saveChanges() {
        let startTime = logger.startPerformanceTimer()
        logger.log("💾 Saving settings changes", level: .info)
        
        // Log what changed
        let voiceChanged = selectedVoice != userPreferences.settings.selectedVoice
        let timeChanged = selectedTime != userPreferences.schedule.time 
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
        
        // Schedule
        userPreferences.schedule = DayStartSchedule(
            time: selectedTime,
            repeatDays: selectedDays,
            skipTomorrow: skipTomorrow
        )
        
        // Settings (mutate only fields we expose here)
        var settings = userPreferences.settings
        settings.preferredName = preferredName
        settings.includeWeather = includeWeather
        settings.includeNews = includeNews
        settings.includeSports = includeSports
        settings.includeStocks = includeStocks
        
        // Sync stockSymbolItems to stockSymbols and filter/validate
        let validSymbols = stockSymbolItems.asStringArray.filter { UserSettings.isValidStockSymbol($0) }
        
        settings.stockSymbols = validSymbols
        
        settings.includeCalendar = includeCalendar
        settings.includeQuotes = includeQuotes
        settings.quotePreference = quotePreference
        settings.selectedVoice = selectedVoice
        settings.dayStartLength = dayStartLength
        userPreferences.settings = settings
        userPreferences.saveSettings()
        
        DebugLogger.shared.log("✅ Settings saved successfully", level: .info)
        logger.endPerformanceTimer(startTime, operation: "Settings save")
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
                .adaptiveFontWeight(
                    light: isSelected ? .bold : .regular,
                    dark: isSelected ? .heavy : .medium
                )
                .foregroundColor(isSelected ? BananaTheme.ColorToken.background : BananaTheme.ColorToken.text)
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
                        .foregroundColor(BananaTheme.ColorToken.primary)
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


// MARK: - Extensions  
private extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
