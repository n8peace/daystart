import Foundation
import SwiftUI
import Combine

class HomeViewModel: ObservableObject {
    private let logger = DebugLogger.shared
    enum AppState {
        case idle
        case welcomeCountdown
        case welcomeReady
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
    @Published var isNextDayStartToday = false
    
    private var timer: Timer?
    private var pauseTimeoutTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let userPreferences = UserPreferences.shared
    private let audioPlayer = AudioPlayerManager.shared
    private let notificationScheduler = NotificationScheduler.shared
    private let mockService = MockDataService.shared
    private let welcomeScheduler = WelcomeDayStartScheduler.shared
    
    init() {
        logger.log("🏠 HomeViewModel initialized", level: .info)
        setupObservers()
        updateState()
        
        // Defer mock data generation to avoid "Publishing changes from within view updates"
        // Use asyncAfter to ensure this happens outside the current view update cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if self.userPreferences.history.isEmpty {
                self.userPreferences.history = self.mockService.generateMockHistory()
                self.logger.log("📊 Generated \(self.userPreferences.history.count) mock history items", level: .info)
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
                // Force UI update when settings change - defer to avoid publishing during view updates
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        audioPlayer.$didFinishPlaying
            .sink { [weak self] didFinish in
                if self?.state == .playing && didFinish {
                    self?.transitionToRecentlyPlayed()
                }
            }
            .store(in: &cancellables)
        
        // Monitor play/pause state to handle pause timeouts
        audioPlayer.$isPlaying
            .sink { [weak self] isPlaying in
                if self?.state == .playing {
                    if isPlaying {
                        self?.stopPauseTimeoutTimer()
                    } else {
                        self?.startPauseTimeoutTimer()
                    }
                }
            }
            .store(in: &cancellables)
        
        welcomeScheduler.$isWelcomePending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPending in
                if isPending {
                    self?.state = .welcomeCountdown
                } else if self?.state == .welcomeCountdown {
                    self?.state = .welcomeReady
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateState() {
        timer?.invalidate()
        pauseTimeoutTimer?.invalidate()
        
        // Check for welcome DayStart first
        if welcomeScheduler.isWelcomePending {
            state = .welcomeCountdown
            return
        }
        
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            logger.log("📅 No schedule found, showing no schedule message", level: .info)
            state = .idle
            showNoScheduleMessage = true
            nextDayStartTime = nil
            hasCompletedCurrentOccurrence = false
            isNextDayStartTomorrow = false
            isNextDayStartToday = false
            return
        }
        
        showNoScheduleMessage = false
        nextDayStartTime = nextOccurrence
        
        // Check if next DayStart is today or tomorrow
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!
        
        let nextOccurrenceDay = calendar.startOfDay(for: nextOccurrence)
        
        isNextDayStartToday = nextOccurrenceDay == today
        isNextDayStartTomorrow = nextOccurrenceDay == tomorrow
        
        
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
            startCountdown()
        } else {
            // More than 10 hours before OR more than 6 hours after - show next scheduled time
            if timeUntil < -sixHoursInSeconds {
            } else {
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
        stopPauseTimeoutTimer()
        
        // Cancel today's missed notification since user is now listening
        Task {
            await notificationScheduler.cancelTodaysMissedNotification()
            await notificationScheduler.cancelTodaysEveningReminder()
        }
        
        scheduleNextNotifications()
    }
    
    func startWelcomeDayStart() {
        logger.logUserAction("Start Welcome DayStart", details: ["time": Date().description])
        let dayStart = mockService.fetchDayStart(for: userPreferences.settings)
        
        var welcomeDayStart = dayStart
        welcomeDayStart.id = UUID() // Generate new UUID for welcome DayStart
        
        currentDayStart = welcomeDayStart
        userPreferences.addToHistory(welcomeDayStart)
        
        logger.logAudioEvent("Loading audio for Welcome DayStart")
        audioPlayer.loadAudio()
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
        
        welcomeScheduler.cancelWelcomeDayStart()
    }
    
    func replayDayStart(_ dayStart: DayStartData) {
        logger.logUserAction("Replay DayStart", details: ["id": dayStart.id])
        currentDayStart = dayStart
        audioPlayer.loadAudio()
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
    }
    
    private func transitionToRecentlyPlayed() {
        logger.log("✅ DayStart completed, transitioning to recently played", level: .info)
        
        // Update completion status for current occurrence
        if let scheduledTime = nextDayStartTime {
            hasCompletedCurrentOccurrence = hasCompletedOccurrence(scheduledTime)
        }
        
        state = .recentlyPlayed
        stopPauseTimeoutTimer()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.state == .recentlyPlayed {
                self?.updateState()
            }
        }
    }
    
    private func scheduleNotifications() {
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
    
    // MARK: - Pause Timeout Management
    private func startPauseTimeoutTimer() {
        stopPauseTimeoutTimer()
        
        // Check every 30 seconds if we should exit playing state due to time passing
        pauseTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIfShouldExitPlayingState()
        }
    }
    
    private func stopPauseTimeoutTimer() {
        pauseTimeoutTimer?.invalidate()
        pauseTimeoutTimer = nil
    }
    
    private func checkIfShouldExitPlayingState() {
        guard state == .playing, !audioPlayer.isPlaying else { return }
        
        // Check if we're still within a reasonable window to be in playing state
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            // No schedule - transition out of playing state
            logger.log("No schedule found while paused, exiting playing state", level: .info)
            audioPlayer.reset()
            updateState()
            return
        }
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        let sixHoursInSeconds: TimeInterval = 6 * 3600
        let tenHoursInSeconds: TimeInterval = 10 * 3600
        
        // If we're outside the normal "ready" window (more than 6 hours past scheduled time)
        // or if it's time for the next countdown/ready period, exit playing state
        if timeUntil < -sixHoursInSeconds {
            logger.log("Paused too long past scheduled time, transitioning to next state", level: .info)
            audioPlayer.reset()
            updateState()
        } else if timeUntil > 0 && timeUntil <= tenHoursInSeconds {
            // Next DayStart countdown should start
            logger.log("Time for next DayStart countdown, exiting playing state", level: .info)
            audioPlayer.reset()
            updateState()
        }
    }
}