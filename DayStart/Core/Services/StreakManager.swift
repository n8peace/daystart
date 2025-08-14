import Foundation
import Combine
import SwiftUI

@MainActor
final class StreakManager: ObservableObject {
    static let shared = StreakManager()

    // Published UI state
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var todayProgress: Double = 0.0 // 0...1
    @Published private(set) var todayCompletedSameDay: Bool = false

    enum DayStatus: Equatable {
        case notStarted
        case inProgress
        case completedSameDay
        case completedLate
    }

    private let logger = DebugLogger.shared
    private var audioPlayer: AudioPlayerManager { AudioPlayerManager.shared }
    private let userPreferences = UserPreferences.shared
    private let notificationScheduler = NotificationScheduler.shared

    private var cancellables = Set<AnyCancellable>()

    // Persistence keys
    private let sameDayKey = "streak_same_day_dates" // Set<String YYYY-MM-DD>
    private let lateKey = "streak_late_dates" // Set<String YYYY-MM-DD>
    private let bestKey = "streak_best_value"

    // Backing stores
    private var sameDayCompletionDates: Set<String>
    private var lateCompletionDates: Set<String>

    // Threshold config
    private let minRatio: Double = 0.60
    private let minSeconds: TimeInterval = 300 // 5 minutes

    private init() {
        sameDayCompletionDates = Set(UserDefaults.standard.stringArray(forKey: sameDayKey) ?? [])
        lateCompletionDates = Set(UserDefaults.standard.stringArray(forKey: lateKey) ?? [])
        bestStreak = UserDefaults.standard.integer(forKey: bestKey)

        bindAudioProgress()
        recomputeStreaks()
        updateTodayFlags()
    }

    // MARK: - Public API
    func status(for date: Date) -> DayStatus {
        let key = Self.key(for: date)
        if sameDayCompletionDates.contains(key) { return .completedSameDay }
        if lateCompletionDates.contains(key) { return .completedLate }

        // In progress if currently playing this day's DayStart
        if let currentId = audioPlayer.currentTrackId,
           let day = userPreferences.history.first(where: { $0.id == currentId }) {
            let deliveredDate = deliveredDate(for: day)
            if Calendar.current.isDate(deliveredDate, inSameDayAs: date), audioPlayer.isPlaying {
                return .inProgress
            }
        }
        return .notStarted
    }

    func lastNDaysStatuses(_ n: Int) -> [(date: Date, status: DayStatus)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, status(for: date))
        }
    }

    // MARK: - Private
    private func bindAudioProgress() {
        // Observe time and duration for threshold crossing
        audioPlayer.$currentTime
            .combineLatest(audioPlayer.$duration, audioPlayer.$currentTrackId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime, duration, currentTrackId in
                guard let self else { return }
                self.evaluateProgress(currentTime: currentTime, duration: duration, currentTrackId: currentTrackId)
            }
            .store(in: &cancellables)

        // Also observe play state to zero out progress when not playing
        audioPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if !isPlaying { self.todayProgress = self.todayCompletedSameDay ? 1.0 : 0.0 }
            }
            .store(in: &cancellables)
    }

    private func evaluateProgress(currentTime: TimeInterval, duration: TimeInterval, currentTrackId: UUID?) {
        guard duration > 0 else { return }
        let ratio = max(0, min(currentTime / duration, 1))

        // If we know which history item is playing, use its delivered date
        if let trackId = currentTrackId, let day = userPreferences.history.first(where: { $0.id == trackId }) {
            let delivered = deliveredDate(for: day)
            if Calendar.current.isDateInToday(delivered) {
                todayProgress = todayCompletedSameDay ? 1.0 : ratio
            }
            if (ratio >= minRatio || currentTime >= minSeconds) {
                handleThresholdCross(for: day)
            }
            return
        }

        // Fallback: Home playback uses bundled audio without track id; treat as today's DayStart
        if audioPlayer.isPlaying {
            todayProgress = todayCompletedSameDay ? 1.0 : ratio
            if (ratio >= minRatio || currentTime >= minSeconds) {
                handleThresholdCrossForToday()
            }
        }
    }

    private func handleThresholdCross(for day: DayStartData) {
        let delivered = deliveredDate(for: day)
        let now = Date()
        let deliveredKey = Self.key(for: delivered)

        if Calendar.current.isDate(now, inSameDayAs: delivered) {
            // Same-day completion: idempotent
            if !sameDayCompletionDates.contains(deliveredKey) {
                sameDayCompletionDates.insert(deliveredKey)
                persistSets()
                todayCompletedSameDay = Calendar.current.isDateInToday(delivered)
                todayProgress = 1.0
                recomputeStreaks()
                Task {
                    await notificationScheduler.cancelTodaysMissedNotification()
                    await notificationScheduler.cancelTodaysEveningReminder()
                }
                logger.log("🔥 Streak +1 recorded for \(deliveredKey)", level: .info)
            }
        } else {
            // Late completion: does not count toward streak
            if !lateCompletionDates.contains(deliveredKey) {
                lateCompletionDates.insert(deliveredKey)
                persistSets()
                logger.log("⏳ Late completion recorded for \(deliveredKey)", level: .info)
            }
        }
    }

    private func handleThresholdCrossForToday() {
        let delivered = Calendar.current.startOfDay(for: Date())
        let now = Date()
        let deliveredKey = Self.key(for: delivered)

        if Calendar.current.isDate(now, inSameDayAs: delivered) {
            if !sameDayCompletionDates.contains(deliveredKey) {
                sameDayCompletionDates.insert(deliveredKey)
                persistSets()
                todayCompletedSameDay = true
                todayProgress = 1.0
                recomputeStreaks()
                Task {
                    await notificationScheduler.cancelTodaysMissedNotification()
                    await notificationScheduler.cancelTodaysEveningReminder()
                }
                logger.log("🔥 Streak +1 recorded for today", level: .info)
            }
        }
    }

    private func deliveredDate(for day: DayStartData) -> Date {
        // Use scheduledTime if present, else the entry date
        day.scheduledTime ?? day.date
    }

    private func persistSets() {
        UserDefaults.standard.set(Array(sameDayCompletionDates), forKey: sameDayKey)
        UserDefaults.standard.set(Array(lateCompletionDates), forKey: lateKey)
        UserDefaults.standard.set(bestStreak, forKey: bestKey)
    }

    private func updateTodayFlags() {
        let todayKey = Self.key(for: Date())
        todayCompletedSameDay = sameDayCompletionDates.contains(todayKey)
        todayProgress = todayCompletedSameDay ? 1.0 : 0.0
    }

    private func recomputeStreaks() {
        // Current streak: consecutive days ending today if completed, else ending yesterday
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        var count = 0

        let anchorIsToday = sameDayCompletionDates.contains(Self.key(for: day))
        if !anchorIsToday {
            // Start from yesterday
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return }
            day = y
        }

        while sameDayCompletionDates.contains(Self.key(for: day)) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        currentStreak = count
        if currentStreak > bestStreak {
            bestStreak = currentStreak
            UserDefaults.standard.set(bestStreak, forKey: bestKey)
        }
    }

    private static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}


