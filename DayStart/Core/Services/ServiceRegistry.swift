import Foundation
import SwiftUI
import Combine

/// Centralized lazy loading system for all services
/// Only loads services when actually needed, dramatically improving startup time
@MainActor
class ServiceRegistry: ObservableObject {
    static let shared = ServiceRegistry()
    
    private let logger = DebugLogger.shared
    
    // MARK: - Lazy-loaded services
    
    // TIER 2: Core UI Services (Load when UI appears)
    private var _audioPlayerManager: AudioPlayerManager?
    private var _audioCache: AudioCache?
    private var _hapticManager: HapticManager?
    private var _formatterCache: FormatterCache?
    
    // TIER 3: User Feature Services (Load when features accessed)
    private var _notificationScheduler: NotificationScheduler?
    private var _streakManager: StreakManager?
    
    // TIER 4: Content Generation Services (Load when DayStart content needed)
    private var _supabaseClient: SupabaseClient?
    private var _audioDownloader: AudioDownloader?
    private var _audioPrefetchManager: AudioPrefetchManager?
    private var _snapshotBuilder: SnapshotBuilder?
    private var _snapshotUpdateManager: SnapshotUpdateManager?
    private var _stockValidationService: StockValidationService?
    
    // TIER 5: Platform Integration Services (Load only with permissions/features enabled)
    private var _locationManager: LocationManager?
    private var _weatherService: WeatherService?
    private var _calendarManager: CalendarManager?
    
    private init() {
        logger.log("🏗️ ServiceRegistry initialized - all services will load on-demand", level: .info)
    }
    
    // MARK: - TIER 2: Core UI Services
    
    var audioPlayerManager: AudioPlayerManager {
        if _audioPlayerManager == nil {
            logger.log("🎵 Loading AudioPlayerManager on-demand", level: .info)
            _audioPlayerManager = AudioPlayerManager.shared
        }
        return _audioPlayerManager!
    }
    
    var audioCache: AudioCache {
        if _audioCache == nil {
            logger.log("💾 Loading AudioCache on-demand", level: .info)
            _audioCache = AudioCache.shared
        }
        return _audioCache!
    }
    
    var hapticManager: HapticManager {
        if _hapticManager == nil {
            logger.log("📳 Loading HapticManager on-demand", level: .info)
            _hapticManager = HapticManager.shared
        }
        return _hapticManager!
    }
    
    var formatterCache: FormatterCache {
        if _formatterCache == nil {
            logger.log("📅 Loading FormatterCache on-demand", level: .info)
            _formatterCache = FormatterCache.shared
        }
        return _formatterCache!
    }
    
    // MARK: - TIER 3: User Feature Services
    
    var notificationScheduler: NotificationScheduler {
        if _notificationScheduler == nil {
            logger.log("📱 Loading NotificationScheduler on-demand", level: .info)
            _notificationScheduler = NotificationScheduler.shared
        }
        return _notificationScheduler!
    }
    
    var streakManager: StreakManager {
        if _streakManager == nil {
            logger.log("🔥 Loading StreakManager on-demand", level: .info)
            _streakManager = StreakManager.shared
        }
        return _streakManager!
    }
    
    // MARK: - TIER 4: Content Generation Services
    
    var supabaseClient: SupabaseClient {
        if _supabaseClient == nil {
            logger.log("☁️ Loading SupabaseClient on-demand", level: .info)
            _supabaseClient = SupabaseClient.shared
        }
        return _supabaseClient!
    }
    
    var audioDownloader: AudioDownloader {
        if _audioDownloader == nil {
            logger.log("⬇️ Loading AudioDownloader on-demand", level: .info)
            _audioDownloader = AudioDownloader.shared
        }
        return _audioDownloader!
    }
    
    var audioPrefetchManager: AudioPrefetchManager {
        if _audioPrefetchManager == nil {
            logger.log("🔄 Loading AudioPrefetchManager on-demand", level: .info)
            _audioPrefetchManager = AudioPrefetchManager.shared
        }
        return _audioPrefetchManager!
    }
    
    var snapshotBuilder: SnapshotBuilder {
        if _snapshotBuilder == nil {
            logger.log("📸 Loading SnapshotBuilder on-demand", level: .info)
            _snapshotBuilder = SnapshotBuilder.shared
        }
        return _snapshotBuilder!
    }
    
    var snapshotUpdateManager: SnapshotUpdateManager {
        if _snapshotUpdateManager == nil {
            logger.log("🔄 Loading SnapshotUpdateManager on-demand", level: .info)
            _snapshotUpdateManager = SnapshotUpdateManager.shared
        }
        return _snapshotUpdateManager!
    }
    
