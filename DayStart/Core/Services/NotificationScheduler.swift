import UserNotifications
import Foundation

class NotificationScheduler {
    static let shared = NotificationScheduler()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let mainIdentifierPrefix = "daystart_main_"
    private let reminderIdentifierPrefix = "daystart_reminder_"
    private let missedIdentifierPrefix = "daystart_missed_"
    private let streakEveningIdentifierPrefix = "daystart_streak_evening_"
    
    private init() {}
    
    func scheduleNotifications(for schedule: DayStartSchedule) async {
        // First, remove all pending notifications
        await cancelAllNotifications()
        
        // Request permission if needed
        let hasPermission = await requestPermission()
        guard hasPermission else {
            DebugLogger.shared.log("Notification permission denied", level: .warning)
            return
        }
        
        // Schedule notifications for the next 48 hours (2 days max)
        let calendar = Calendar.current
        let now = Date()
        let maxScheduleTime = now.addingTimeInterval(48 * 60 * 60) // 48 hours from now
        
        for dayOffset in 0..<3 { // Check today, tomorrow, day after (max 2 days out)
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            // Skip tomorrow if skipTomorrow is enabled
            if schedule.skipTomorrow {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                if calendar.isDate(targetDate, inSameDayAs: tomorrow) {
                    continue
                }
            }
            
            // Check if this day is in the repeat schedule
            let weekday = calendar.component(.weekday, from: targetDate)
            guard let weekDay = WeekDay(weekday: weekday),
                  schedule.repeatDays.contains(weekDay) else {
                continue
            }
            
            // Create the notification time for this day using timezone-independent components
            let timeComponents = schedule.effectiveTimeComponents
            var notificationComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            notificationComponents.hour = timeComponents.hour
            notificationComponents.minute = timeComponents.minute
            
            guard let notificationDate = calendar.date(from: notificationComponents),
                  notificationDate > now,
                  notificationDate <= maxScheduleTime else {
                continue
            }
            
            // Schedule main notification
            await scheduleMainNotification(for: notificationDate, dayOffset: dayOffset)
            
            // Schedule a BG processing window near this occurrence
            await MainActor.run {
                AudioPrefetchManager.shared.scheduleAudioPrefetch(for: notificationDate)
            }
            
            // Ensure a placeholder job exists far in advance without forcing early processing
            Task.detached {
                do {
                    let status = try await SupabaseClient.shared.getAudioStatus(for: notificationDate)
                    if status.status == "not_found" || status.status == "queued" || status.status == "failed" {
                        // Build snapshot for context data (location, weather, calendar) using local date
                        let localDate = Calendar.current.startOfDay(for: notificationDate)
                        let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: localDate)
                        _ = try? await SupabaseClient.shared.createJob(
                            for: notificationDate,
                            with: UserPreferences.shared.settings,
                            schedule: UserPreferences.shared.schedule,
                            locationData: snapshot.location,
                            weatherData: snapshot.weather,
                            calendarEvents: snapshot.calendar
                        )
                    }
                } catch {
                    DebugLogger.shared.logError(error, context: "Placeholder job ensure failed")
                }
            }
            
            // Note: Prefetch functionality removed - local notifications cannot trigger background fetch
            
            // Schedule night-before reminder (10 hours before)
            if let reminderDate = calendar.date(byAdding: .hour, value: -10, to: notificationDate) {
                await scheduleReminderNotification(for: reminderDate, dayOffset: dayOffset)
            }
            
            // Notifications to encourage listening without duplicates:
            // - Today (dayOffset == 0): schedule ONLY the evening streak reminder (8 PM), skip the 6-hour "missed" to avoid overlap
            // - Future days: schedule the standard 6-hour missed notification; do NOT schedule evening reminders in advance
            if dayOffset == 0 {
                if var eveningComponents = calendar.dateComponents([.year, .month, .day], from: targetDate) as DateComponents? {
                    eveningComponents.hour = 20
                    eveningComponents.minute = 0
                    if let eveningDate = calendar.date(from: eveningComponents), eveningDate > now, eveningDate <= maxScheduleTime {
                        await scheduleStreakEveningReminder(for: eveningDate, dayOffset: dayOffset)
                    }
                }
            } else {
                if let missedDate = calendar.date(byAdding: .hour, value: 6, to: notificationDate) {
                    await scheduleMissedNotification(for: missedDate, dayOffset: dayOffset)
                }
            }
        }
        
