import Foundation
import WeatherKit
import CoreLocation

@available(iOS 16.0, *)
class WeatherService {
    static let shared = WeatherService()
    private let service = WeatherKit.WeatherService.shared
    private let logger = DebugLogger.shared
    
    private init() {}
    
    func weather(for location: CLLocation) async throws -> Weather {
        return try await service.weather(for: location)
    }
    
    func getTomorrowForecast(for location: CLLocation) async throws -> DayWeather? {
        let weather = try await service.weather(for: location)
        
        // Get tomorrow's date
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)
        
        // Find tomorrow's daily forecast
        return weather.dailyForecast.forecast.first { dayWeather in
            calendar.isDate(dayWeather.date, inSameDayAs: startOfTomorrow)
        }
    }
    
    func getTomorrowForecastDescription(for location: CLLocation) async -> String? {
        do {
            guard let tomorrowForecast = try await getTomorrowForecast(for: location) else {
                return nil
            }
            
            let highTemp = Int(tomorrowForecast.highTemperature.converted(to: .fahrenheit).value)
            let lowTemp = Int(tomorrowForecast.lowTemperature.converted(to: .fahrenheit).value)
            let condition = tomorrowForecast.condition.description
            
            return "High \(highTemp)°, Low \(lowTemp)°, \(condition)"
        } catch {
            logger.logError(error, context: "Failed to get tomorrow's forecast")
            return nil
        }
    }
    
    func getForecast(for location: CLLocation, date: Date) async throws -> DayWeather? {
        let weather = try await service.weather(for: location)

        // Find the forecast for the specific date
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        return weather.dailyForecast.forecast.first { dayWeather in
            calendar.isDate(dayWeather.date, inSameDayAs: targetDate)
        }
    }

    // MARK: - Multi-Location Forecasting

    /// Fetches weather forecasts for multiple locations with notable condition detection
    func getMultiLocationForecasts(
        eventLocations: [(name: String, location: CLLocation, date: Date)],
        currentLocation: CLLocation?,
        currentLocationName: String
    ) async -> EnhancedWeatherContext? {
        var currentForecast: [LocationForecast] = []
        var travelForecasts: [LocationForecast] = []
        var notableConditions: [NotableWeather] = []

        // Fetch current location forecast (3-4 days)
        if let currentLoc = currentLocation {
            do {
                let weather = try await self.weather(for: currentLoc)
                let forecasts = weather.dailyForecast.forecast.prefix(4)

                for (index, dayWeather) in forecasts.enumerated() {
                    let forecast = buildLocationForecast(
                        from: dayWeather,
                        locationName: currentLocationName
                    )
                    currentForecast.append(forecast)

                    // Detect notable conditions
                    let notable = detectNotableConditions(
                        forecast: dayWeather,
                        previousForecast: index > 0 ? forecasts[forecasts.index(forecasts.startIndex, offsetBy: index - 1)] : nil,
                        locationName: currentLocationName
                    )
                    notableConditions.append(contentsOf: notable)
                }

                logger.log("Fetched \(currentForecast.count)-day forecast for current location", level: .info)
            } catch {
                logger.logError(error, context: "Failed to fetch current location forecast")
            }
        }

        // Fetch travel destination forecasts in parallel
        await withTaskGroup(of: (String, LocationForecast, [NotableWeather])?.self) { group in
            for (locationName, location, eventDate) in eventLocations {
                group.addTask {
                    do {
                        guard let dayWeather = try await self.getForecast(for: location, date: eventDate) else {
                            self.logger.log("No forecast available for \(locationName)", level: .warning)
                            return nil
                        }

                        let forecast = self.buildLocationForecast(
                            from: dayWeather,
                            locationName: locationName
                        )

                        let notable = self.detectNotableConditions(
                            forecast: dayWeather,
                            previousForecast: nil,
                            locationName: locationName
                        )

                        self.logger.log("Fetched forecast for travel destination: \(locationName)", level: .info)
                        return (locationName, forecast, notable)
                    } catch {
                        self.logger.logError(error, context: "Failed to fetch forecast for \(locationName)")
                        return nil
                    }
                }
            }

            for await result in group {
                if let (_, forecast, notable) = result {
                    travelForecasts.append(forecast)
                    notableConditions.append(contentsOf: notable)
                }
            }
        }

        // Only return enhanced context if we have at least current forecast
        guard !currentForecast.isEmpty else {
            logger.log("No forecasts available for enhanced weather context", level: .warning)
            return nil
        }

        return EnhancedWeatherContext(
            currentLocation: currentLocationName,
            currentForecast: currentForecast,
            travelForecasts: travelForecasts,
            notableConditions: notableConditions
        )
    }

    // MARK: - Helper Methods

    private func buildLocationForecast(from dayWeather: DayWeather, locationName: String) -> LocationForecast {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return LocationForecast(
            locationName: locationName,
            date: dateFormatter.string(from: dayWeather.date),
            highTempF: Int(dayWeather.highTemperature.converted(to: .fahrenheit).value),
            lowTempF: Int(dayWeather.lowTemperature.converted(to: .fahrenheit).value),
            condition: dayWeather.condition.description,
            precipitationChance: Int(dayWeather.precipitationChance * 100),
            hasAlert: false  // TODO: Implement alert detection if WeatherKit provides it
        )
    }

    /// Detects notable weather conditions worth mentioning
    private func detectNotableConditions(
        forecast: DayWeather,
        previousForecast: DayWeather?,
        locationName: String
    ) -> [NotableWeather] {
        var notable: [NotableWeather] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: forecast.date)

        let highTempF = forecast.highTemperature.converted(to: .fahrenheit).value
        let lowTempF = forecast.lowTemperature.converted(to: .fahrenheit).value
        let precipChance = forecast.precipitationChance

        // Check for high precipitation (>30%)
        if precipChance > 0.3 {
            let precipPercent = Int(precipChance * 100)
            notable.append(NotableWeather(
                date: dateString,
                location: locationName,
                reason: "high_precipitation",
                description: "Rain likely (\(precipPercent)% chance)"
            ))
        }

        // Check for extreme heat (>85°F)
        if highTempF > 85 {
            notable.append(NotableWeather(
                date: dateString,
                location: locationName,
                reason: "extreme_heat",
                description: "High of \(Int(highTempF))°F"
            ))
        }

        // Check for freezing temperatures (<32°F)
        if lowTempF < 32 {
            notable.append(NotableWeather(
                date: dateString,
                location: locationName,
                reason: "extreme_cold",
                description: "Freezing temps, low of \(Int(lowTempF))°F"
            ))
        }

        // Check for temperature swings (>20°F day-to-day)
        if let previousForecast = previousForecast {
            let previousHighF = previousForecast.highTemperature.converted(to: .fahrenheit).value
            let tempSwing = abs(highTempF - previousHighF)

            if tempSwing > 20 {
                notable.append(NotableWeather(
                    date: dateString,
                    location: locationName,
                    reason: "temp_swing",
                    description: "\(Int(tempSwing))° temperature change from previous day"
                ))
            }
        }

        return notable
    }
}