    var stockValidationService: StockValidationService {
        if _stockValidationService == nil {
            logger.log("📈 Loading StockValidationService on-demand", level: .info)
            _stockValidationService = StockValidationService.shared
        }
        return _stockValidationService!
    }
    
    // MARK: - TIER 5: Platform Integration Services (Conditional Loading)
    
    /// Location Manager - Only loads if user has enabled location features
    var locationManager: LocationManager? {
        // Don't load if user hasn't enabled weather/location features
        guard UserPreferences.shared.settings.includeWeather else {
            logger.log("📍 LocationManager not loaded - weather disabled", level: .debug)
            return nil
        }
        
        if _locationManager == nil {
            logger.log("📍 Loading LocationManager on-demand (weather enabled)", level: .info)
            _locationManager = LocationManager()
        }
        return _locationManager
    }
    
    /// Weather Service - Only loads if location is available
    var weatherService: WeatherService? {
        guard locationManager != nil else {
            logger.log("🌤️ WeatherService not loaded - location unavailable", level: .debug)
            return nil
        }
        
        if _weatherService == nil {
            logger.log("🌤️ Loading WeatherService on-demand", level: .info)
            _weatherService = WeatherService.shared
        }
        return _weatherService
    }
    
    /// Calendar Manager - Only loads if user has enabled calendar features
    var calendarManager: CalendarManager? {
        // Don't load if user hasn't enabled calendar integration
        guard UserPreferences.shared.settings.includeCalendar else {
            logger.log("📅 CalendarManager not loaded - calendar disabled", level: .debug)
            return nil
        }
        
        if _calendarManager == nil {
            logger.log("📅 Loading CalendarManager on-demand (calendar enabled)", level: .info)
            _calendarManager = CalendarManager.shared
        }
        return _calendarManager
    }
    
    // MARK: - Background Task Management
    
    /// Register background tasks only when needed (user has active schedule)
    func registerBackgroundTasksIfNeeded() {
        guard !UserPreferences.shared.schedule.repeatDays.isEmpty else {
            logger.log("🔄 Background tasks not registered - no active schedule", level: .debug)
            return
        }
        
        Task.detached(priority: .background) {
            // Load AudioPrefetchManager in background only when needed
            await MainActor.run {
                _ = ServiceRegistry.shared.audioPrefetchManager
            }
            await DebugLogger.shared.log("✅ Background tasks registered on-demand", level: .info)
        }
    }
    
    // MARK: - Memory Management
    
    /// Release services that aren't currently needed (for memory pressure)
    func releaseUnusedServices() {
        logger.log("🧹 Checking for unused services to release", level: .debug)
        
        // Release location/weather if disabled
        if !UserPreferences.shared.settings.includeWeather {
            _locationManager = nil
            _weatherService = nil
            logger.log("📍 Released location services - weather disabled", level: .debug)
        }
        
        // Release calendar if disabled
        if !UserPreferences.shared.settings.includeCalendar {
            _calendarManager = nil
            logger.log("📅 Released calendar services - calendar disabled", level: .debug)
        }
        
        // Release content generation services if no active schedule
        if UserPreferences.shared.schedule.repeatDays.isEmpty {
            _audioPrefetchManager = nil
            _snapshotBuilder = nil
            _snapshotUpdateManager = nil
            logger.log("☁️ Released content generation services - no active schedule", level: .debug)
        }
    }
    
    // MARK: - Service Status
    
    var loadedServices: [String] {
        var services: [String] = []
        if _audioPlayerManager != nil { services.append("AudioPlayerManager") }
        if _audioCache != nil { services.append("AudioCache") }
        if _hapticManager != nil { services.append("HapticManager") }
        if _formatterCache != nil { services.append("FormatterCache") }
        if _notificationScheduler != nil { services.append("NotificationScheduler") }
        if _streakManager != nil { services.append("StreakManager") }
        if _supabaseClient != nil { services.append("SupabaseClient") }
        if _audioDownloader != nil { services.append("AudioDownloader") }
        if _audioPrefetchManager != nil { services.append("AudioPrefetchManager") }
        if _snapshotBuilder != nil { services.append("SnapshotBuilder") }
        if _snapshotUpdateManager != nil { services.append("SnapshotUpdateManager") }
        if _stockValidationService != nil { services.append("StockValidationService") }
        if _locationManager != nil { services.append("LocationManager") }
        if _weatherService != nil { services.append("WeatherService") }
        if _calendarManager != nil { services.append("CalendarManager") }
        return services
    }
    
    func logServiceStatus() {
        logger.log("📊 Loaded services: \(loadedServices.joined(separator: ", "))", level: .info)
    }
}
