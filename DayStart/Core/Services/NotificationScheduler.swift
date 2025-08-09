import UserNotifications
import Foundation

class NotificationScheduler {
    static let shared = NotificationScheduler()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let mainIdentifierPrefix = "daystart_main_"
    private let prefetchIdentifierPrefix = "daystart_prefetch_"
    private let reminderIdentifierPrefix = "daystart_reminder_"
    private let missedIdentifierPrefix = "daystart_missed_"
    
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
            
            // Create the notification time for this day
            let timeComponents = calendar.dateComponents([.hour, .minute], from: schedule.time)
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
            
            // Schedule prefetch notification (30 minutes before)
            await schedulePrefetchNotification(for: notificationDate, dayOffset: dayOffset)
            
            // Schedule night-before reminder (10 hours before)
            if let reminderDate = calendar.date(byAdding: .hour, value: -10, to: notificationDate) {
                await scheduleReminderNotification(for: reminderDate, dayOffset: dayOffset)
            }
            
            // Schedule missed notification (6 hours after)
            if let missedDate = calendar.date(byAdding: .hour, value: 6, to: notificationDate) {
                await scheduleMissedNotification(for: missedDate, dayOffset: dayOffset)
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
    
    private func scheduleMainNotification(for date: Date, dayOffset: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "🌅 Time for Your DayStart!"
        content.body = "Your personalized morning briefing is ready."
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_CATEGORY"
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(mainIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled main notification for \(date)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule main notification: \(error)", level: .error)
        }
    }
    
    private func scheduleReminderNotification(for date: Date, dayOffset: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "🌙 Your DayStart is Scheduled"
        content.body = "Tomorrow's morning briefing is set. Click to edit."
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_REMINDER_CATEGORY"
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(reminderIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled reminder notification for \(date)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule reminder notification: \(error)", level: .error)
        }
    }
    
    private func schedulePrefetchNotification(for date: Date, dayOffset: Int) async {
        let prefetchTime = date.addingTimeInterval(-30 * 60) // 30 minutes before
        
        // Only schedule if prefetch time is in the future
        guard prefetchTime > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "" // Silent notification
        content.body = ""
        content.sound = nil
        // This triggers background app refresh for audio download
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: prefetchTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(prefetchIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled prefetch notification for \(prefetchTime)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule prefetch notification: \(error)", level: .error)
        }
    }
    
    private func scheduleMissedNotification(for date: Date, dayOffset: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Your DayStart is Waiting"
        content.body = "Don't miss your personalized morning briefing!"
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_MISSED_CATEGORY"
        
        let calendar = Calendar.current
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let identifier = "\(missedIdentifierPrefix)\(dayOffset)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            DebugLogger.shared.log("Scheduled missed notification for \(date)", level: .info)
        } catch {
            DebugLogger.shared.log("Failed to schedule missed notification: \(error)", level: .error)
        }
    }
}