import Foundation
import CoreLocation

// Note: LocationData and WeatherData types are defined in LocationManager.swift

/// Generates personalized notification content with variety to increase engagement
class NotificationContentGenerator {
    static let shared = NotificationContentGenerator()
    
    private let logger = DebugLogger.shared
    
    // MARK: - Notification Style Types
    
    enum MorningStyle: String, CaseIterable {
        case weather = "weather"
        case calendar = "calendar"
        case streak = "streak"
        case dayOfWeek = "dayOfWeek"
        case duration = "duration"
        case location = "location"
        case energizing = "energizing"
    }
    
    enum NightBeforeStyle: String, CaseIterable {
        case weatherPreview = "weatherPreview"
        case calendarPreview = "calendarPreview"
        case dayPreview = "dayPreview"
        case timeReminder = "timeReminder"
    }
    
    enum StreakStyle: String, CaseIterable {
        case milestone = "milestone"
        case competitive = "competitive"
        case motivational = "motivational"
        case timeWarning = "timeWarning"
        case weekdayPerfect = "weekdayPerfect"
    }
    
    // MARK: - History Tracking
    
    private struct NotificationHistory: Codable {
        var lastMorningStyle: String?
        var lastNightStyle: String?
        var lastStreakStyle: String?
        var lastUsedDate: Date
        var styleUsageCounts: [String: Int] = [:]
    }
    
