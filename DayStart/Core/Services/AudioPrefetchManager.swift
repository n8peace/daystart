import Foundation
import BackgroundTasks
import AVFoundation
import UIKit

/// AudioPrefetchManager with conditional background task registration
/// Only registers background tasks when user has an active schedule
@MainActor
class AudioPrefetchManager {
    static let shared = AudioPrefetchManager()
    
    private let taskIdentifier = "ai.bananaintelligence.DayStart.audio-prefetch"
    private lazy var logger = DebugLogger.shared // Lazy logger
    
    // Background task registration state
    private var isBackgroundTaskRegistered = false
    
    // PHASE 4: AVPlayerItem prefetching for instant audio start
    private var preloadedPlayerItems: [String: (item: AVPlayerItem, created: Date)] = [:]
    private let maxCacheAge: TimeInterval = 3600 // 1 hour TTL
    private let maxCacheSize = 5 // Limit memory usage
    
    private init() {
        // LIGHTWEIGHT: Only memory pressure observer (no background task registration)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        logger.log("🔄 AudioPrefetchManager initialized - background tasks deferred", level: .info)
    }
    
    @objc private func handleMemoryWarning() {
        logger.log("🚨 Memory warning received, clearing player item cache", level: .warning)
        clearPlayerItemCache()
    }
    
    // MARK: - Conditional Background Task Registration
    
    /// Register background tasks only when user has an active schedule
    func registerBackgroundTasksIfNeeded() {
        // Don't register if already registered
        guard !isBackgroundTaskRegistered else {
            logger.log("🔄 Background tasks already registered", level: .debug)
            return
        }
        
        // Don't register if user doesn't have an active schedule
        guard !UserPreferences.shared.schedule.repeatDays.isEmpty else {
            logger.log("🔄 Background tasks not registered - no active schedule", level: .debug)
            return
        }
        
        // DEFERRED: Register background tasks only when actually needed
        Task.detached(priority: .background) { [weak self] in
            await self?.performBackgroundTaskRegistration()
        }
    }
    
