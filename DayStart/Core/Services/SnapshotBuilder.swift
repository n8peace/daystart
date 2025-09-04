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
    
    func buildSnapshot(for date: Date = Date()) async -> Snapshot {
        var locData: LocationData? = nil
        var weatherData: WeatherData? = nil
        var calendarLines: [String]? = nil
        
        // Location (best-effort)
        if LocationManager.shared.hasLocationAccess(), let loc = await LocationManager.shared.getCurrentLocation() {
            // Perform reverse geocoding to get city, state, neighborhood
            let geocoder = CLGeocoder()
            var city: String? = nil
            var state: String? = nil
            var country: String? = nil
            var neighborhood: String? = nil
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(loc)
                if let placemark = placemarks.first {
                    city = placemark.locality
                    state = placemark.administrativeArea
                    country = placemark.country
                    neighborhood = placemark.subLocality
                    
                    logger.log("Reverse geocoded: \(neighborhood ?? "nil") in \(city ?? "nil"), \(state ?? "nil")", level: .info)
                }
            } catch {
                logger.logError(error, context: "Reverse geocoding failed")
            }
            
            locData = LocationData(
                city: city,
                state: state,
                country: country,
                neighborhood: neighborhood
            )
        }
        
        // Weather (requires iOS 16 + location)
        if #available(iOS 16.0, *), let _ = locData {
            if let weather = await LocationManager.shared.getCurrentWeather() {
                let tempF = Int(weather.currentWeather.temperature.converted(to: .fahrenheit).value)
                let conditionDesc = weather.currentWeather.condition.description
                let symbolName = weather.currentWeather.symbolName
                
                // Get today's forecast data
                var highTempF: Int? = nil
                var lowTempF: Int? = nil
                var precipChance: Int? = nil
                
                // Find today's daily forecast
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: date)
                if let todayForecast = weather.dailyForecast.forecast.first(where: { dayWeather in
                    calendar.isDate(dayWeather.date, inSameDayAs: today)
                }) {
                    highTempF = Int(todayForecast.highTemperature.converted(to: .fahrenheit).value)
                    lowTempF = Int(todayForecast.lowTemperature.converted(to: .fahrenheit).value)
                    precipChance = Int((todayForecast.precipitationChance * 100).rounded())
                }
                
                weatherData = WeatherData(
                    temperatureF: tempF,
                    condition: conditionDesc,
                    symbol: symbolName,
                    updated_at: ISO8601DateFormatter().string(from: Date()),
                    highTemperatureF: highTempF,
                    lowTemperatureF: lowTempF,
                    precipitationChance: precipChance
                )
            }
        }
        
        // Calendar - get events for the specific date
        if CalendarManager.shared.hasCalendarAccess() {
            let events = getEventsForDate(date)
            let lines = CalendarManager.shared.formatEventsForDayStart(events)
            calendarLines = lines
        }
        
        logger.log("Snapshot built for \(date): loc=\(locData != nil), weather=\(weatherData != nil), calendar=\((calendarLines?.count ?? 0)) items", level: .info)
        return Snapshot(location: locData, weather: weatherData, calendar: calendarLines)
    }
    
    private func getEventsForDate(_ date: Date) -> [EKEvent] {
        let calendarManager = CalendarManager.shared
        let calendar = Calendar.current
        
        // If it's today, use the existing method
        if calendar.isDateInToday(date) {
            return calendarManager.getTodaysEvents()
        }
        
        // For future dates, use the new method
        return calendarManager.getEventsForDate(date)
    }
}