    private var history: NotificationHistory {
        get {
            if let data = UserDefaults.standard.data(forKey: "NotificationHistory"),
               let decoded = try? JSONDecoder().decode(NotificationHistory.self, from: data) {
                return decoded
            }
            return NotificationHistory(lastUsedDate: Date())
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: "NotificationHistory")
            }
        }
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Generate morning notification content with variety
    func generateMorningNotification(
        date: Date,
        weather: WeatherData?,
        calendarCount: Int,
        streak: Int,
        location: LocationData?,
        duration: TimeInterval
    ) -> (title: String, body: String) {
        let style = selectMorningStyle(
            date: date,
            weather: weather,
            calendarCount: calendarCount,
            streak: streak
        )
        
        logger.log("📱 Generating morning notification with style: \(style.rawValue)", level: .debug)
        updateHistory(morningStyle: style)
        
        switch style {
        case .weather:
            return generateWeatherNotification(weather: weather)
        case .calendar:
            return generateCalendarNotification(calendarCount: calendarCount)
        case .streak:
            return generateStreakNotification(streak: streak)
        case .dayOfWeek:
            return generateDayOfWeekNotification(date: date)
        case .duration:
            return generateDurationNotification(duration: duration)
        case .location:
            return generateLocationNotification(location: location)
        case .energizing:
            return generateEnergizingNotification()
        }
    }
    
    /// Generate night-before reminder content
    func generateNightBeforeNotification(
        tomorrowDate: Date,
        tomorrowWeather: WeatherData?,
        tomorrowCalendarCount: Int,
        scheduledTime: Date
    ) -> (title: String, body: String) {
        let style = selectNightBeforeStyle()
        
        logger.log("🌙 Generating night-before notification with style: \(style.rawValue)", level: .debug)
        updateHistory(nightStyle: style)
        
        switch style {
        case .weatherPreview:
            return generateWeatherPreviewNotification(weather: tomorrowWeather, date: tomorrowDate)
        case .calendarPreview:
            return generateCalendarPreviewNotification(count: tomorrowCalendarCount, date: tomorrowDate)
        case .dayPreview:
            return generateDayPreviewNotification(date: tomorrowDate)
        case .timeReminder:
            return generateTimeReminderNotification(time: scheduledTime)
        }
    }
    
    /// Generate streak reminder content
    func generateStreakReminder(
        streak: Int,
        dayOfWeek: String
    ) -> (title: String, body: String) {
        let style = selectStreakStyle(streak: streak, dayOfWeek: dayOfWeek)
        
        logger.log("🔥 Generating streak reminder with style: \(style.rawValue)", level: .debug)
        updateHistory(streakStyle: style)
        
        switch style {
        case .milestone:
            return generateMilestoneReminder(streak: streak)
        case .competitive:
            return generateCompetitiveReminder(streak: streak)
        case .motivational:
            return generateMotivationalReminder()
        case .timeWarning:
            return generateTimeWarningReminder()
        case .weekdayPerfect:
            return generateWeekdayPerfectReminder(dayOfWeek: dayOfWeek)
        }
    }
    
    // MARK: - Style Selection Logic
    
    private func selectMorningStyle(
        date: Date,
        weather: WeatherData?,
        calendarCount: Int,
        streak: Int
    ) -> MorningStyle {
        // Priority rules
        
        // 1. Extreme weather always gets priority
        if let weather = weather {
            // Prefer forecast high temp, fallback to current temp
            let temp = weather.highTemperatureF ?? weather.temperatureF
            if let temp = temp {
                if temp < 32 || temp > 90 || 
                   weather.condition?.lowercased().contains("storm") ?? false ||
                   weather.condition?.lowercased().contains("snow") ?? false {
                    return .weather
                }
            }
        }
        
        // 2. Streak milestones
        if [7, 14, 30, 50, 100].contains(streak) {
            return .streak
        }
        
        // 3. Busy calendar
        if calendarCount >= 4 {
            return .calendar
        }
        
        // 4. Day-specific content
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 2 { // Monday
            return .dayOfWeek
        }
        if weekday == 6 { // Friday
            return .dayOfWeek
        }
        
        // 5. Default rotation avoiding recent styles
        var availableStyles = MorningStyle.allCases
        
        // Remove last used style
        if let lastStyle = history.lastMorningStyle,
           let style = MorningStyle(rawValue: lastStyle) {
            availableStyles.removeAll { $0 == style }
        }
        
        // Pick least used style
        let leastUsed = availableStyles.min { style1, style2 in
            let count1 = history.styleUsageCounts[style1.rawValue] ?? 0
            let count2 = history.styleUsageCounts[style2.rawValue] ?? 0
            return count1 < count2
        }
        
        return leastUsed ?? .energizing
    }
    
    private func selectNightBeforeStyle() -> NightBeforeStyle {
        var availableStyles = NightBeforeStyle.allCases
        
        // Remove last used style
        if let lastStyle = history.lastNightStyle,
           let style = NightBeforeStyle(rawValue: lastStyle) {
            availableStyles.removeAll { $0 == style }
        }
        
        // Simple rotation
        return availableStyles.randomElement() ?? .dayPreview
    }
    
    private func selectStreakStyle(streak: Int, dayOfWeek: String) -> StreakStyle {
        // Milestone approaching
        if [6, 13, 29, 49, 99].contains(streak) {
            return .milestone
        }
        
        // Friday perfect week check
        if dayOfWeek == "Friday" && streak >= 4 {
            return .weekdayPerfect
        }
        
        // Default rotation
        var availableStyles = StreakStyle.allCases
        
        if let lastStyle = history.lastStreakStyle,
           let style = StreakStyle(rawValue: lastStyle) {
            availableStyles.removeAll { $0 == style }
        }
        
        return availableStyles.randomElement() ?? .motivational
    }
    
    // MARK: - Content Generators
    
    // Morning Notifications
    
    private func generateWeatherNotification(weather: WeatherData?) -> (String, String) {
        guard let weather = weather, 
              let condition = weather.condition?.lowercased() else {
            return ("🌅 Time for Your DayStart!", "Your personalized morning briefing is ready.")
        }
        
        // Prefer forecast high temp, fallback to current temp
        let temp = weather.highTemperatureF ?? weather.temperatureF
        
        if let temp = temp {
            if temp < 32 {
                return ("🌅 Brrr! High of \(temp)°F", "Bundle up! Your DayStart includes cold weather tips.")
            } else if temp > 90 {
                return ("🌅 Hot day ahead! High of \(temp)°F", "Stay cool - your briefing is ready.")
            } else if condition.contains("rain") {
                return ("🌅 High of \(temp)°F and rainy", "Your DayStart has umbrella weather updates.")
            } else if condition.contains("snow") {
                return ("❄️ Snow day! High of \(temp)°F", "Your briefing includes weather safety tips.")
            } else if condition.contains("sunny") || condition.contains("clear") {
                return ("🌅 Beautiful \(temp)°F high", "Perfect day ahead - get briefed!")
            } else {
                return ("🌅 High of \(temp)°F and \(weather.condition ?? "")", "Your morning briefing is ready.")
            }
        } else {
            // No temperature available, use condition only
            if condition.contains("rain") {
                return ("🌧️ Rainy day vibes", "Your DayStart has umbrella weather updates.")
            } else if condition.contains("snow") {
                return ("❄️ Snow day energy!", "Your briefing includes weather safety tips.")
            } else if condition.contains("sunny") || condition.contains("clear") {
                return ("☀️ Beautiful day ahead!", "Perfect weather - get briefed!")
            } else {
                return ("🌅 \(weather.condition ?? "Weather") update", "Your morning briefing is ready.")
            }
        }
    }
    
    private func generateCalendarNotification(calendarCount: Int) -> (String, String) {
        if calendarCount == 0 {
            return ("🌅 Clear calendar today!", "Your schedule-free briefing awaits.")
        } else if calendarCount == 1 {
            return ("🌅 You have 1 event today", "Get briefed before your meeting.")
        } else if calendarCount <= 3 {
            return ("🌅 \(calendarCount) events on deck", "Start prepared with your DayStart.")
        } else {
            return ("🌅 Busy day! \(calendarCount) events", "Essential briefing before the rush.")
        }
    }
    
    private func generateStreakNotification(streak: Int) -> (String, String) {
        switch streak {
        case 7:
            return ("🎉 One week streak!", "Your briefing celebrates 7 days strong.")
        case 14:
            return ("🔥 Two week champion!", "14 days of morning excellence awaits.")
        case 30:
            return ("🏆 30-day DayStart Master!", "Your achievement briefing is ready.")
        case 50:
            return ("💎 50 days of brilliance!", "Half-century streak briefing awaits.")
        case 100:
            return ("👑 Century streak legend!", "100 days strong - briefing ready!")
        default:
            return ("🔥 Day \(streak) streak!", "Keep the momentum with today's briefing.")
        }
    }
    
    private func generateDayOfWeekNotification(date: Date) -> (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date)
        
        switch dayName {
        case "Monday":
            return ("🌅 Monday momentum!", "Conquer your week starting now.")
        case "Tuesday":
            return ("🌅 Tuesday triumph awaits", "Stay sharp with your briefing.")
        case "Wednesday":
            return ("🌅 Hump day hustle", "Midweek briefing powers you through.")
        case "Thursday":
            return ("🌅 Thriving Thursday", "Almost there - stay informed!")
        case "Friday":
            return ("🌅 TGIF! Friday briefing", "End your week on a high note.")
        case "Saturday":
            return ("🌅 Saturday wisdom", "Weekend warriors stay informed.")
        case "Sunday":
            return ("🌅 Sunday strategy", "Prep for the week ahead.")
        default:
            return ("🌅 Rise and shine!", "Your daily briefing awaits.")
        }
    }
    
    private func generateDurationNotification(duration: TimeInterval) -> (String, String) {
        let minutes = Int(duration / 60)
        return ("🌅 Your \(minutes)-minute briefing", "Perfect morning companion ready.")
    }
    
    private func generateLocationNotification(location: LocationData?) -> (String, String) {
        if let city = location?.city {
            return ("🌅 Good morning from \(city)!", "Your local briefing is ready.")
        }
        return ("🌅 Rise and shine!", "Your personalized briefing awaits.")
    }
    
    private func generateEnergizingNotification() -> (String, String) {
        let options = [
            ("🌅 Rise and conquer!", "Leaders start with DayStart."),
            ("🌅 Seize the day!", "Your power briefing awaits."),
            ("🌅 Morning excellence calls", "Answer with your DayStart."),
            ("🌅 Wake up. Get briefed.", "DayStart is ready for you.")
        ]
        return options.randomElement() ?? options[0]
    }
    
    // Night-Before Notifications
    
    private func generateWeatherPreviewNotification(weather: WeatherData?, date: Date) -> (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date)
        
        if let weather = weather {
            // Prefer forecast high temp, fallback to current temp
            let temp = weather.highTemperatureF ?? weather.temperatureF
            let condition = weather.condition?.lowercased() ?? "expected"
            
            if let temp = temp {
                return ("🌙 \(dayName): High of \(temp)°F and \(condition)", 
                        "Your morning briefing is scheduled.")
            } else {
                return ("🌙 \(dayName): \(condition) weather expected", 
                        "Your morning briefing is scheduled.")
            }
        }
        return ("🌙 Your \(dayName) DayStart is set", "Tomorrow's briefing awaits at dawn.")
    }
    
    private func generateCalendarPreviewNotification(count: Int, date: Date) -> (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date)
        
        if count == 0 {
            return ("🌙 Clear \(dayName) ahead", "Your schedule-free briefing is set.")
        } else if count == 1 {
            return ("🌙 \(dayName): 1 event scheduled", "DayStart will prep you.")
        } else {
            return ("🌙 Big \(dayName): \(count) events", "Wake up prepared with DayStart.")
        }
    }
    
    private func generateDayPreviewNotification(date: Date) -> (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date)
        
        switch dayName {
        case "Friday":
            return ("🌙 Friday briefing scheduled", "End your week informed.")
        case "Monday":
            return ("🌙 Monday prep scheduled", "Start your week strong.")
        case "Saturday", "Sunday":
            return ("🌙 Weekend briefing set", "Leaders never stop learning.")
        default:
            return ("🌙 \(dayName) briefing scheduled", "Stay ahead with DayStart.")
        }
    }
    
    private func generateTimeReminderNotification(time: Date) -> (String, String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: time)
        return ("🌙 DayStart set for \(timeString)", "Your morning briefing awaits.")
    }
    
    // Streak Reminders
    
    private func generateMilestoneReminder(streak: Int) -> (String, String) {
        switch streak {
        case 6:
            return ("🔥 One day from weekly badge!", "Listen now to reach 7 days tomorrow.")
        case 13:
            return ("🔥 Two weeks tomorrow!", "Keep your 13-day streak alive.")
        case 29:
            return ("🔥 Monthly milestone awaits!", "One more for your 30-day badge.")
        case 49:
            return ("🔥 50-day achievement tomorrow!", "Listen to unlock the milestone.")
        case 99:
            return ("🔥 Century streak tomorrow!", "Make history with day 100.")
        default:
            return ("🔥 Keep Your Streak Alive", "Day \(streak + 1) awaits tomorrow!")
        }
    }
    
    private func generateCompetitiveReminder(streak: Int) -> (String, String) {
        if streak >= 30 {
            return ("🔥 Top 1% of DayStarters!", "Elite streakers never miss.")
        } else if streak >= 14 {
            return ("🔥 Top 10% streak status!", "Champions listen every day.")
        } else if streak >= 7 {
            return ("🔥 You're outpacing 80% of users", "Keep your edge - listen now.")
        } else {
            return ("🔥 Join the streak elite", "Day \(streak) proves you're serious.")
        }
    }
    
    private func generateMotivationalReminder() -> (String, String) {
        let options = [
            ("🔥 Champions never skip", "Your streak depends on you."),
            ("🔥 Success is a daily habit", "Keep your DayStart streak."),
            ("🔥 Leaders stay consistent", "Don't break the chain."),
            ("🔥 Excellence is daily", "Maintain your morning routine.")
        ]
        return options.randomElement() ?? options[0]
    }
    
    private func generateTimeWarningReminder() -> (String, String) {
        return ("🔥 2 hours left today!", "Save your streak - listen now.")
    }
    
    private func generateWeekdayPerfectReminder(dayOfWeek: String) -> (String, String) {
        if dayOfWeek == "Friday" {
            return ("🔥 Perfect week within reach!", "Finish strong with Friday's briefing.")
        } else {
            return ("🔥 Weekday streak on fire!", "Keep the momentum going.")
        }
    }
    
    // MARK: - History Management
    
    private func updateHistory(morningStyle: MorningStyle? = nil, 
                              nightStyle: NightBeforeStyle? = nil,
                              streakStyle: StreakStyle? = nil) {
        var updatedHistory = history
        
        if let style = morningStyle {
            updatedHistory.lastMorningStyle = style.rawValue
            updatedHistory.styleUsageCounts[style.rawValue, default: 0] += 1
        }
        
        if let style = nightStyle {
            updatedHistory.lastNightStyle = style.rawValue
            updatedHistory.styleUsageCounts[style.rawValue, default: 0] += 1
        }
        
        if let style = streakStyle {
            updatedHistory.lastStreakStyle = style.rawValue
            updatedHistory.styleUsageCounts[style.rawValue, default: 0] += 1
        }
        
        updatedHistory.lastUsedDate = Date()
        
        // Reset counts if it's been more than 30 days
        if Date().timeIntervalSince(updatedHistory.lastUsedDate) > 30 * 24 * 60 * 60 {
            updatedHistory.styleUsageCounts = [:]
        }
        
        history = updatedHistory
    }
    
    // MARK: - Re-engagement Notifications
    
    /// Generate re-engagement notification content based on inactivity type
    func generateReengagementNotification(
        type: ReengagementType,
        streak: Int,
        daysInactive: Int
    ) -> (title: String, body: String) {
        
        logger.log("🔔 Generating \(type.rawValue) re-engagement notification (streak: \(streak), inactive: \(daysInactive))", level: .debug)
        
        switch type {
        case .gentle:
            return generateGentleReengagement(streak: streak, daysInactive: daysInactive)
        case .value:
            return generateValueReengagement(streak: streak, daysInactive: daysInactive)
        case .final:
            return generateFinalReengagement(streak: streak, daysInactive: daysInactive)
        }
    }
    
    private func generateGentleReengagement(streak: Int, daysInactive: Int) -> (String, String) {
        // Focus on gentle nudges and streak awareness
        if streak >= 14 {
            return ("🔥 Missing your morning edge?", "Your \(streak)-day streak wants to continue")
        } else if streak >= 7 {
            return ("🌅 Ready to restart your routine?", "Week-long streaks take dedication - you've got this")
        } else if daysInactive >= 10 {
            return ("☀️ Your mornings miss you", "10 days without your briefing - ready to return?")
        } else {
            let options = [
                ("🌅 Time to rise and shine again?", "Your personalized briefing is waiting"),
                ("🔥 Ready to restart your streak?", "Every expert was once a beginner"),
                ("☀️ Missing your morning momentum?", "Leaders never stay down for long")
            ]
            return options.randomElement() ?? options[0]
        }
    }
    
    private func generateValueReengagement(streak: Int, daysInactive: Int) -> (String, String) {
        // Emphasize the value and benefits of DayStart
        let options = [
            ("🎯 Stay ahead of your day", "20 minutes saved daily with AI-curated updates"),
            ("📰 The world kept moving", "Catch up with personalized news + weather"),
            ("⚡ Leaders stay informed", "Your executive briefing is ready"),
            ("🌅 Mornings made simple", "Weather, news, calendar - all in one place"),
            ("🧠 Smart people stay current", "AI picks what matters to you"),
            ("📅 Big week ahead?", "Get prepared with your morning briefing")
        ]
        
        // Special case for high streaks
        if streak >= 30 {
            return ("👑 Elite performers return", "30+ day veterans don't quit - they restart")
        } else if streak >= 14 {
            return ("🏆 Champions make comebacks", "Your \(streak)-day streak proved your commitment")
        }
        
        return options.randomElement() ?? options[0]
    }
    
    private func generateFinalReengagement(streak: Int, daysInactive: Int) -> (String, String) {
        // Final retention attempt with warmth and value
        if streak >= 21 {
            return ("💎 We miss our daily time together", "Elite streakers like you built something special")
        } else if daysInactive >= 30 {
            return ("🎁 Welcome back gift waiting", "A month away? Your perfect comeback briefing is ready")
        } else {
            let options = [
                ("✨ Something special awaits", "New features and improvements while you were away"),
                ("🤝 Your morning partner misses you", "Ready for a fresh start together?"),
                ("🌟 The best is yet to come", "Your personalized experience is better than ever"),
                ("🏠 Home is where the heart is", "Your DayStart family welcomes you back"),
                ("🚀 Ready for your comeback?", "Every champion has a return story")
            ]
            return options.randomElement() ?? options[0]
        }
    }
}