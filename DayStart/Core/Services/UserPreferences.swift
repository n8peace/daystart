import Foundation
import SwiftUI
import Combine

/// Simplified UserPreferences with aggressive dependency deferral
/// Uses UserDefaults as single source of truth for reliable persistence
@MainActor
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private let userDefaults = UserDefaults.standard
    
    // Lazy-loaded dependencies (only when needed)
    private var _logger: DebugLogger?
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            logger.log("🎓 hasCompletedOnboarding changed: \(oldValue) → \(hasCompletedOnboarding)", level: .info)
            userDefaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    @Published var schedule: DayStartSchedule {
        didSet {
            saveSchedule()
            // Handle schedule changes in background
            handleScheduleChange()
        }
    }
    
    @Published var settings: UserSettings {
        didSet {
            // Only trigger settings save when changed
            saveSettings()
        }
    }
    
    @Published var history: [DayStartData] {
        didSet {
            debouncedSaveHistory()
        }
    }
    
    private var saveHistoryWorkItem: DispatchWorkItem?
    
    private init() {
        // INSTANT: Only UserDefaults loading (no dependencies)
        self.hasCompletedOnboarding = userDefaults.bool(forKey: "hasCompletedOnboarding")
        self.schedule = Self.loadScheduleFromUserDefaults() ?? DayStartSchedule()
        self.settings = Self.loadSettingsFromUserDefaults() ?? UserSettings.default
        self.history = Self.loadHistoryFromUserDefaults() ?? []
        
        // UserDefaults is now the single source of truth - no reconciliation needed
    }
    
    // MARK: - Lazy Dependencies
    
    
    private var logger: DebugLogger {
        if _logger == nil {
            _logger = DebugLogger.shared
        }
        return _logger!
    }
    
    // MARK: - Fast UserDefaults Loading (No Dependencies)
    
    private static func loadScheduleFromUserDefaults() -> DayStartSchedule? {
        guard let data = UserDefaults.standard.data(forKey: "schedule"),
              let schedule = try? JSONDecoder().decode(DayStartSchedule.self, from: data) else {
            return nil
        }
        return schedule
    }
    
    private static func loadSettingsFromUserDefaults() -> UserSettings? {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return nil
        }
        return settings
    }
    
    private static func loadHistoryFromUserDefaults() -> [DayStartData]? {
        guard let data = UserDefaults.standard.data(forKey: "history"),
              let decoded = try? JSONDecoder().decode([DayStartData].self, from: data) else {
            return nil
        }
        return Self.processHistory(decoded)
    }
    
    // MARK: - UserDefaults is now single source of truth
    // Keychain reconciliation removed - no longer needed
    
    // MARK: - History Processing (Static, No Dependencies)
    
    private static func processHistory(_ decoded: [DayStartData]) -> [DayStartData] {
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let targetDate = calendar.date(from: DateComponents(year: 2025, month: 8, day: 8))
        
        let patched: [DayStartData] = decoded.map { item in
            var updated = item
            if let targetDate = targetDate, calendar.isDate(item.date, inSameDayAs: targetDate) {
                // Attach bundled sample audio for the Aug 8, 2025 entry
                updated.audioFilePath = Bundle.main.path(forResource: "voice1_fallback", ofType: "mp3", inDirectory: "Audio/Fallbacks")
                updated.isDeleted = false
            } else if item.date < sevenDaysAgo {
                // Mark entries older than 7 days as deleted
                updated.isDeleted = true
            }
            return updated
        }
        
        // Deduplicate the patched history
        var deduplicatedHistory: [DayStartData] = []
        var seenDates: Set<DateComponents> = []
        
        for item in patched {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: item.date)
            
            if !seenDates.contains(dateComponents) {
                seenDates.insert(dateComponents)
                deduplicatedHistory.append(item)
            } else {
                // Find existing item for this date and keep the better one
                if let existingIndex = deduplicatedHistory.firstIndex(where: { 
                    let existingComponents = calendar.dateComponents([.year, .month, .day], from: $0.date)
                    return existingComponents == dateComponents 
                }) {
                    let existing = deduplicatedHistory[existingIndex]
                    let shouldReplace = item.audioFilePath != nil && (existing.audioFilePath == nil || item.date > existing.date)
                    
                    if shouldReplace {
                        deduplicatedHistory[existingIndex] = item
                    }
                }
            }
        }
        
        return deduplicatedHistory
    }
    
    // MARK: - Saving (Deferred Keychain)
    
    private func saveSchedule() {
        let scheduleToSave = schedule
        
        // IMMEDIATE: Save to UserDefaults for fast access
        if let data = try? JSONEncoder().encode(scheduleToSave) {
            userDefaults.set(data, forKey: "schedule")
        }
        
        // UserDefaults is now the single source of truth - no Keychain needed
    }
    
    /// Handle schedule changes to update/cancel jobs when days are added/removed
    private func handleScheduleChange() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.updateJobsForScheduleChange()
        }
    }
    
    func saveSettings() {
        let settingsToSave = settings
        
        // Debug logging for news and sports settings being saved
        logger.log("💾 Saving settings - News: includeNews=\(settingsToSave.includeNews), selectedNewsCategories=\(settingsToSave.selectedNewsCategories.map(\.rawValue))", level: .debug)
        logger.log("💾 Saving settings - Sports: includeSports=\(settingsToSave.includeSports), selectedSports=\(settingsToSave.selectedSports.map(\.rawValue))", level: .debug)
        
        // IMMEDIATE: Save to UserDefaults for fast access
        if let data = try? JSONEncoder().encode(settingsToSave) {
            userDefaults.set(data, forKey: "settings")
        }
        
        // DEFERRED: Background job updates (only if content generation is needed)
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.updateUpcomingJobsIfNeeded(with: settingsToSave)
        }
    }
    
    /// Update jobs when timezone changes to maintain alarm clock behavior
    func updateJobsForTimezoneChange() async {
        do {
            let supabaseClient = ServiceRegistry.shared.supabaseClient
            let currentSettings = await MainActor.run { self.settings }
            let currentSchedule = await MainActor.run { self.schedule }
            
            // Get upcoming scheduled dates that need timezone updates
            let upcomingDates = await MainActor.run { self.upcomingScheduledDates(windowHours: 72) }
            guard !upcomingDates.isEmpty else {
                await MainActor.run {
                    logger.log("🌍 No upcoming scheduled dates to update for timezone change", level: .info)
                }
                return
            }
            
            // Format current schedule time for backend recalculation (timezone-independent)
            let scheduleTimeString: String = {
                let components = currentSchedule.effectiveTimeComponents
                let hour = String(format: "%02d", components.hour ?? 7)
                let minute = String(format: "%02d", components.minute ?? 0)
                return "\(hour):\(minute)"
            }()
            
            await MainActor.run {
                logger.log("🌍 Updating \(upcomingDates.count) jobs for timezone change to maintain \(scheduleTimeString) local time", level: .info)
            }
            
            // Call updateJobs WITH scheduleTime parameter to trigger backend recalculation
            let result = try await supabaseClient.updateJobs(
                dates: upcomingDates,
                with: currentSettings,
                scheduleTime: scheduleTimeString // ← This triggers scheduled_at recalculation in new timezone
            )
            
            await MainActor.run {
                logger.log("🌍 Timezone change: Successfully updated \(result.updatedCount) jobs to maintain local time (\(scheduleTimeString))", level: .info)
            }
            
            // Trigger snapshot update since times have changed
            await triggerSnapshotUpdateForPreferenceChange()
            
        } catch {
            await MainActor.run {
                logger.logError(error, context: "Failed to update jobs for timezone change")
            }
        }
    }
    
    /// Update upcoming jobs for schedule changes (add/remove days)
    private func updateJobsForScheduleChange() async {
        do {
            let supabaseClient = ServiceRegistry.shared.supabaseClient
            let settings = await MainActor.run { self.settings }
            let currentSchedule = await MainActor.run { self.schedule }
            
            // Get the next 3 days to check for schedule changes
            let calendar = Calendar.current
            let now = Date()
            let threeDaysFromNow = calendar.date(byAdding: .day, value: 3, to: now) ?? now
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            
            let startDate = formatter.string(from: now)
            let endDate = formatter.string(from: threeDaysFromNow)
            
            // Get existing jobs from backend
            let existingJobs = try await supabaseClient.getJobsInDateRange(startDate: startDate, endDate: endDate)
            
            // Calculate dates that should be scheduled based on current schedule
            let shouldBeScheduledDates = await MainActor.run { self.upcomingScheduledDates(windowHours: 72) }
            
            // Find dates that have jobs but shouldn't be scheduled anymore (to cancel)
            let datesToCancel: [Date] = existingJobs.compactMap { job in
                guard let jobDate = formatter.date(from: job.localDate) else { return nil }
                let jobShouldExist = shouldBeScheduledDates.contains { scheduledDate in
                    calendar.isDate(jobDate, inSameDayAs: scheduledDate)
                }
                return jobShouldExist ? nil : jobDate
            }
            
            // Find dates that should be scheduled but might have cancelled jobs (to reactivate)
            let datesToReactivate: [Date] = shouldBeScheduledDates.compactMap { scheduledDate in
                // Check if we have any existing jobs (including cancelled ones) for this date
                let hasExistingJob = existingJobs.contains { job in
                    guard let jobDate = formatter.date(from: job.localDate) else { return false }
                    return calendar.isDate(jobDate, inSameDayAs: scheduledDate)
                }
                // If we should schedule this date but have no existing job, it might be a newly cancelled job to reactivate
                return hasExistingJob ? scheduledDate : nil
            }
            
            // Update jobs with current settings, cancel removed dates, and reactivate added dates
            // Always update if there are scheduled dates (to handle time changes) or if there are cancellations/reactivations
            if !shouldBeScheduledDates.isEmpty || !datesToCancel.isEmpty || !datesToReactivate.isEmpty {
                // Convert schedule time to HH:MM format for server-side calculation
                let scheduleTimeString: String? = {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    return formatter.string(from: currentSchedule.time)
                }()
                
                let result = try await supabaseClient.updateJobs(
                    dates: shouldBeScheduledDates, 
                    with: settings, 
                    scheduleTime: scheduleTimeString, // NEW: Pass the schedule time for server-side scheduled_at calculation
                    cancelDates: datesToCancel,
                    reactivateDates: datesToReactivate
                )
                
                await MainActor.run {
                    logger.log("✅ Schedule change: Updated \(result.updatedCount) jobs, cancelled \(result.cancelledCount) jobs, reactivated \(result.reactivatedCount) jobs", level: .info)
                }
                
                // Trigger snapshot update if there are still scheduled jobs
                if !shouldBeScheduledDates.isEmpty {
                    await triggerSnapshotUpdateForPreferenceChange()
                }
            }
            
        } catch {
            await MainActor.run {
                logger.logError(error, context: "Failed to update jobs for schedule change")
            }
        }
    }
    
    /// Update upcoming jobs only when content generation services are needed
    private func updateUpcomingJobsIfNeeded(with settings: UserSettings) async {
        let upcomingDates = await MainActor.run { self.upcomingScheduledDates(windowHours: 48) }
        guard !upcomingDates.isEmpty else { return }
        
        do {
            // Debug logging before updating jobs
            await MainActor.run {
                logger.log("🔄 Updating \(upcomingDates.count) upcoming jobs with settings - News: includeNews=\(settings.includeNews), selectedNewsCategories=\(settings.selectedNewsCategories.map(\.rawValue))", level: .debug)
            }
            
            // LAZY: Only load SupabaseClient when actually updating jobs
            let supabaseClient = ServiceRegistry.shared.supabaseClient
            let result = try await supabaseClient.updateJobs(dates: upcomingDates, with: settings)
            await MainActor.run {
                logger.log("✅ Updated \(result.updatedCount) scheduled jobs with new settings", level: .info)
            }
            
            // Trigger immediate snapshot update for preference changes (bypasses rate limiting)
            await triggerSnapshotUpdateForPreferenceChange()
            
        } catch {
            await MainActor.run {
                logger.logError(error, context: "Failed to update scheduled jobs after settings change")
            }
        }
    }
    
    /// Trigger snapshot update when preferences change (bypasses rate limiting)
    private func triggerSnapshotUpdateForPreferenceChange() async {
        await MainActor.run {
            let registry = ServiceRegistry.shared
            
            // Only trigger if user has active schedule
            guard !schedule.repeatDays.isEmpty else {
                return
            }
            
            // Initialize SnapshotUpdateManager and trigger preference change update
            Task {
                await registry.snapshotUpdateManager.updateSnapshotsForUpcomingJobs(trigger: .preferencesChanged)
            }
        }
    }
    
    private func debouncedSaveHistory() {
        saveHistoryWorkItem?.cancel()
        
        saveHistoryWorkItem = DispatchWorkItem { [weak self] in
            self?.saveHistory()
        }
        
        if let workItem = saveHistoryWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }
    
    private func saveHistory() {
        let historyToSave = history
        
        // IMMEDIATE: Save to UserDefaults for fast access
        if let data = try? JSONEncoder().encode(historyToSave) {
            userDefaults.set(data, forKey: "history")
        }
        
        // UserDefaults is now the single source of truth - no Keychain needed
    }
    
    // MARK: - Scheduling Helpers (No Dependencies)
    
    private func upcomingScheduledDates(windowHours: Int = 48) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        let maxScheduleTime = now.addingTimeInterval(TimeInterval(windowHours * 60 * 60))
        var results: [Date] = []
        
        for dayOffset in 0..<3 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            // Skip tomorrow if enabled
            if schedule.skipTomorrow {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                if calendar.isDate(targetDate, inSameDayAs: tomorrow) { continue }
            }
            
            // Check repeat schedule
            let weekday = calendar.component(.weekday, from: targetDate)
            guard let weekDay = WeekDay(weekday: weekday), schedule.repeatDays.contains(weekDay) else { continue }
            
            // Build occurrence at scheduled time using timezone-independent components
            let timeComponents = schedule.effectiveTimeComponents
            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            if let occurrence = calendar.date(from: components), occurrence > now, occurrence <= maxScheduleTime {
                results.append(occurrence)
            }
        }
        
        // Ensure unique days
        var uniqueByDay: [String: Date] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for d in results { uniqueByDay[df.string(from: d)] = d }
        return Array(uniqueByDay.values).sorted()
    }
    
    // MARK: - History Management
    
    private func isFallbackTranscript(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return trimmed.contains("Welcome to your DayStart! Please connect to the internet")
    }
    
    func addToHistory(_ dayStart: DayStartData) {
        let calendar = Calendar.current
        
        // Check if we already have an entry for this date
        if let existingIndex = history.firstIndex(where: { existing in
            guard let existingDate = existing.scheduledTime ?? existing.date as Date?,
                  let newDate = dayStart.scheduledTime ?? dayStart.date as Date? else {
                return false
            }
            return calendar.isDate(existingDate, inSameDayAs: newDate)
        }) {
            // Update existing entry but preserve important fields
            var updatedEntry = dayStart
            let existing = history[existingIndex]
            
            // Preserve the original ID so updateHistory can find it later
            updatedEntry.id = existing.id
            
            // Preserve scheduledTime if it exists in the old entry but not the new one
            if existing.scheduledTime != nil && dayStart.scheduledTime == nil {
                updatedEntry.scheduledTime = existing.scheduledTime
            }
            
            // Preserve jobId if it exists in either the old or new entry (for share functionality)
            if existing.jobId != nil {
                updatedEntry.jobId = existing.jobId
            } else if dayStart.jobId != nil {
                updatedEntry.jobId = dayStart.jobId
            }
            
            // Preserve audio file path if it exists
            if existing.audioFilePath != nil && dayStart.audioFilePath == nil {
                updatedEntry.audioFilePath = existing.audioFilePath
            }
            
            // Preserve audioStoragePath if it exists in either the old or new entry (for share functionality)
            if existing.audioStoragePath != nil {
                updatedEntry.audioStoragePath = existing.audioStoragePath
            } else if dayStart.audioStoragePath != nil {
                updatedEntry.audioStoragePath = dayStart.audioStoragePath
            }
            
            // Preserve transcript if existing has a real one and new is empty/fallback
            let newTranscript = dayStart.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingTranscript = existing.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !existingTranscript.isEmpty && (newTranscript.isEmpty || isFallbackTranscript(newTranscript)) {
                updatedEntry.transcript = existing.transcript
            }
            
            // Preserve duration if existing has > 0 and new is 0/invalid
            if existing.duration > 0 && dayStart.duration <= 0 {
                updatedEntry.duration = existing.duration
            }
            
            history[existingIndex] = updatedEntry
            logger.log("Updated existing history entry for date: \(dayStart.date)", level: .debug)
        } else {
            // Add new entry
            history.insert(dayStart, at: 0)
            if history.count > 30 {
                history.removeLast()
            }
            logger.log("Added new history entry for date: \(dayStart.date)", level: .debug)
        }
        
        // Periodically clean up old audio files (every 5th addition)
        if history.count % 5 == 0 {
            Task {
                await self.cleanupOldAudioFiles()
            }
        }
    }
    
    func updateHistory(with id: UUID, transcript: String? = nil, duration: TimeInterval? = nil, audioFilePath: String? = nil, jobId: String? = nil, audioStoragePath: String? = nil) {
        guard let index = history.firstIndex(where: { $0.id == id }) else {
            logger.log("⚠️ Could not find history item with id: \(id)", level: .warning)
            return
        }
        
        var updatedItem = history[index]
        
        if let transcript = transcript {
            updatedItem.transcript = transcript
        }
        
        if let duration = duration {
            updatedItem.duration = duration
        }
        
        if let audioFilePath = audioFilePath {
            updatedItem.audioFilePath = audioFilePath
        }
        
        if let jobId = jobId {
            updatedItem.jobId = jobId
        }
        
        if let audioStoragePath = audioStoragePath {
            updatedItem.audioStoragePath = audioStoragePath
        }
        
        history[index] = updatedItem
        logger.log("✅ Updated history item: id=\(id)", level: .info)
    }
    
    func isWithinLockoutPeriod(of date: Date) -> Bool {
        let hoursUntil = date.timeIntervalSinceNow / 3600
        return hoursUntil < 4 && hoursUntil > 0
    }
    
    // MARK: - Audio Cleanup (Deferred, No Dependencies in Call Path)
    
    nonisolated func cleanupOldAudioFiles() async {
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        let currentHistory = await history
        var updatedHistory = currentHistory
        var deletedCount = 0
        var errorCount = 0
        
        for i in 0..<updatedHistory.count {
            let item = updatedHistory[i]
            
            guard !item.isDeleted && item.date < sevenDaysAgo else { continue }
            
            // Delete the audio file if it exists and isn't bundled
            if let audioPath = item.audioFilePath,
               !audioPath.contains(".app/"),
               FileManager.default.fileExists(atPath: audioPath) {
                do {
                    try FileManager.default.removeItem(atPath: audioPath)
                    deletedCount += 1
                } catch {
                    errorCount += 1
                }
            }
            
            updatedHistory[i].isDeleted = true
        }
        
        // Update history on main thread if changes were made
        if deletedCount > 0 || updatedHistory.contains(where: { !$0.isDeleted && $0.date < sevenDaysAgo }) {
            await MainActor.run {
                history = updatedHistory
            }
        }
    }
}