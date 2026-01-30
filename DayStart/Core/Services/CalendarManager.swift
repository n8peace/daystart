import EventKit
import Foundation
import Combine
import CoreLocation

// MARK: - Event Location Data Structure
struct EventLocation: Codable {
    let locationName: String
    let coordinates: CLLocationCoordinate2D?
    let eventDate: Date
    let eventTitle: String
}

// Make CLLocationCoordinate2D codable
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

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

    // MARK: - Location Extraction

    /// Extracts travel locations from calendar events using both structured location and title parsing
    func extractLocationsFromEvents(_ events: [EKEvent]) -> [EventLocation] {
        var locations: [EventLocation] = []

        for event in events {
            // Try structured location first (most reliable)
            if let structuredLocation = event.structuredLocation {
                let locationName = structuredLocation.title ?? "Unknown Location"
                let coordinates = structuredLocation.geoLocation?.coordinate

                locations.append(EventLocation(
                    locationName: locationName,
                    coordinates: coordinates,
                    eventDate: event.startDate,
                    eventTitle: event.title ?? "Untitled Event"
                ))

                logger.log("Found structured location '\(locationName)' for event '\(event.title ?? "")'", level: .info)
                continue
            }

            // Fall back to title parsing for travel keywords
            if let title = event.title, let parsedLocation = parseLocationFromTitle(title) {
                locations.append(EventLocation(
                    locationName: parsedLocation,
                    coordinates: nil,
                    eventDate: event.startDate,
                    eventTitle: title
                ))

                logger.log("Parsed location '\(parsedLocation)' from event title '\(title)'", level: .info)
            }
        }

        // Remove duplicate locations for the same date
        let uniqueLocations = removeDuplicateLocations(locations)
        logger.log("Extracted \(uniqueLocations.count) unique locations from \(events.count) events", level: .info)

        return uniqueLocations
    }

    /// Parses travel location from event title using common patterns
    private func parseLocationFromTitle(_ title: String) -> String? {
        let lowercased = title.lowercased()

        // Common travel patterns
        let patterns = [
            "flight to ",
            "flying to ",
            "trip to ",
            "travel to ",
            "meeting in ",
            "conference in ",
            "visiting ",
            " in ",
            " @ "
        ]

        for pattern in patterns {
            if let range = lowercased.range(of: pattern) {
                let afterPattern = String(title[range.upperBound...])
                // Extract location (up to comma, dash, or end)
                let components = afterPattern.components(separatedBy: CharacterSet(charactersIn: ",-–—"))
                if let location = components.first?.trimmingCharacters(in: .whitespaces),
                   !location.isEmpty {
                    return location
                }
            }
        }

        return nil
    }

    /// Removes duplicate locations for the same date
    private func removeDuplicateLocations(_ locations: [EventLocation]) -> [EventLocation] {
        var seen = Set<String>()
        var unique: [EventLocation] = []

        for location in locations {
            let calendar = Calendar.current
            let dateKey = calendar.startOfDay(for: location.eventDate)
            let key = "\(location.locationName)-\(dateKey)"

            if !seen.contains(key) {
                seen.insert(key)
                unique.append(location)
            }
        }

        return unique
    }
}