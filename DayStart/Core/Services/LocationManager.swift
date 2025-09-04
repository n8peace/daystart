import CoreLocation
import WeatherKit
import Foundation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    private let logger = DebugLogger.shared
    private let weatherService = WeatherService.shared
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentWeather: Weather?
    
    private var locationContinuation: CheckedContinuation<Bool, Never>?
    
    // Weather cache
    private var weatherCache: (weather: Weather, timestamp: Date)?
    private var forecastCache: (forecast: String, timestamp: Date)?
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced // Privacy-friendly
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Permission Management
    
    func requestLocationPermission() async -> Bool {
        guard authorizationStatus == .notDetermined else {
            return hasLocationAccess()
        }
        
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    func hasLocationAccess() -> Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Location Services
    
    func getCurrentLocation() async -> CLLocation? {
        guard hasLocationAccess() else {
            logger.log("Cannot get location: permission not granted", level: .warning)
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            if let location = currentLocation, location.timestamp.timeIntervalSinceNow > -300 {
                // Use cached location if it's less than 5 minutes old
                continuation.resume(returning: location)
                return
            }
            
            locationManager.requestLocation()
            
            // Store continuation for delegate callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                continuation.resume(returning: self.currentLocation)
            }
        }
    }
    
    // MARK: - Weather Services
    
    @available(iOS 16.0, *)
    func getCurrentWeather() async -> Weather? {
        // Check cache first
        if let cached = weatherCache,
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            logger.log("Using cached weather data", level: .info)
            return cached.weather
        }
        
        guard let location = await getCurrentLocation() else {
            logger.log("Cannot get weather: location unavailable", level: .warning)
            return nil
        }
        
        do {
            let weather = try await weatherService.weather(for: location)
            
            // Update cache
            weatherCache = (weather, Date())
            
            await MainActor.run {
                self.currentWeather = weather
            }
            logger.log("Retrieved weather for location: \(location.coordinate)", level: .info)
            return weather
        } catch {
            logger.logError(error, context: "Failed to fetch weather")
            return nil
        }
    }
    
    func getWeatherDescription() async -> String {
        if #available(iOS 16.0, *) {
            guard let weather = await getCurrentWeather() else {
                return "Weather unavailable"
            }
            
            let temp = Int(weather.currentWeather.temperature.value)
            let condition = weather.currentWeather.condition.description
            let symbol = weather.currentWeather.symbolName
            
            return "It's currently \(temp)° and \(condition.lowercased())"
        } else {
            // Fallback for iOS 15 and below
            return "Weather requires iOS 16 or later"
        }
    }
    
    @available(iOS 16.0, *)
    func getTomorrowForecast() async -> String? {
        // Check cache first
        if let cached = forecastCache,
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            logger.log("Using cached forecast data", level: .info)
            return cached.forecast
        }
        
        guard hasLocationAccess() else { return nil }
        guard let location = await getCurrentLocation() else { return nil }
        
        let forecast = await weatherService.getTomorrowForecastDescription(for: location)
        
        // Update cache if we got a forecast
        if let forecast = forecast {
            forecastCache = (forecast, Date())
        }
        
        return forecast
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.logError(error, context: "Location manager failed")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        logger.log("Location authorization changed: \(status.rawValue)", level: .info)
        
        // Resume any pending permission request
        if let continuation = locationContinuation {
            locationContinuation = nil
            let granted = hasLocationAccess()
            continuation.resume(returning: granted)
        }
    }
}

// MARK: - Snapshot DTOs used for Supabase job context

struct LocationData: Codable {
    let city: String?
    let state: String?
    let country: String?
    let neighborhood: String? // subLocality - e.g., "Mar Vista"
    // Removed latitude/longitude for privacy compliance
}

struct WeatherData: Codable {
    let temperatureF: Int?
    let condition: String?
    let symbol: String?
    let updated_at: String?
    // Daily forecast data
    let highTemperatureF: Int?
    let lowTemperatureF: Int?
    let precipitationChance: Int? // Percentage (0-100)
}

// MARK: - CLAuthorizationStatus Extension

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Authorized Always"
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        @unknown default:
            return "Unknown"
        }
    }
}