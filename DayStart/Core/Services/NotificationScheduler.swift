import UserNotifications
import Foundation

class NotificationScheduler {
    static let shared = NotificationScheduler()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationIdentifier = "DayStartNotification"
    
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
        
        // Schedule notifications for the next 30 days
        let calendar = Calendar.current
        let now = Date()
        
        for dayOffset in 0..<30 {
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
                  notificationDate > now else {
                continue
            }
            
            // Create the notification
            let content = UNMutableNotificationContent()
            content.title = "🌅 Time for Your DayStart!"
            content.body = "Your personalized morning briefing is ready."
            content.sound = .default
            content.categoryIdentifier = "DAYSTART_CATEGORY"
            
            // Create trigger
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            
            // Create request
            let identifier = "\(notificationIdentifier)_\(dayOffset)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            // Schedule notification
            do {
                try await notificationCenter.add(request)
                DebugLogger.shared.log("Scheduled notification for \(notificationDate)", level: .info)
            } catch {
                DebugLogger.shared.log("Failed to schedule notification: \(error)", level: .error)
            }
        }
        
        // Log total scheduled notifications
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        DebugLogger.shared.log("Total scheduled notifications: \(pendingRequests.count)", level: .info)
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
        
        // Define category
        let category = UNNotificationCategory(
            identifier: "DAYSTART_CATEGORY",
            actions: [listenAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Set categories
        notificationCenter.setNotificationCategories([category])
    }
    
    func handleNotificationAction(_ actionIdentifier: String, for notificationIdentifier: String) {
        switch actionIdentifier {
        case "LISTEN_ACTION":
            DebugLogger.shared.log("User chose to listen from notification", level: .info)
            // This would typically trigger the app to open and start playback
            
        case "SKIP_ACTION":
            DebugLogger.shared.log("User chose to skip from notification", level: .info)
            // Mark today as skipped
            
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
}