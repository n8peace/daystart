import Foundation

struct DayStartData: Identifiable, Codable {
    var id = UUID()
    var jobId: String? // Backend job ID for share functionality
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
    var audioFilePath: String? // Local cache path for offline playback
    var audioStoragePath: String? // Backend storage path (e.g. "2025/10/21/job_abc.m4a") for sharing
    var isDeleted: Bool = false
    
    // Custom memberwise initializer to maintain backwards compatibility
    init(jobId: String? = nil, date: Date, scheduledTime: Date? = nil, weather: String, news: [String], sports: [String], stocks: [String], quote: String, customPrompt: String, transcript: String, duration: TimeInterval, audioFilePath: String? = nil, audioStoragePath: String? = nil, isDeleted: Bool = false) {
        self.id = UUID()
        self.jobId = jobId
        self.date = date
        self.scheduledTime = scheduledTime
        self.weather = weather
        self.news = news
        self.sports = sports
        self.stocks = stocks
        self.quote = quote
        self.customPrompt = customPrompt
        self.transcript = transcript
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.audioStoragePath = audioStoragePath
        self.isDeleted = isDeleted
    }
    
    static var placeholder: DayStartData {
        DayStartData(
            jobId: nil,
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
            audioStoragePath: nil,
            isDeleted: false
        )
    }
}

struct DayStartSchedule: Codable, Equatable {
    var time: Date // Legacy storage - kept for backwards compatibility
    var timeComponents: DateComponents? // New timezone-independent storage
    var repeatDays: Set<WeekDay>
    var skipTomorrow: Bool // Note: UI shows inverted as "Next DayStart" toggle
    
    init(time: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date(),
         repeatDays: Set<WeekDay> = Set(WeekDay.allCases),
         skipTomorrow: Bool = false) { // Note: skipTomorrow=false means "Next DayStart" toggle shows as ON
        self.time = time
        self.repeatDays = repeatDays
        self.skipTomorrow = skipTomorrow
        
        // Auto-migrate: Extract timezone-independent components from legacy Date
        // CRITICAL: Use the device's current timezone to extract the intended local time
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        self.timeComponents = DateComponents(hour: components.hour ?? 7, minute: components.minute ?? 0)
        
    }
    
    // MARK: - Timezone-Independent Time Access
    
    /// Returns the effective scheduled time for display and DatePicker usage
    /// This creates a Date in the current timezone with the stored hour/minute components
    var effectiveTime: Date {
        if let components = timeComponents {
            // Create a time in the current timezone using our stored components
            // This ensures DatePickers and display show the correct local time
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            if let displayTime = calendar.date(bySettingHour: components.hour ?? 7, 
                                               minute: components.minute ?? 0, 
                                               second: 0, 
                                               of: today) {
                return displayTime
            }
        }
        
        // Fallback to legacy Date storage for backwards compatibility
        return time
    }
    
    /// Returns timezone-independent time components (hour, minute)
    var effectiveTimeComponents: DateComponents {
        if let components = timeComponents {
            return components
        }
        
        // Extract components from legacy Date storage
        let calendar = Calendar.current
        return calendar.dateComponents([.hour, .minute], from: time)
    }
    
    /// Updates the scheduled time using timezone-independent components
    mutating func setTime(hour: Int, minute: Int) {
        // Always store as timezone-independent components (primary storage)
        self.timeComponents = DateComponents(hour: hour, minute: minute)
        
        // Update legacy storage for backwards compatibility
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        self.time = calendar.date(byAdding: timeComponents!, to: today) ?? time
    }
    
    /// Updates the scheduled time from a Date (extracts components for timezone independence)
    /// This ensures the time shown will always be the same regardless of timezone
    mutating func setTime(from date: Date) {
        // Extract local time components from the date (ignore timezone)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        setTime(hour: components.hour ?? 7, minute: components.minute ?? 0)
    }
    
    var nextOccurrence: Date? {
        // No DayStart if no days are selected
        guard !repeatDays.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Use timezone-independent components
        let timeComponents = effectiveTimeComponents
        
        for dayOffset in 0..<8 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            // Skip tomorrow's occurrence if skipTomorrow is true
            // Commented out - skip tomorrow feature disabled
            // if skipTomorrow {
            //     let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            //     if calendar.isDate(candidateDate, inSameDayAs: tomorrow) {
            //         continue
            //     }
            // }
            
            let weekday = calendar.component(.weekday, from: candidateDate)
            if let weekDay = WeekDay(weekday: weekday), repeatDays.contains(weekDay) {
                var components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                
                if let scheduledTime = calendar.date(from: components), scheduledTime > now {
                    return scheduledTime
                }
            }
        }
        
