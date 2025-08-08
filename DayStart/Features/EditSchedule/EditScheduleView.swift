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
    @State private var selectedVoice: VoiceOption
    @State private var dayStartLength: Int
    @State private var showResetConfirmation = false
    @StateObject private var themeManager = ThemeManager.shared
    
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
            
            Picker("Voice", selection: $selectedVoice) {
                ForEach(VoiceOption.allCases, id: \.self) { voice in
                    Text(voice.name).tag(voice)
                }
            }
            .pickerStyle(MenuPickerStyle())
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
                .disabled(isLocked)
            Toggle("News", isOn: $includeNews)
                .disabled(isLocked)
            Toggle("Sports", isOn: $includeSports)
                .disabled(isLocked)
            Toggle("Stocks", isOn: $includeStocks)
                .disabled(isLocked)
            
            if includeStocks {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stock Symbols (up to 5)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(0..<stockSymbols.count, id: \.self) { index in
                        HStack {
                            TextField("Symbol", text: $stockSymbols[index])
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.allCharacters)
                                .onChange(of: stockSymbols[index]) { _ in
                                    stockSymbols[index] = stockSymbols[index].uppercased()
                                    if stockSymbols[index].count > 5 {
                                        stockSymbols[index] = String(stockSymbols[index].prefix(5))
                                    }
                                }
                                .disabled(isLocked)
                            
                            Button(action: {
                                stockSymbols.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .disabled(isLocked)
                        }
                    }
                    
                    if stockSymbols.count < 5 {
                        Button(action: {
                            stockSymbols.append("")
                        }) {
                            Label("Add Symbol", systemImage: "plus.circle.fill")
                                .font(.caption)
                        }
                        .disabled(isLocked)
                    }
                }
                .padding(.leading)
            }
            
            Toggle("Calendar", isOn: $includeCalendar)
                .disabled(isLocked)
            Toggle("Motivational Quotes", isOn: $includeQuotes)
                .disabled(isLocked)
            
            if includeQuotes {
                Picker("Quote Style", selection: $quotePreference) {
                    ForEach(QuotePreference.allCases, id: \.rawValue) { preference in
                        Text(preference.name).tag(preference)
                    }
                }
                .pickerStyle(MenuPickerStyle())
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
        settings.stockSymbols = stockSymbols.filter { !$0.isEmpty && UserSettings.isValidStockSymbol($0) }
        settings.includeCalendar = includeCalendar
        settings.includeQuotes = includeQuotes
        settings.quotePreference = quotePreference
        settings.selectedVoice = selectedVoice
        settings.dayStartLength = dayStartLength
        userPreferences.settings = settings
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
