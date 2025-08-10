import Foundation
import Combine

class WelcomeDayStartScheduler: ObservableObject {
    static let shared = WelcomeDayStartScheduler()
    
    @Published var isWelcomePending = false
    @Published var welcomeCountdownText = ""
    
    private var welcomeTimer: Timer?
    private let logger = DebugLogger.shared
    
    private init() {}
    
    func scheduleWelcomeDayStart() {
        guard !isWelcomePending else {
            logger.log("🎉 Welcome DayStart already scheduled", level: .info)
            return
        }
        
        logger.log("🎉 Scheduling welcome DayStart in 10 minutes", level: .info)
        isWelcomePending = true
        
        let welcomeTime = Date().addingTimeInterval(10 * 60) // 10 minutes
        
        // Initialize countdown text immediately
        updateWelcomeCountdown(timeInterval: welcomeTime.timeIntervalSinceNow)
        
        startWelcomeCountdown(to: welcomeTime)
    }
    
    private func startWelcomeCountdown(to targetTime: Date) {
        welcomeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeUntil = targetTime.timeIntervalSinceNow
            
            DispatchQueue.main.async {
                if timeUntil <= 0 {
                    self.welcomeTimer?.invalidate()
                    self.isWelcomePending = false
                    self.logger.log("🎉 Welcome DayStart is ready!", level: .info)
                } else {
                    self.updateWelcomeCountdown(timeInterval: timeUntil)
                }
            }
        }
    }
    
    private func updateWelcomeCountdown(timeInterval: TimeInterval) {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        welcomeCountdownText = String(format: "%02d:%02d", minutes, seconds)
    }
    
    func cancelWelcomeDayStart() {
        logger.log("🎉 Cancelling welcome DayStart", level: .info)
        welcomeTimer?.invalidate()
        isWelcomePending = false
        welcomeCountdownText = ""
    }
}