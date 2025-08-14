import Foundation
import SwiftUI
import Combine

@MainActor
class UserPreferences: ObservableObject {
    static let shared = UserPreferences()
    
    private let userDefaults = UserDefaults.standard
    private let keychain = KeychainManager.shared
    private let logger = DebugLogger.shared
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            userDefaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    @Published var schedule: DayStartSchedule {
        didSet {
            saveSchedule()
        }
    }
    
    @Published var settings: UserSettings
    
    @Published var history: [DayStartData] {
        didSet {
            debouncedSaveHistory()
        }
    }
    
    private var saveHistoryWorkItem: DispatchWorkItem?
    
    private init() {
        // PHASE 2 OPTIMIZATION: UserDefaults-first loading for instant initialization
        self.hasCompletedOnboarding = userDefaults.bool(forKey: "hasCompletedOnboarding")
        self.schedule = Self.loadScheduleFromUserDefaults() ?? DayStartSchedule()
        self.settings = Self.loadSettingsFromUserDefaults() ?? UserSettings.default
        self.history = Self.loadHistoryFromUserDefaults() ?? []
        
        logger.log("🏎 UserPreferences initialized instantly from UserDefaults", level: .debug)
        
        // BACKGROUND: Reconcile with Keychain without blocking main thread
        Task.detached { [weak self] in
            await self?.reconcileWithKeychain()
        }
    }
    
    // PHASE 2: Separate UserDefaults and Keychain loading methods
    private static func loadScheduleFromUserDefaults() -> DayStartSchedule? {
        guard let data = UserDefaults.standard.data(forKey: "schedule"),
              let schedule = try? JSONDecoder().decode(DayStartSchedule.self, from: data) else {
            return nil
        }
        return schedule
    }
    
    private static func loadScheduleFromKeychain() -> DayStartSchedule? {
        return KeychainManager.shared.retrieve(DayStartSchedule.self, forKey: KeychainManager.Keys.schedule)
    }
    
