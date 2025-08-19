import EventKit
import Foundation
import Combine

class CalendarManager: NSObject, ObservableObject {
    static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    private let logger = DebugLogger.shared
    
    private override init() {}
    
    // MARK: - Permission Management
    
    func requestCalendarAccess() async -> Bool {
        return await withCheckedContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error = error {
                    self.logger.logError(error, context: "Failed to request calendar access")
                }
                self.logger.log("Calendar access granted: \(granted)", level: granted ? .info : .warning)
                continuation.resume(returning: granted)
            }
        }
    }
    
    func hasCalendarAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .authorized
    }
    
    // MARK: - Event Retrieval
    
    func getTodaysEvents() -> [EKEvent] {
        guard hasCalendarAccess() else {
            logger.log("Cannot fetch calendar events: access not granted", level: .warning)
            return []
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            logger.log("Failed to calculate tomorrow's date", level: .error)
            return []
        }
        
        let predicate = eventStore.predicateForEvents(
            withStart: today,
            end: tomorrow,
            calendars: nil // All calendars
        )
        
        let events = eventStore.events(matching: predicate)
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
        
        logger.log("Retrieved \(sortedEvents.count) events for today", level: .info)
        return sortedEvents
    }
    
    func getUpcomingEvents(days: Int = 2) -> [EKEvent] {
        guard hasCalendarAccess() else {
            logger.log("Cannot fetch calendar events: access not granted", level: .warning)
            return []
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        guard let endDate = calendar.date(byAdding: .day, value: days, to: today) else {
            logger.log("Failed to calculate end date for upcoming events", level: .error)
            return []
        }
        
        let predicate = eventStore.predicateForEvents(
            withStart: today,
            end: endDate,
            calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
        
        logger.log("Retrieved \(sortedEvents.count) upcoming events", level: .info)
        return sortedEvents
    }
    
    func getEventsForDate(_ date: Date) -> [EKEvent] {
        guard hasCalendarAccess() else {
            logger.log("Cannot fetch calendar events: access not granted", level: .warning)
            return []
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            logger.log("Failed to calculate end of day for \(date)", level: .error)
            return []
        }
        
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }
        
        logger.log("Retrieved \(sortedEvents.count) events for \(date)", level: .info)
        return sortedEvents
    }
    
    // MARK: - Event Formatting
    
    func formatEventsForDayStart(_ events: [EKEvent]) -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return events.compactMap { event in
            guard let title = event.title, !title.isEmpty else { return nil }
            
            let isToday = calendar.isDate(event.startDate, inSameDayAs: today)
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            
            if event.isAllDay {
                return isToday ? "\(title) (all day)" : "\(title) on \(formatDate(event.startDate))"
            } else {
                let timeString = timeFormatter.string(from: event.startDate)
                return isToday ? "\(title) at \(timeString)" : "\(title) on \(formatDate(event.startDate)) at \(timeString)"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Available Calendars
    
    func getAvailableCalendars() -> [EKCalendar] {
        guard hasCalendarAccess() else { return [] }
        
        let calendars = eventStore.calendars(for: .event)
        logger.log("Found \(calendars.count) available calendars", level: .info)
        
        for calendar in calendars {
        }
        
        return calendars
    }
}