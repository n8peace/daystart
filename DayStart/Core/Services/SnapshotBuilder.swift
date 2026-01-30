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
        let weather: WeatherData?  // Simple weather (backwards compat)
        let calendar: [String]?
        let enhancedWeather: EnhancedWeatherContext?  // NEW: Enhanced multi-location weather
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
        if #available(iOS 16.0, *), let loc = await LocationManager.shared.getCurrentLocation() {
            do {
                // Try to get forecast for the specific date first
                if let dayForecast = try await WeatherService.shared.getForecast(for: loc, date: date) {
                    let highTempF = Int(dayForecast.highTemperature.converted(to: .fahrenheit).value)
                    let lowTempF = Int(dayForecast.lowTemperature.converted(to: .fahrenheit).value)
                    let conditionDesc = dayForecast.condition.description
                    let symbolName = dayForecast.symbolName
                    let precipChance = Int((dayForecast.precipitationChance * 100).rounded())
                    
                    // Format the forecast date as YYYY-MM-DD
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    dateFormatter.timeZone = TimeZone.current
                    let forecastDateString = dateFormatter.string(from: date)
                    
                    // Include current temp for today, nil for future dates
                    let calendar = Calendar.current
                    var currentTempF: Int? = nil
                    if calendar.isDateInToday(date) {
                        if let weather = await LocationManager.shared.getCurrentWeather() {
                            currentTempF = Int(weather.currentWeather.temperature.converted(to: .fahrenheit).value)
                        }
                    }
                    
                    weatherData = WeatherData(
                        temperatureF: currentTempF,
                        condition: conditionDesc,
                        symbol: symbolName,
                        updated_at: ISO8601DateFormatter().string(from: Date()),
                        highTemperatureF: highTempF,
                        lowTemperatureF: lowTempF,
                        precipitationChance: precipChance,
                        forecastDate: forecastDateString
                    )
                    
                    logger.log("Weather forecast for \(forecastDateString): High \(highTempF)°, Low \(lowTempF)°, \(conditionDesc)", level: .info)
                }
            } catch {
                logger.logError(error, context: "Failed to get weather forecast for date \(date)")
                
                // Fallback: If it's today and forecast failed, try current weather
                let calendar = Calendar.current
                if calendar.isDateInToday(date) {
                    if let weather = await LocationManager.shared.getCurrentWeather() {
                        let tempF = Int(weather.currentWeather.temperature.converted(to: .fahrenheit).value)
                        let conditionDesc = weather.currentWeather.condition.description
                        let symbolName = weather.currentWeather.symbolName
                        
                        // Try to get today's forecast data as backup
                        var highTempF: Int? = nil
                        var lowTempF: Int? = nil
                        var precipChance: Int? = nil
                        
                        if let todayForecast = weather.dailyForecast.forecast.first(where: { dayWeather in
                            calendar.isDate(dayWeather.date, inSameDayAs: date)
                        }) {
                            highTempF = Int(todayForecast.highTemperature.converted(to: .fahrenheit).value)
                            lowTempF = Int(todayForecast.lowTemperature.converted(to: .fahrenheit).value)
                            precipChance = Int((todayForecast.precipitationChance * 100).rounded())
                        }
                        
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        dateFormatter.timeZone = TimeZone.current
                        let forecastDateString = dateFormatter.string(from: date)
                        
                        weatherData = WeatherData(
                            temperatureF: tempF,
                            condition: conditionDesc,
                            symbol: symbolName,
                            updated_at: ISO8601DateFormatter().string(from: Date()),
                            highTemperatureF: highTempF,
                            lowTemperatureF: lowTempF,
                            precipitationChance: precipChance,
                            forecastDate: forecastDateString
                        )
                        
                        logger.log("Weather fallback for today: Current \(tempF)°, High \(highTempF ?? 0)°, \(conditionDesc)", level: .info)
                    }
                }
                // For future dates, if forecast fails, we just continue with no weather data
            }
        }
        
        // Calendar - fetch upcoming events once (includes today + next 10 days)
        // This single fetch will be used for both calendar formatting and travel location extraction
        var upcomingEvents: [EKEvent] = []
        if CalendarManager.shared.hasCalendarAccess() {
            upcomingEvents = CalendarManager.shared.getUpcomingEvents(days: 10)

            // Filter for today's events for calendar lines
            let calendar = Calendar.current
            let todayEvents = upcomingEvents.filter { event in
                calendar.isDate(event.startDate, inSameDayAs: date)
            }

            let lines = CalendarManager.shared.formatEventsForDayStart(todayEvents)
            calendarLines = lines
        }

        // Enhanced Weather - multi-location forecasts with travel detection
        // Apply 30-second timeout to prevent indefinite hangs
        var enhancedWeather: EnhancedWeatherContext? = nil
        if #available(iOS 16.0, *), let currentLoc = await LocationManager.shared.getCurrentLocation() {
            enhancedWeather = try? await LocationManager.shared.withTimeout(seconds: 30) {
                // Extract travel locations from already-fetched calendar events
                let eventLocations = CalendarManager.shared.extractLocationsFromEvents(upcomingEvents)

                // Rate limiting: Limit to 5 travel destinations to prevent API throttling
                let limitedLocations = Array(eventLocations.prefix(5))
                if eventLocations.count > 5 {
                    self.logger.log("⚠️ Limited to 5 travel destinations (found \(eventLocations.count))", level: .info)
                }

                // Parallel geocoding for locations without coordinates
                var locationsWithCoords: [(name: String, location: CLLocation, date: Date)] = []
                await withTaskGroup(of: (String, CLLocation?, Date).self) { group in
                    for eventLoc in limitedLocations {
                        group.addTask {
                            if let coords = eventLoc.coordinates {
                                // Use existing coordinates from structured location
                                let location = CLLocation(latitude: coords.latitude, longitude: coords.longitude)
                                return (eventLoc.locationName, location, eventLoc.eventDate)
                            } else {
                                // Geocode location name (in parallel)
                                let geocoded = await LocationManager.shared.geocodeLocation(eventLoc.locationName)
                                return (eventLoc.locationName, geocoded, eventLoc.eventDate)
                            }
                        }
                    }

                    for await result in group {
                        if let location = result.1 {
                            locationsWithCoords.append((result.0, location, result.2))
                        } else {
                            self.logger.log("❌ Failed to geocode location: '\(result.0)' for date \(result.2)", level: .warning)
                        }
                    }
                }

                self.logger.log("Geocoded \(locationsWithCoords.count)/\(limitedLocations.count) travel locations", level: .info)

                // Build current location name
                let currentLocationName = [locData?.neighborhood, locData?.city, locData?.state]
                    .compactMap { $0 }
                    .first ?? "Current Location"

                // Fetch multi-location forecasts with notable condition detection
                let result = await WeatherService.shared.getMultiLocationForecasts(
                    eventLocations: locationsWithCoords,
                    currentLocation: currentLoc,
                    currentLocationName: currentLocationName
                )

                if let enhanced = result {
                    self.logger.log("Enhanced weather built: \(enhanced.currentForecast.count) current forecasts, \(enhanced.travelForecasts.count) travel forecasts, \(enhanced.notableConditions.count) notable conditions", level: .info)
                }

                return result
            }

            if enhancedWeather == nil {
                logger.log("⏱️ Enhanced weather building timed out or failed", level: .warning)

                // Track failure rate for monitoring
                if !upcomingEvents.isEmpty {
                    let eventLocations = CalendarManager.shared.extractLocationsFromEvents(upcomingEvents)
                    if !eventLocations.isEmpty {
                        logger.log("⚠️ Enhanced weather unavailable despite \(eventLocations.count) travel event(s) detected", level: .warning)
                    }
                }
            }
        }

        logger.log("Snapshot built for \(date): loc=\(locData != nil), weather=\(weatherData != nil), calendar=\((calendarLines?.count ?? 0)) items, enhanced=\(enhancedWeather != nil)", level: .info)
        return Snapshot(location: locData, weather: weatherData, calendar: calendarLines, enhancedWeather: enhancedWeather)
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


