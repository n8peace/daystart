import Foundation
import SwiftUI
import Combine

class HomeViewModel: ObservableObject {
    private let logger = DebugLogger.shared
    enum AppState {
        case idle
        case countdown
        case ready
        case playing
        case recentlyPlayed
    }
    
    @Published var state: AppState = .idle
    @Published var countdownText = ""
    @Published var nextDayStartTime: Date?
    @Published var currentDayStart: DayStartData?
    @Published var showNoScheduleMessage = false
    @Published var hasCompletedCurrentOccurrence = false
    @Published var isNextDayStartTomorrow = false
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let userPreferences = UserPreferences.shared
    private let audioPlayer = AudioPlayerManager.shared
    private let notificationScheduler = NotificationScheduler.shared
    private let mockService = MockDataService.shared
    
    init() {
        logger.log("🏠 HomeViewModel initialized", level: .info)
        setupObservers()
        updateState()
        
        // Defer mock data generation to avoid "Publishing changes from within view updates"
        Task { @MainActor in
            if userPreferences.history.isEmpty {
                logger.log("🎭 History empty, generating mock data", level: .debug)
                userPreferences.history = mockService.generateMockHistory()
                logger.log("📊 Generated \(userPreferences.history.count) mock history items", level: .info)
            } else {
                logger.log("📚 Found existing history: \(userPreferences.history.count) items", level: .debug)
            }
        }
    }
    
    private func setupObservers() {
        userPreferences.$schedule
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateState()
                self?.scheduleNotifications()
            }
            .store(in: &cancellables)
        
        userPreferences.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Force UI update when settings change
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        audioPlayer.$isPlaying
            .sink { [weak self] isPlaying in
                if self?.state == .playing && !isPlaying {
                    self?.transitionToRecentlyPlayed()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateState() {
        timer?.invalidate()
        logger.log("🔄 Updating app state", level: .debug)
        
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            logger.log("📅 No schedule found, showing no schedule message", level: .info)
            state = .idle
            showNoScheduleMessage = true
            nextDayStartTime = nil
            hasCompletedCurrentOccurrence = false
            isNextDayStartTomorrow = false
            return
        }
        
        showNoScheduleMessage = false
        nextDayStartTime = nextOccurrence
        
        // Check if next DayStart is tomorrow
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        isNextDayStartTomorrow = calendar.isDate(nextOccurrence, inSameDayAs: tomorrow)
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        let sixHoursInSeconds: TimeInterval = 6 * 3600 // 6 hours
        let tenHoursInSeconds: TimeInterval = 10 * 3600 // 10 hours
        
        // Check if current occurrence has been completed
        hasCompletedCurrentOccurrence = hasCompletedOccurrence(nextOccurrence)
        
        if timeUntil <= 0 && timeUntil >= -sixHoursInSeconds {
            // Within 6 hours after scheduled time - show Ready with Play/Replay
            logger.log("⏰ Within 6-hour ready window: \(Int(-timeUntil))s after scheduled time", level: .info)
            state = .ready
        } else if timeUntil > 0 && timeUntil <= tenHoursInSeconds {
            // Less than 10 hours before - show countdown
            logger.log("⏳ Starting countdown: \(Int(timeUntil))s until DayStart", level: .debug)
            startCountdown()
        } else {
            // More than 10 hours before OR more than 6 hours after - show next scheduled time
            if timeUntil < -sixHoursInSeconds {
                logger.log("💤 More than 6 hours past scheduled time, showing next occurrence", level: .debug)
            } else {
                logger.log("💤 More than 10 hours until DayStart, idle state", level: .debug)
            }
            state = .idle
        }
    }
    
    private func startCountdown() {
        state = .countdown
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let nextTime = self.nextDayStartTime else { return }
            
            let timeUntil = nextTime.timeIntervalSinceNow
            
            if timeUntil <= 0 {
                self.state = .ready
                self.timer?.invalidate()
            } else {
                self.updateCountdownText(timeInterval: timeUntil)
            }
        }
    }
    
    private func updateCountdownText(timeInterval: TimeInterval) {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        
        countdownText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    func startDayStart() {
        logger.logUserAction("Start DayStart", details: ["time": Date().description])
        let dayStart = mockService.fetchDayStart(for: userPreferences.settings)
        
        // Mark this occurrence with the scheduled time for tracking
        var dayStartWithScheduledTime = dayStart
        if let scheduledTime = nextDayStartTime {
            dayStartWithScheduledTime.scheduledTime = scheduledTime
        }
        
        currentDayStart = dayStartWithScheduledTime
        userPreferences.addToHistory(dayStartWithScheduledTime)
        
        logger.logAudioEvent("Loading audio for DayStart")
        audioPlayer.loadAudio()
        audioPlayer.play()
        state = .playing
        
        // Cancel today's missed notification since user is now listening
        Task {
            await notificationScheduler.cancelTodaysMissedNotification()
        }
        
        scheduleNextNotifications()
    }
    
    func replayDayStart(_ dayStart: DayStartData) {
        logger.logUserAction("Replay DayStart", details: ["id": dayStart.id])
        currentDayStart = dayStart
        audioPlayer.loadAudio()
        audioPlayer.play()
        state = .playing
    }
    
    private func transitionToRecentlyPlayed() {
        logger.log("✅ DayStart completed, transitioning to recently played", level: .info)
        
        // Update completion status for current occurrence
        if let scheduledTime = nextDayStartTime {
            hasCompletedCurrentOccurrence = hasCompletedOccurrence(scheduledTime)
        }
        
        state = .recentlyPlayed
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.state == .recentlyPlayed {
                self?.updateState()
            }
        }
    }
    
    private func scheduleNotifications() {
        logger.log("📬 Scheduling notifications", level: .debug)
        Task {
            await notificationScheduler.scheduleNotifications(for: userPreferences.schedule)
        }
    }
    
    private func scheduleNextNotifications() {
        var nextSchedule = userPreferences.schedule
        nextSchedule.skipTomorrow = false
        userPreferences.schedule = nextSchedule
    }
    
    private func hasCompletedOccurrence(_ scheduledTime: Date) -> Bool {
        let calendar = Calendar.current
        
        // Look for a completed DayStart with matching scheduled time
        return userPreferences.history.contains { dayStart in
            guard !dayStart.isDeleted,
                  let dayStartScheduledTime = dayStart.scheduledTime else {
                return false
            }
            
            // Check if scheduled times match (within 1 minute tolerance for any scheduling drift)
            return abs(dayStartScheduledTime.timeIntervalSince(scheduledTime)) < 60
        }
    }
}