        // Log total scheduled notifications
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        DebugLogger.shared.log("Total scheduled notifications (48hr window): \(pendingRequests.count)", level: .info)
    }
    
    func cancelAllNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
        DebugLogger.shared.log("Cancelled all pending notifications", level: .info)
    }
    
    func getScheduledNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }
    
    private func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            DebugLogger.shared.log("Failed to request notification permission: \(error)", level: .error)
            return false
        }
    }
    
    func setupNotificationActions() {
        // Define notification actions
        let listenAction = UNNotificationAction(
            identifier: "LISTEN_ACTION",
            title: "Listen Now",
            options: [.foreground]
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP_ACTION",
            title: "Skip Today",
            options: []
        )
        
        let editAction = UNNotificationAction(
            identifier: "EDIT_ACTION",
            title: "Edit Schedule",
            options: [.foreground]
        )
        
        // Define categories
        let mainCategory = UNNotificationCategory(
            identifier: "DAYSTART_CATEGORY",
            actions: [listenAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        let reminderCategory = UNNotificationCategory(
            identifier: "DAYSTART_REMINDER_CATEGORY",
            actions: [editAction],
            intentIdentifiers: [],
            options: []
        )
        
        let missedCategory = UNNotificationCategory(
            identifier: "DAYSTART_MISSED_CATEGORY",
            actions: [listenAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Set categories
        notificationCenter.setNotificationCategories([mainCategory, reminderCategory, missedCategory])
    }
    
    func handleNotificationAction(_ actionIdentifier: String, for notificationIdentifier: String) {
        switch actionIdentifier {
        case "LISTEN_ACTION":
            DebugLogger.shared.log("User chose to listen from notification", level: .info)
            // This would typically trigger the app to open and start playback
            
        case "SKIP_ACTION":
            DebugLogger.shared.log("User chose to skip from notification", level: .info)
            // Mark today as skipped
            
        case "EDIT_ACTION":
            DebugLogger.shared.log("User chose to edit schedule from notification", level: .info)
            // This would typically open the edit schedule view
            
        default:
            break
        }
    }
    
    func getNextScheduledTime(for schedule: DayStartSchedule) async -> Date? {
        let requests = await getScheduledNotifications()
        
        let sortedTimes = requests
            .compactMap { request -> Date? in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let nextTriggerDate = trigger.nextTriggerDate() else {
                    return nil
                }
                return nextTriggerDate
            }
            .sorted()
        
        return sortedTimes.first
    }
    
    func cancelMissedNotifications(forDayOffsets dayOffsets: [Int]) async {
        let identifiers = dayOffsets.map { "\(missedIdentifierPrefix)\($0)" }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        DebugLogger.shared.log("Cancelled missed notifications for day offsets: \(dayOffsets)", level: .info)
    }
    
    func cancelTodaysMissedNotification() async {
        // Calculate today's day offset from when notifications were scheduled
        let calendar = Calendar.current
        let now = Date()
        
        // Find today's missed notification by checking all pending notifications
        let requests = await getScheduledNotifications()
        let todaysIdentifiers = requests
            .filter { request in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let nextTriggerDate = trigger.nextTriggerDate() else {
                    return false
                }
                
                // Check if this is a missed notification scheduled for today
                return request.identifier.hasPrefix(missedIdentifierPrefix) &&
                       calendar.isDate(nextTriggerDate, inSameDayAs: now)
            }
            .map { $0.identifier }
        
        if !todaysIdentifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: todaysIdentifiers)
            DebugLogger.shared.log("Cancelled today's missed notifications: \(todaysIdentifiers)", level: .info)
        }
    }

    func cancelTodaysEveningReminder() async {
        let calendar = Calendar.current
        let now = Date()
        let requests = await getScheduledNotifications()
        let todaysIdentifiers = requests
            .filter { request in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let nextTriggerDate = trigger.nextTriggerDate() else {
                    return false
                }
                return request.identifier.hasPrefix(streakEveningIdentifierPrefix) &&
                       calendar.isDate(nextTriggerDate, inSameDayAs: now)
            }
            .map { $0.identifier }

        if !todaysIdentifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: todaysIdentifiers)
            DebugLogger.shared.log("Cancelled today's streak evening reminders: \(todaysIdentifiers)", level: .info)
        }
    }
    
    private func scheduleMainNotification(for date: Date, dayOffset: Int) async {
        // Build snapshot to get weather, location, and calendar data
        let localDate = Calendar.current.startOfDay(for: date)
        let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: localDate)
        
        // Get current streak and duration
        let streak = await MainActor.run { StreakManager.shared.currentStreak }
        let duration = await MainActor.run { TimeInterval(UserPreferences.shared.settings.dayStartLength * 60) }
        
        // Generate personalized notification content
        let (title, body) = NotificationContentGenerator.shared.generateMorningNotification(
            date: date,
            weather: snapshot.weather,
            calendarCount: snapshot.calendar?.count ?? 0,
            streak: streak,
            location: snapshot.location,
            duration: duration
        )
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_CATEGORY"
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(mainIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled personalized main notification for \(date): \(title)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule main notification: \(error)", level: .error)
        }
    }
    
    private func scheduleReminderNotification(for date: Date, dayOffset: Int) async {
        // Calculate tomorrow's date for the preview
        let calendar = Calendar.current
        guard let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: date) else { return }
        
        // Build snapshot for tomorrow's data
        let localTomorrowDate = calendar.startOfDay(for: tomorrowDate)
        let tomorrowSnapshot = await SnapshotBuilder.shared.buildSnapshot(for: localTomorrowDate)
        
        // Get scheduled time for tomorrow using timezone-independent time
        let scheduledTime = await MainActor.run { UserPreferences.shared.schedule.effectiveTime }
        
        // Generate personalized night-before notification
        let (title, body) = NotificationContentGenerator.shared.generateNightBeforeNotification(
            tomorrowDate: tomorrowDate,
            tomorrowWeather: tomorrowSnapshot.weather,
            tomorrowCalendarCount: tomorrowSnapshot.calendar?.count ?? 0,
            scheduledTime: scheduledTime
        )
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_REMINDER_CATEGORY"
        
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(reminderIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled personalized reminder notification for \(date): \(title)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule reminder notification: \(error)", level: .error)
        }
    }
    
    // Removed: schedulePrefetchNotification - local notifications cannot trigger background fetch
    // If background processing is needed in future, use BGTaskScheduler or remote silent pushes
    
    private func scheduleMissedNotification(for date: Date, dayOffset: Int) async {
        // Use a motivational reminder style for missed notifications
        let streak = await MainActor.run { StreakManager.shared.currentStreak }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayOfWeek = formatter.string(from: date)
        
        // Generate personalized missed notification using streak reminder
        let (title, body) = NotificationContentGenerator.shared.generateStreakReminder(
            streak: streak,
            dayOfWeek: dayOfWeek
        )
        
        // Override with missed-specific messaging if generic
        let finalTitle = title.contains("Streak") ? title : "⏰ Your DayStart is Waiting"
        let finalBody = body.contains("streak") || body.contains("Streak") ? body : "Don't miss your personalized morning briefing!"
        
        let content = UNMutableNotificationContent()
        content.title = finalTitle
        content.body = finalBody
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_MISSED_CATEGORY"
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(missedIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled personalized missed notification for \(date): \(finalTitle)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule missed notification: \(error)", level: .error)
        }
    }

    private func scheduleStreakEveningReminder(for date: Date, dayOffset: Int) async {
        // Get current streak and day of week
        let streak = await MainActor.run { StreakManager.shared.currentStreak }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayOfWeek = formatter.string(from: date)
        
        // Generate personalized streak reminder
        let (title, body) = NotificationContentGenerator.shared.generateStreakReminder(
            streak: streak,
            dayOfWeek: dayOfWeek
        )
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_MISSED_CATEGORY" // Reuse listen action

        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let identifier = "\(streakEveningIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled personalized streak reminder for \(date): \(title)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule streak evening reminder: \(error)", level: .error)
        }
    }
}