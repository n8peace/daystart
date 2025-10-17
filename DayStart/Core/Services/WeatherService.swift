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
}