    private func performBackgroundTaskRegistration() async {
        await MainActor.run {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
                guard let self = self else { return }
                self.handleAudioPrefetch(task: task as! BGProcessingTask)
            }
            
            isBackgroundTaskRegistered = true
            logger.log("✅ Background tasks registered on-demand", level: .info)
        }
    }
    
    /// Force registration (for migration/legacy support)
    func registerBackgroundTasks() {
        isBackgroundTaskRegistered = false // Reset flag
        registerBackgroundTasksIfNeeded()
    }
    
    func scheduleAudioPrefetch(for scheduledTime: Date) {
        // Only schedule if background tasks are registered
        guard isBackgroundTaskRegistered else {
            logger.log("🔄 Cannot schedule audio prefetch - background tasks not registered", level: .debug)
            return
        }
        
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = scheduledTime.addingTimeInterval(-2 * 3600) // 2 hours before
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.log("📅 Scheduled BGTask for \(scheduledTime)", level: .info)
        } catch {
            logger.logError(error, context: "Failed to schedule background task")
        }
    }
    
    private func handleAudioPrefetch(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            let success = await precreateJobsWithSnapshotIfNeeded()
            task.setTaskCompleted(success: success)
        }
    }
    
    // MARK: - Foreground Check (Conditional Service Loading)
    
    func checkForUpcomingDayStarts() async {
        // Don't check if user doesn't have an active schedule
        guard !UserPreferences.shared.schedule.repeatDays.isEmpty else {
            logger.log("🔄 Skipping upcoming DayStarts check - no active schedule", level: .debug)
            return
        }
        
        let upcomingSchedules = getSchedulesWithinHours(2)
        
        guard !upcomingSchedules.isEmpty else {
            logger.log("📅 No upcoming DayStarts within 2 hours", level: .debug)
            return
        }
        
        logger.log("🔍 Checking \(upcomingSchedules.count) upcoming DayStarts for ready audio", level: .info)
        
        // Ensure background tasks are registered if we have upcoming schedules
        registerBackgroundTasksIfNeeded()
        
        for schedule in upcomingSchedules {
            _ = await checkAndDownloadAudio(for: schedule.date)
        }
    }
    
    private func checkAndDownloadAudio(for date: Date) async -> Bool {
        // LAZY: Only check cache if AudioCache is loaded
        if ServiceRegistry.shared.loadedServices.contains("AudioCache"),
           ServiceRegistry.shared.audioCache.hasAudio(for: date) {
            logger.log("📦 Audio already cached for \(date)", level: .debug)
            return true
        }
        
        // Perform network status check
        do {
            // LAZY: Load SupabaseClient only when needed
            let supabaseClient = ServiceRegistry.shared.supabaseClient
            let response = try await Task.detached(priority: .background) {
                try await supabaseClient.getAudioStatus(for: date)
            }.value
            
            if response.status == "ready", let audioUrl = response.audioUrl {
                logger.log("🎵 Audio ready for \(date), creating player item and downloading...", level: .info)
                
                // PHASE 4: Create and cache AVPlayerItem for instant handoff
                let playerItem = AVPlayerItem(url: audioUrl)
                let cacheKey = localDateString(from: date)
                addPlayerItemToCache(playerItem, forKey: cacheKey)
                
                // LAZY: Load AudioDownloader only when needed
                let audioDownloader = ServiceRegistry.shared.audioDownloader
                return await audioDownloader.download(from: audioUrl, for: date)
                
            } else if response.status == "not_found" {
                logger.log("📋 Audio not found for \(date), creating job with snapshot...", level: .info)
                
                // LAZY: Load SnapshotBuilder only when creating jobs
                let snapshot = await ServiceRegistry.shared.snapshotBuilder.buildSnapshot(for: date)
                
                // Create job
                _ = try? await Task.detached(priority: .background) {
                    try await supabaseClient.createJob(
                        for: date,
                        with: UserPreferences.shared.settings,
                        schedule: UserPreferences.shared.schedule,
                        locationData: snapshot.location,
                        weatherData: snapshot.weather,
                        calendarEvents: snapshot.calendar
                    )
                }.value
                return false
                
            } else {
                logger.log("⏳ Audio not ready for \(date), status: \(response.status)", level: .debug)
                return false
            }
        } catch {
            logger.logError(error, context: "Failed to check audio status for \(date)")
            return false
        }
    }
    
    private func precreateJobsWithSnapshotIfNeeded() async -> Bool {
        let upcomingSchedules = getSchedulesWithinHours(2)
        if upcomingSchedules.isEmpty { return true }
        
        var createdOrConfirmed = 0
        
        // LAZY: Load services only when background task actually runs
        let supabaseClient = ServiceRegistry.shared.supabaseClient
        let snapshotBuilder = ServiceRegistry.shared.snapshotBuilder
        
        for schedule in upcomingSchedules {
            let scheduledTime = schedule.scheduledTime
            do {
                // Check status
                let status = try await Task.detached(priority: .background) {
                    try await supabaseClient.getAudioStatus(for: scheduledTime)
                }.value
                
                if status.status == "ready" || status.status == "processing" {
                    continue
                }
                
                // Build snapshot for the local date of the scheduled time
                let localDate = Calendar.current.startOfDay(for: scheduledTime)
                let snapshot = await snapshotBuilder.buildSnapshot(for: localDate)
                
                // Create job
                _ = try? await Task.detached(priority: .background) {
                    try await supabaseClient.createJob(
                        for: scheduledTime,
                        with: UserPreferences.shared.settings,
                        schedule: UserPreferences.shared.schedule,
                        locationData: snapshot.location,
                        weatherData: snapshot.weather,
                        calendarEvents: snapshot.calendar
                    )
                }.value
                createdOrConfirmed += 1
                
            } catch {
                logger.logError(error, context: "BG precreate job failed for \(scheduledTime)")
            }
        }
        
        logger.log("✅ Background precreate completed: \(createdOrConfirmed)/\(upcomingSchedules.count) jobs ensured", level: .info)
        return createdOrConfirmed > 0
    }
    
    // MARK: - Helper Methods (Lightweight)
    
    private func getSchedulesWithinHours(_ hours: Int) -> [ScheduleInfo] {
        let userPreferences = UserPreferences.shared
        let schedule = userPreferences.schedule
        let calendar = Calendar.current
        let now = Date()
        let endTime = now.addingTimeInterval(TimeInterval(hours * 3600))
        
        var schedules: [ScheduleInfo] = []
        
        // Check each day within the time window
        for dayOffset in 0...2 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { continue }
            guard candidateDate <= endTime else { continue }
            
            // Check if this day is in the repeat schedule
            let weekday = calendar.component(.weekday, from: candidateDate)
            guard let weekDay = WeekDay(weekday: weekday), schedule.repeatDays.contains(weekDay) else { continue }
            
            // Skip tomorrow if skipTomorrow is true
            if schedule.skipTomorrow {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                if calendar.isDate(candidateDate, inSameDayAs: tomorrow) {
                    continue
                }
            }
            
            // Create the scheduled time for this date
            let timeComponents = calendar.dateComponents([.hour, .minute], from: schedule.time)
            var scheduledComponents = calendar.dateComponents([.year, .month, .day], from: candidateDate)
            scheduledComponents.hour = timeComponents.hour
            scheduledComponents.minute = timeComponents.minute
            
            if let scheduledTime = calendar.date(from: scheduledComponents),
               scheduledTime > now && scheduledTime <= endTime {
                schedules.append(ScheduleInfo(date: candidateDate, scheduledTime: scheduledTime))
                
                // Schedule background task only if registered
                if isBackgroundTaskRegistered {
                    scheduleAudioPrefetch(for: scheduledTime)
                }
            }
        }
        
        return schedules
    }
    
    // MARK: - Public Interface
    
    func prefetchAudioIfNeeded(for date: Date) async -> Bool {
        return await checkAndDownloadAudio(for: date)
    }
    
    func cancelAllBackgroundTasks() {
        guard isBackgroundTaskRegistered else {
            logger.log("🔄 No background tasks to cancel - not registered", level: .debug)
            return
        }
        
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        logger.log("❌ Cancelled all background audio prefetch tasks", level: .info)
    }
    
    // MARK: - AVPlayerItem Prefetching (Lightweight)
    
    private func addPlayerItemToCache(_ item: AVPlayerItem, forKey key: String) {
        purgeExpiredItems()
        if preloadedPlayerItems.count >= maxCacheSize {
            purgeOldestItem()
        }
        
        preloadedPlayerItems[key] = (item, Date())
        logger.log("🎵 Cached player item for \(key) (cache size: \(preloadedPlayerItems.count))", level: .info)
    }
    
    func getPreloadedPlayerItem(for date: Date) -> AVPlayerItem? {
        let cacheKey = localDateString(from: date)
        
        guard let cached = preloadedPlayerItems[cacheKey] else {
            return nil
        }
        
        // Check if item is still valid
        let age = Date().timeIntervalSince(cached.created)
        if age > maxCacheAge {
            preloadedPlayerItems.removeValue(forKey: cacheKey)
            return nil
        }
        
        logger.log("🚀 Using preloaded player item for \(cacheKey)", level: .info)
        return cached.item
    }
    
    private func purgeExpiredItems() {
        let now = Date()
        let expiredKeys = preloadedPlayerItems.compactMap { (key, value) in
            now.timeIntervalSince(value.created) > maxCacheAge ? key : nil
        }
        
        for key in expiredKeys {
            preloadedPlayerItems.removeValue(forKey: key)
        }
    }
    
    private func purgeOldestItem() {
        guard let oldestKey = preloadedPlayerItems.min(by: { $0.value.created < $1.value.created })?.key else {
            return
        }
        
        preloadedPlayerItems.removeValue(forKey: oldestKey)
    }
    
    func clearPlayerItemCache() {
        let cacheSize = preloadedPlayerItems.count
        preloadedPlayerItems.removeAll()
        logger.log("🛡️ Cleared all \(cacheSize) player items due to memory pressure", level: .warning)
    }
    
    private func localDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    // MARK: - Schedule Status
    
    var hasActiveSchedule: Bool {
        !UserPreferences.shared.schedule.repeatDays.isEmpty
    }
    
    var backgroundTaskStatus: String {
        if !hasActiveSchedule {
            return "No active schedule"
        } else if isBackgroundTaskRegistered {
            return "Registered"
        } else {
            return "Not registered (will register on demand)"
        }
    }
}

// MARK: - Helper Structs

private struct ScheduleInfo {
    let date: Date
    let scheduledTime: Date
}