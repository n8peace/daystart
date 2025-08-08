import Foundation
import SwiftUI
import Combine

class HomeViewModel: ObservableObject {
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
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let userPreferences = UserPreferences.shared
    private let audioPlayer = AudioPlayerManager.shared
    private let notificationScheduler = NotificationScheduler.shared
    private let mockService = MockDataService.shared
    
    init() {
        setupObservers()
        updateState()
        
        if userPreferences.history.isEmpty {
            userPreferences.history = mockService.generateMockHistory()
        }
    }
    
    private func setupObservers() {
        userPreferences.$schedule
            .sink { [weak self] _ in
                self?.updateState()
                self?.scheduleNotifications()
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
        
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            state = .idle
            showNoScheduleMessage = true
            nextDayStartTime = nil
            return
        }
        
        showNoScheduleMessage = false
        nextDayStartTime = nextOccurrence
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        
        if timeUntil <= 0 {
            state = .ready
        } else if timeUntil > 36000 {
            state = .idle
        } else {
            startCountdown()
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
        let dayStart = mockService.fetchDayStart(for: userPreferences.settings)
        currentDayStart = dayStart
        userPreferences.addToHistory(dayStart)
        
        audioPlayer.loadAudio()
        audioPlayer.play()
        state = .playing
        
        scheduleNextNotifications()
    }
    
    func replayDayStart(_ dayStart: DayStartData) {
        currentDayStart = dayStart
        audioPlayer.loadAudio()
        audioPlayer.play()
        state = .playing
    }
    
    private func transitionToRecentlyPlayed() {
        state = .recentlyPlayed
        
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
}