import Foundation
import Combine
import UserNotifications

class WelcomeDayStartScheduler: ObservableObject {
    static let shared = WelcomeDayStartScheduler()
    
    @Published var isWelcomePending = false
    @Published var welcomeCountdownText = ""
    
    private var welcomeTimer: Timer?
    private var audioStatusTimer: Timer?
    private var hasNotifiedReady = false
    private let logger = DebugLogger.shared
    
    private init() {}
    
    func scheduleWelcomeDayStart() {
        guard !isWelcomePending else {
            logger.log("🎉 Welcome DayStart already scheduled", level: .info)
            return
        }
        
        logger.log("🎉 Scheduling welcome DayStart in 5 minutes", level: .info)
        isWelcomePending = true
        
        let welcomeTime = Date().addingTimeInterval(5 * 60) // 5 minutes
        
        // Initialize countdown text immediately
        updateWelcomeCountdown(timeInterval: welcomeTime.timeIntervalSinceNow)
        
        startWelcomeCountdown(to: welcomeTime)
        
        // Start checking audio status after 3 minutes
        let pollStartTime = Date().addingTimeInterval(3 * 60)
        startAudioStatusPolling(startTime: pollStartTime)
    }
    
    private func startWelcomeCountdown(to targetTime: Date) {
        welcomeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeUntil = targetTime.timeIntervalSinceNow
            
            DispatchQueue.main.async {
                if timeUntil <= 0 {
                    self.welcomeTimer?.invalidate()
                    self.isWelcomePending = false
                    self.logger.log("🎉 Welcome DayStart countdown complete!", level: .info)
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
        audioStatusTimer?.invalidate()
        isWelcomePending = false
        welcomeCountdownText = ""
        hasNotifiedReady = false
    }
    
    private func startAudioStatusPolling(startTime: Date) {
        let delay = startTime.timeIntervalSinceNow
        if delay > 0 {
            // Wait until start time
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.beginPolling()
            }
        } else {
            // Start immediately if start time has passed
            beginPolling()
        }
    }
    
    private func beginPolling() {
        logger.log("📊 Starting audio status polling for welcome DayStart", level: .info)
        
        // Poll every 30 seconds
        audioStatusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.checkAudioStatus()
            }
        }
        
        // Check immediately
        Task { [weak self] in
            await self?.checkAudioStatus()
        }
    }
    
    private func checkAudioStatus() async {
        guard !hasNotifiedReady else { return }
        
        do {
            // Get current date for the job
            let localDate: Date = {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                let localDateString = formatter.string(from: Date())
                return formatter.date(from: localDateString) ?? Date()
            }()
            
            let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: localDate)
            
            if audioStatus.success && audioStatus.status == "ready" {
                logger.log("✅ Welcome DayStart audio is ready!", level: .info)
                
                // Stop polling
                await MainActor.run {
                    self.audioStatusTimer?.invalidate()
                    self.audioStatusTimer = nil
                }
                
                // Send notification
                await sendReadyNotification()
                hasNotifiedReady = true
            } else {
                logger.log("⏳ Welcome DayStart audio status: \(audioStatus.status ?? "unknown")", level: .debug)
            }
        } catch {
            logger.logError(error, context: "Failed to check welcome DayStart audio status")
        }
    }
    
    private func sendReadyNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "🎉 Your Welcome DayStart is Ready!"
        content.body = "Tap to start your personalized briefing"
        content.sound = .default
        content.categoryIdentifier = "DAYSTART_READY"
        
        // Create a unique identifier
        let identifier = "welcome-daystart-ready-\(Date().timeIntervalSince1970)"
        
        // Deliver immediately
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.log("📬 Welcome DayStart ready notification sent", level: .info)
        } catch {
            logger.logError(error, context: "Failed to send welcome DayStart ready notification")
        }
    }
}