        return nil
    }
    
    var nextOccurrenceAfterToday: Date? {
        // No DayStart if no days are selected
        guard !repeatDays.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        
        // Use timezone-independent components
        let timeComponents = effectiveTimeComponents
        
        // Start checking from tomorrow (dayOffset starts at 1)
        for dayOffset in 1..<8 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            let weekday = calendar.component(.weekday, from: candidateDate)
            if let weekDay = WeekDay(weekday: weekday), repeatDays.contains(weekDay) {
                var components = calendar.dateComponents([.year, .month, .day], from: candidateDate)
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                
                if let scheduledTime = calendar.date(from: components) {
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
    
    static func fromCalendarWeekday(_ weekday: Int) -> WeekDay {
        return WeekDay(weekday: weekday) ?? .sunday
    }
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .sunday: return "Su"
        case .monday: return "M"
        case .tuesday: return "Tu"
        case .wednesday: return "W"
        case .thursday: return "Th"
        case .friday: return "F"
        case .saturday: return "Sa"
        }
    }
    
    var shortName: String {
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

enum SportType: String, CaseIterable, Codable {
    case mlb = "MLB"
    case nhl = "NHL"
    case nba = "NBA"
    case nfl = "NFL"
    case ncaaf = "NCAAF"
    
    var displayName: String {
        return rawValue
    }
}

enum NewsCategory: String, CaseIterable, Codable {
    case world = "World"
    case business = "Business"
    case technology = "Technology"
    case politics = "Politics"
    case science = "Science"
    
    var displayName: String {
        return rawValue
    }
}

enum ContentType: String, CaseIterable, Identifiable {
    case weather = "Weather"
    case calendar = "Calendar"
    case quotes = "Motivational Quotes"
    case news = "News"
    case sports = "Sports"
    case stocks = "Stocks"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .weather: return "cloud.sun"
        case .calendar: return "calendar"
        case .quotes: return "quote.bubble"
        case .news: return "newspaper"
        case .sports: return "sportscourt"
        case .stocks: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var hasExpandableSettings: Bool {
        switch self {
        case .quotes, .sports, .stocks, .news: return true
        case .weather, .calendar: return false
        }
    }
    
}

struct ContentSettings: Codable {
    var quotePreference: QuotePreference = .goodFeelings
    var selectedSports: [SportType] = SportType.allCases
    var stockSymbols: [String] = ["^GSPC", "^DJI", "BTC-USD"]
    
    func isEnabled(_ type: ContentType, in userSettings: UserSettings) -> Bool {
        switch type {
        case .weather: return userSettings.includeWeather
        case .calendar: return userSettings.includeCalendar
        case .quotes: return userSettings.includeQuotes
        case .news: return userSettings.includeNews
        case .sports: return userSettings.includeSports
        case .stocks: return userSettings.includeStocks
        }
    }
}

struct UserSettings: Codable, Equatable {
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
    var dayStartLength: Int // Always 3 minutes for now, UI hidden
    var themePreference: ThemePreference
    var selectedSports: [SportType]
    var selectedNewsCategories: [NewsCategory]
    var allowReengagementNotifications: Bool
    
    static func isValidStockSymbol(_ symbol: String) -> Bool {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        // Allow letters, numbers, hyphens, dots, and equals for crypto pairs (BTC-USD), forex (EUR=X), and futures
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-.$=^"))
        return trimmed.count >= 1 && 
               trimmed.count <= 16 && // Increased to support longer symbols like BTC-USD, EUR=X
               trimmed.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
    
    static func isValidNameCharacter(_ character: Character) -> Bool {
        // Match backend logic: Basic Latin, common accented Latin, spaces, hyphens, apostrophes
        guard let scalar = character.unicodeScalars.first else { return false }
        return (scalar.value >= 0x0020 && scalar.value <= 0x007E) ||   // Basic Latin (includes spaces, punctuation)
               (scalar.value >= 0x00A0 && scalar.value <= 0x00FF) ||   // Latin-1 Supplement (accented chars)
               (scalar.value >= 0x0100 && scalar.value <= 0x017F) ||   // Latin Extended-A
               (scalar.value >= 0x0180 && scalar.value <= 0x024F)      // Latin Extended-B
    }
    
    static func sanitizeName(_ name: String) -> String {
        return name
            .filter { isValidNameCharacter($0) }
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static let maxNameLength = 50
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
            stockSymbols: ["^GSPC", "^DJI", "BTC-USD"],
            includeCalendar: false,
            includeQuotes: true,
            quotePreference: .goodFeelings,
            selectedVoice: .voice1,
            dayStartLength: 3, // Default 3 minutes
            themePreference: .system,
            selectedSports: SportType.allCases, // Default all sports selected
            selectedNewsCategories: NewsCategory.allCases, // Default all news categories selected
            allowReengagementNotifications: true // Default enabled
        )
    }
}

// MARK: - Share Functionality

struct ShareResponse: Codable {
    let shareUrl: String
    let token: String
    let expiresAt: Date
    let shareId: UUID
    
    private enum CodingKeys: String, CodingKey {
        case shareUrl = "share_url"
        case token
        case expiresAt = "expires_at"
        case shareId = "share_id"
    }
}