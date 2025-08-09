import Foundation

struct DayStartData: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var scheduledTime: Date? // Tracks which occurrence this DayStart was for
    var weather: String
    var news: [String]
    var sports: [String]
    var stocks: [String]
    var quote: String
    var customPrompt: String
    var transcript: String
    var duration: TimeInterval
    var audioFilePath: String?
    var isDeleted: Bool = false
    
    static var placeholder: DayStartData {
        DayStartData(
            date: Date(),
            scheduledTime: nil,
            weather: "Loading...",
            news: [],
            sports: [],
            stocks: [],
            quote: "",
            customPrompt: "",
            transcript: "",
            duration: 0,
            audioFilePath: nil,
            isDeleted: false
        )
    }
}

struct DayStartSchedule: Codable {
    var time: Date
    var repeatDays: Set<WeekDay>
    var skipTomorrow: Bool // Note: UI shows inverted as "Next DayStart" toggle
    
    init(time: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date(),
         repeatDays: Set<WeekDay> = Set(WeekDay.allCases),
         skipTomorrow: Bool = false) { // Note: skipTomorrow=false means "Next DayStart" toggle shows as ON
        self.time = time
        self.repeatDays = repeatDays
        self.skipTomorrow = skipTomorrow
    }
    
    var nextOccurrence: Date? {
        // No DayStart if no days are selected
        guard !repeatDays.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        let todayComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        for dayOffset in 0..<8 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            // Skip tomorrow's occurrence if skipTomorrow is true
            if skipTomorrow {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                if calendar.isDate(candidateDate, inSameDayAs: tomorrow) {
                    continue
                }
            }
            
            let weekday = calendar.component(.weekday, from: candidateDate)
            if let weekDay = WeekDay(weekday: weekday), repeatDays.contains(weekDay) {
                var components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                components.hour = todayComponents.hour
                components.minute = todayComponents.minute
                
                if let scheduledTime = calendar.date(from: components), scheduledTime > now {
                    return scheduledTime
                }
            }
        }
        
        return nil
    }
}

enum WeekDay: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    init?(weekday: Int) {
        self.init(rawValue: weekday)
    }
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
}

enum VoiceOption: Int, CaseIterable, Codable {
    case voice1 = 0
    case voice2 = 1
    case voice3 = 2
    
    var name: String {
        switch self {
        case .voice1: return "Grace"
        case .voice2: return "Rachel"
        case .voice3: return "Matthew"
        }
    }
}

enum QuotePreference: String, CaseIterable, Codable {
    case buddhist = "Buddhist"
    case christian = "Christian"
    case goodFeelings = "Good Feelings"
    case hindu = "Hindu"
    case inspirational = "Inspirational"
    case jewish = "Jewish"
    case mindfulness = "Mindfulness"
    case muslim = "Muslim"
    case philosophical = "Philosophical"
    case stoic = "Stoic"
    case success = "Success"
    case zen = "Zen"
    
    var name: String {
        return self.rawValue
    }
}

enum ThemePreference: String, CaseIterable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var displayName: String {
        return rawValue
    }
}

struct UserSettings: Codable {
    var preferredName: String
    var includeWeather: Bool
    var includeNews: Bool
    var includeSports: Bool
    var includeStocks: Bool
    var stockSymbols: [String]
    var includeCalendar: Bool
    var includeQuotes: Bool
    var quotePreference: QuotePreference
    var selectedVoice: VoiceOption
    var dayStartLength: Int
    var themePreference: ThemePreference
    
    static func isValidStockSymbol(_ symbol: String) -> Bool {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        return trimmed.count >= 1 && 
               trimmed.count <= 5 && 
               trimmed.allSatisfy { $0.isLetter && $0.isASCII }
    }
}

struct StockSymbol: Identifiable, Codable, Hashable {
    var id = UUID()
    let symbol: String
    
    init(_ symbol: String) {
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
    }
}

extension UserSettings {
    static var `default`: UserSettings {
        UserSettings(
            preferredName: "",
            includeWeather: true,
            includeNews: true,
            includeSports: true,
            includeStocks: true,
            stockSymbols: ["AAPL", "TSLA", "SPY"],
            includeCalendar: false,
            includeQuotes: true,
            quotePreference: .inspirational,
            selectedVoice: .voice1,
            dayStartLength: 5,
            themePreference: .system
        )
    }
}