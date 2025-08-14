import Foundation
import CoreLocation
import EventKit
import WeatherKit

@MainActor
class SnapshotBuilder {
    static let shared = SnapshotBuilder()
    private let logger = DebugLogger.shared
    private init() {}
    
    struct Snapshot {
        let location: LocationData?
        let weather: WeatherData?
        let calendar: [String]?
    }
    
    func buildSnapshot() async -> Snapshot {
        var locData: LocationData? = nil
        var weatherData: WeatherData? = nil
        var calendarLines: [String]? = nil
        
        // Location (best-effort)
        if LocationManager.shared.hasLocationAccess(), let loc = await LocationManager.shared.getCurrentLocation() {
            locData = LocationData(
                city: nil, // reverse geocode optional future enhancement
                state: nil,
                country: nil,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
        }
        
        // Weather (requires iOS 16 + location)
        if #available(iOS 16.0, *), let _ = locData {
            if let weather = await LocationManager.shared.getCurrentWeather() {
                let tempF = Int(weather.currentWeather.temperature.converted(to: .fahrenheit).value)
                let conditionDesc = weather.currentWeather.condition.description
                let symbolName = weather.currentWeather.symbolName
                weatherData = WeatherData(
                    temperatureF: tempF,
                    condition: conditionDesc,
                    symbol: symbolName,
                    updated_at: ISO8601DateFormatter().string(from: Date())
                )
            }
        }
        
        // Calendar (today only, formatted lines)
        if CalendarManager.shared.hasCalendarAccess() {
            let events = CalendarManager.shared.getTodaysEvents()
            let lines = CalendarManager.shared.formatEventsForDayStart(events)
            calendarLines = lines
        }
        
        logger.log("Snapshot built: loc=\(locData != nil), weather=\(weatherData != nil), calendar=\((calendarLines?.count ?? 0)) items", level: .info)
        return Snapshot(location: locData, weather: weatherData, calendar: calendarLines)
    }
}


