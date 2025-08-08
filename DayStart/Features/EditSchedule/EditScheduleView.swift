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
    @State private var stockSymbols: [String]
    @State private var stockSymbolItems: [StockSymbolItem] = []
    @State private var selectedVoice: VoiceOption
    @State private var dayStartLength: Int
    @State private var showResetConfirmation = false
    @StateObject private var themeManager = ThemeManager.shared
    
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
        _stockSymbols = State(initialValue: prefs.settings.stockSymbols)
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
                appearanceSection
                advancedSection
            }
            .navigationTitle("Edit & Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        logger.logUserAction("Save EditSchedule - toolbar save button")
                        saveChanges()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "checkmark")
                    }
                    .disabled(isLocked)
                }
            }
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
                Text("Name")
                TextField("Your name", text: $preferredName)
                    .multilineTextAlignment(.trailing)
                    .disabled(isLocked)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Voice")
                    Spacer()
                    Text(selectedVoice.name)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                
                HStack(spacing: 12) {
                    ForEach(VoiceOption.allCases, id: \.self) { voice in
                        VoiceSelectionButton(
                            voice: voice,
                            isSelected: selectedVoice == voice,
                            isDisabled: isLocked
                        ) {
                            selectedVoice = voice
                        }
                    }
                }
            }
            
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
            DatePicker(
                "Wake Time",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .disabled(isLocked)
            
            VStack(alignment: .leading) {
                Text("Repeat")
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
                            isDisabled: isLocked
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            
            Toggle("Skip Tomorrow", isOn: $skipTomorrow)
                .tint(BananaTheme.ColorToken.primary)
                .disabled(isLocked)
            
            if let nextTime = previewNextOccurrence {
                HStack {
                    Text("Next DayStart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(nextTime, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    
    
    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            HStack {
                Text("Theme")
                Spacer()
                Picker("Theme", selection: $themeManager.themePreference) {
                    ForEach(ThemePreference.allCases, id: \.self) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .accentColor(BananaTheme.ColorToken.primary)
            }
        }
    }
    
    private var advancedSection: some View {
        Section(header: Text("Advanced")) {
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
        presentationMode.wrappedValue.dismiss()
    }
    
    private func saveChanges() {
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
        DebugLogger.shared.log("📊 Stock symbols saved: \(validSymbols.count) symbols [\(validSymbols.joined(separator: ", "))]", level: .debug)
        
        settings.includeCalendar = includeCalendar
        settings.includeQuotes = includeQuotes
        settings.quotePreference = quotePreference
        settings.selectedVoice = selectedVoice
        settings.dayStartLength = dayStartLength
        userPreferences.settings = settings
        
        DebugLogger.shared.log("✅ Settings saved successfully", level: .info)
    }
}

struct DayToggleChip: View {
    let day: WeekDay
    @Binding var isSelected: Bool
    let isDisabled: Bool
    
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
    @State private var validationResults: [String: StockValidationResult] = [:]
    @State private var isValidating: [String: Bool] = [:]
    
    private let logger = DebugLogger.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stock Symbols (up to 5)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                // 🎯 FIXED: Use stable item IDs, not array indices!
                ForEach(stockSymbolItems) { item in
                    StockSymbolRow(
                        symbol: createBinding(for: item),
                        isDisabled: isDisabled,
                        validationResult: validationResults[item.symbol],
                        isValidating: isValidating[item.symbol] ?? false,
                        onDelete: { removeSymbol(item) },
                        onValidationNeeded: { symbol in
                            validateSymbol(symbol) // 🔍 Validation magic preserved!
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
                .disabled(isDisabled)
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
                    let formatted = String(newValue.uppercased().prefix(5))
                    
                    // Clean up old validation state if symbol changed
                    let oldSymbol = stockSymbolItems[index].symbol
                    if oldSymbol != formatted && !oldSymbol.isEmpty {
                        validationResults.removeValue(forKey: oldSymbol)
                        isValidating.removeValue(forKey: oldSymbol)
                    }
                    
                    stockSymbolItems[index].symbol = formatted
                    
                    // 🔍 Trigger awesome validation!
                    if !formatted.isEmpty {
                        validateSymbol(formatted)
                    }
                }
            }
        )
    }
    
    // 🎯 FIXED: Clean addition - no more UI confusion
    private func addSymbol() {
        guard stockSymbolItems.count < 5 else { return }
        logger.logUserAction("Add stock symbol slot", details: ["currentCount": stockSymbolItems.count])
        let newItem = StockSymbolItem(symbol: "")
        stockSymbolItems.append(newItem)
    }
    
    // 🎯 FIXED: Clean removal - only removes specific item
    private func removeSymbol(_ item: StockSymbolItem) {
        logger.logUserAction("Remove stock symbol", details: ["symbol": item.symbol, "id": item.id.uuidString])
        
        // Clean up validation state for this specific symbol
        validationResults.removeValue(forKey: item.symbol)
        isValidating.removeValue(forKey: item.symbol)
        
        // Remove by ID, not index - bulletproof!
        stockSymbolItems.removeAll { $0.id == item.id }
    }
    
    // 🔥 AWESOME VALIDATION SYSTEM - COMPLETELY PRESERVED! 🔥
    private func validateSymbol(_ symbol: String) {
        guard !symbol.isEmpty else {
            validationResults.removeValue(forKey: symbol)
            isValidating.removeValue(forKey: symbol)
            return
        }
        
        isValidating[symbol] = true
        
        validationService.validateSymbolAsync(symbol) { result in
            validationResults[symbol] = result
            isValidating[symbol] = false
            
            if !result.isValid {
                logger.log("❌ Invalid stock symbol: \(symbol) - \(result.error?.localizedDescription ?? "Unknown error")", level: .warning)
            } else {
                logger.log("✅ Valid stock symbol: \(symbol)", level: .debug)
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
                .disabled(isDisabled)
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
