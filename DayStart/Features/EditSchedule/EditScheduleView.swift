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
    @State private var selectedVoice: VoiceOption
    @State private var dayStartLength: Int
    
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
        _selectedVoice = State(initialValue: prefs.settings.selectedVoice)
        _dayStartLength = State(initialValue: prefs.settings.dayStartLength)
    }
    
    var body: some View {
        NavigationView {
            Form {
                if isLocked {
                    lockoutBanner
                }
                
                settingsSection
                scheduleSection
                contentSection
                voiceSection
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
                        .font(.headline)
                    Text("Changes disabled within 4 hours of next DayStart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var settingsSection: some View {
        Section(header: Text("Personal")) {
            HStack {
                Text("Name")
                TextField("Your name", text: $preferredName)
                    .multilineTextAlignment(.trailing)
                    .disabled(isLocked)
            }
            
            HStack {
                Text("DayStart Length")
                Stepper("\(dayStartLength) minutes", value: $dayStartLength, in: 2...10)
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
                
                HStack(spacing: 8) {
                    ForEach(WeekDay.allCases) { day in
                        let isSelectedBinding = Binding<Bool>(
                            get: { selectedDays.contains(day) },
                            set: { newValue in
                                if newValue { selectedDays.insert(day) } else { selectedDays.remove(day) }
                            }
                        )
                        DayToggleChip(day: day, isSelected: isSelectedBinding, isDisabled: isLocked)
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
            Toggle("Calendar", isOn: $includeCalendar)
                .disabled(isLocked)
            Toggle("Motivational Quotes", isOn: $includeQuotes)
                .disabled(isLocked)
        }
    }
    
    private var voiceSection: some View {
        Section(header: Text("Voice")) {
            Picker("Voice", selection: $selectedVoice) {
                ForEach(VoiceOption.allCases, id: \.self) { voice in
                    Text(voice.name).tag(voice)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .disabled(isLocked)
        }
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
        settings.includeCalendar = includeCalendar
        settings.includeQuotes = includeQuotes
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
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}