    // PHASE 2: Separate UserDefaults and Keychain loading methods
    private static func loadSettingsFromUserDefaults() -> UserSettings? {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return nil
        }
        return settings
    }
    
    private static func loadSettingsFromKeychain() -> UserSettings? {
        return KeychainManager.shared.retrieve(UserSettings.self, forKey: KeychainManager.Keys.userSettings)
    }
    
    // PHASE 2: Separate UserDefaults and Keychain loading methods  
    private static func loadHistoryFromUserDefaults() -> [DayStartData]? {
        guard let data = UserDefaults.standard.data(forKey: "history"),
              let decoded = try? JSONDecoder().decode([DayStartData].self, from: data) else {
            return nil
        }
        return Self.processHistory(decoded)
    }
    
    // PHASE 2: Background reconciliation with Keychain
    private func reconcileWithKeychain() async {
        logger.log("🔄 Starting background Keychain reconciliation", level: .info)
        
        // Load from Keychain in background
        let keychainSchedule = Self.loadScheduleFromKeychain()
        let keychainSettings = Self.loadSettingsFromKeychain()
        let keychainHistory = Self.loadHistoryFromKeychain()
        
        await MainActor.run {
            var hasUpdates = false
            
            // Update from Keychain data if it exists
            if let keychainSchedule = keychainSchedule {
                logger.log("🔄 Updating schedule from Keychain", level: .info)
                self.schedule = keychainSchedule
                hasUpdates = true
            }
            
            if let keychainSettings = keychainSettings {
                logger.log("🔄 Updating settings from Keychain", level: .info)
                self.settings = keychainSettings
                hasUpdates = true
            }
            
            if let keychainHistory = keychainHistory {
                logger.log("🔄 Updating history from Keychain", level: .info)
                self.history = keychainHistory
                hasUpdates = true
            }
            
            if hasUpdates {
                logger.log("✅ Keychain reconciliation completed with updates", level: .info)
            } else {
                logger.log("✅ Keychain reconciliation completed - data was in sync", level: .info)
            }
        }
    }
    
    private static func loadHistoryFromKeychain() -> [DayStartData]? {
        if let history = KeychainManager.shared.retrieve([DayStartData].self, forKey: KeychainManager.Keys.history) {
            return Self.processHistory(history)
        }
        return nil
    }
    
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
                // Mark entries older than 7 days as deleted (defer file deletion to async cleanup task)
                updated.isDeleted = true
            }
            return updated
        }
        
        // Deduplicate the patched history to remove any duplicate dates
        var deduplicatedHistory: [DayStartData] = []
        var seenDates: Set<DateComponents> = []
        
        for item in patched {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: item.date)
            
            if !seenDates.contains(dateComponents) {
                seenDates.insert(dateComponents)
                deduplicatedHistory.append(item)
            } else {
                // Find the existing item for this date
                if let existingIndex = deduplicatedHistory.firstIndex(where: { 
                    let existingComponents = calendar.dateComponents([.year, .month, .day], from: $0.date)
                    return existingComponents == dateComponents 
                }) {
                    let existing = deduplicatedHistory[existingIndex]
                    
                    // Keep the one with more data (audio) or the most recent
                    let shouldReplace = item.audioFilePath != nil && (existing.audioFilePath == nil || item.date > existing.date)
                    
                    if shouldReplace {
                        deduplicatedHistory[existingIndex] = item
                    }
                }
            }
        }
        
        return deduplicatedHistory
    }
    
    private func saveSchedule() {
        let scheduleToSave = schedule
        
        // PHASE 2: Save to UserDefaults immediately for fast access
        if let data = try? JSONEncoder().encode(scheduleToSave) {
            userDefaults.set(data, forKey: "schedule")
        }
        
        // Background save to Keychain for security
        Task.detached { [weak self] in
            guard let self = self else { return }
            _ = self.keychain.store(scheduleToSave, forKey: KeychainManager.Keys.schedule)
        }
    }
    
    func saveSettings() {
        let settingsToSave = settings
        
        // PHASE 2: Save to UserDefaults immediately for fast access
        if let data = try? JSONEncoder().encode(settingsToSave) {
            userDefaults.set(data, forKey: "settings")
        }
        
        // Background save to Keychain for security
        Task.detached { [weak self] in
            guard let self = self else { return }
            let success = self.keychain.store(settingsToSave, forKey: KeychainManager.Keys.userSettings)
            if !success {
                await MainActor.run {
                    self.logger.logError(NSError(domain: "KeychainError", code: 1), context: "Failed to save user settings to Keychain")
                }
            }
        }

        // After saving, update upcoming scheduled jobs (next 48h) with new settings
        Task { [weak self] in
            guard let self = self else { return }
            self.logger.log("🛠️ Settings saved; updating upcoming jobs with new settings", level: .info)
            let upcomingDates = self.upcomingScheduledDates(windowHours: 48)
            if upcomingDates.isEmpty { return }
            do {
                _ = try await SupabaseClient.shared.updateJobs(dates: upcomingDates, with: settingsToSave, forceRequeue: false)
                self.logger.log("✅ Updated \(upcomingDates.count) scheduled jobs with new settings", level: .info)
            } catch {
                self.logger.logError(error, context: "Failed to update scheduled jobs after settings change")
            }
        }
    }

    // MARK: - Scheduling helpers
    private func upcomingScheduledDates(windowHours: Int = 48) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        let maxScheduleTime = now.addingTimeInterval(TimeInterval(windowHours * 60 * 60))
        var results: [Date] = []
        
        for dayOffset in 0..<3 { // today, tomorrow, day after
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            // Skip tomorrow if enabled
            if schedule.skipTomorrow {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                if calendar.isDate(targetDate, inSameDayAs: tomorrow) { continue }
            }
            
            // Check repeat schedule
            let weekday = calendar.component(.weekday, from: targetDate)
            guard let weekDay = WeekDay(weekday: weekday), schedule.repeatDays.contains(weekDay) else { continue }
            
            // Build occurrence at scheduled time
            let timeComponents = calendar.dateComponents([.hour, .minute], from: schedule.time)
            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            
            if let occurrence = calendar.date(from: components), occurrence > now, occurrence <= maxScheduleTime {
                results.append(occurrence)
            }
        }
        
        // Ensure unique days by local date
        var uniqueByDay: [String: Date] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for d in results { uniqueByDay[df.string(from: d)] = d }
        return Array(uniqueByDay.values).sorted()
    }
    
    
    private func debouncedSaveHistory() {
        // Cancel any pending save
        saveHistoryWorkItem?.cancel()
        
        // Schedule new save with 0.5s delay to batch rapid changes
        saveHistoryWorkItem = DispatchWorkItem { [weak self] in
            self?.saveHistory()
        }
        
        if let workItem = saveHistoryWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }
    
    private func saveHistory() {
        let historyToSave = history
        
        // PHASE 2: Save to UserDefaults immediately for fast access
        if let data = try? JSONEncoder().encode(historyToSave) {
            userDefaults.set(data, forKey: "history")
        }
        
        // Background save to Keychain for security
        Task.detached { [weak self] in
            guard let self = self else { return }
            _ = self.keychain.store(historyToSave, forKey: KeychainManager.Keys.history)
        }
    }
    
    func addToHistory(_ dayStart: DayStartData) {
        history.insert(dayStart, at: 0)
        if history.count > 30 {
            history.removeLast()
        }
        
        // Periodically clean up old audio files (every 5th addition)
        if history.count % 5 == 0 {
            Task {
                await self.cleanupOldAudioFiles()
            }
        }
    }
    
    func updateHistory(with id: UUID, transcript: String? = nil, duration: TimeInterval? = nil, audioFilePath: String? = nil) {
        guard let index = history.firstIndex(where: { $0.id == id }) else {
            logger.log("⚠️ Could not find history item with id: \(id)", level: .warning)
            return
        }
        
        var updatedItem = history[index]
        
        // Update fields if provided
        if let transcript = transcript {
            updatedItem.transcript = transcript
        }
        
        if let duration = duration {
            updatedItem.duration = duration
        }
        
        if let audioFilePath = audioFilePath {
            updatedItem.audioFilePath = audioFilePath
        }
        
        // Replace the item in history
        history[index] = updatedItem
        
        logger.log("✅ Updated history item: id=\(id), transcript=\(transcript != nil), duration=\(duration != nil), audioPath=\(audioFilePath != nil)", level: .info)
    }
    
    func isWithinLockoutPeriod(of date: Date) -> Bool {
        let hoursUntil = date.timeIntervalSinceNow / 3600
        return hoursUntil < 4 && hoursUntil > 0
    }
    
    // MARK: - Audio Cleanup
    nonisolated func cleanupOldAudioFiles() async {
        await MainActor.run {
            logger.log("🧹 Starting cleanup of old audio files", level: .info)
        }
        
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        // Work with a copy to avoid concurrent modifications
        let currentHistory = await history
        var updatedHistory = currentHistory
        var deletedCount = 0
        var errorCount = 0
        
        for i in 0..<updatedHistory.count {
            let item = updatedHistory[i]
            
            // Skip if already marked as deleted or not old enough
            guard !item.isDeleted && item.date < sevenDaysAgo else { continue }
            
            // Delete the audio file if it exists and isn't bundled
            if let audioPath = item.audioFilePath,
               !audioPath.contains(".app/"), // Skip bundled resources
               FileManager.default.fileExists(atPath: audioPath) {
                do {
                    try FileManager.default.removeItem(atPath: audioPath)
                    await MainActor.run {
                    }
                    deletedCount += 1
                } catch {
                    await MainActor.run {
                        logger.logError(error, context: "Failed to delete audio file: \(audioPath)")
                    }
                    errorCount += 1
                }
            }
            
            // Mark as deleted
            updatedHistory[i].isDeleted = true
        }
        
        // Update history on main thread if any changes were made
        if deletedCount > 0 || updatedHistory.contains(where: { !$0.isDeleted && $0.date < sevenDaysAgo }) {
            await MainActor.run {
                history = updatedHistory
                logger.log("✅ Audio cleanup completed: \(deletedCount) files deleted, \(errorCount) errors", level: .info)
            }
        } else {
            await MainActor.run {
            }
        }
    }
}