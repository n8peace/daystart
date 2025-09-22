import Foundation
import Combine
import UserNotifications
import AVFoundation

class WelcomeDayStartScheduler: ObservableObject {
    static let shared = WelcomeDayStartScheduler()
    
    @Published var isWelcomePending = false
    @Published var welcomeCountdownText = ""
    @Published var initializationProgress: String = ""
    @Published var initializationStep: Int = 0
    @Published var totalInitializationSteps: Int = 7
    @Published var isWelcomeReadyToPlay = false
    
    private var welcomeTimer: Timer?
    private var audioStatusTimer: Timer?
    private var hasNotifiedReady = false
    private var isAudioReady = false
    private var hasCountdownCompleted = false
    private let logger = DebugLogger.shared
    
    private init() {}
    
    func scheduleWelcomeDayStart() {
        guard !isWelcomePending else {
            logger.log("🎉 Welcome DayStart already scheduled", level: .info)
            return
        }
        
        logger.log("🎉 PHASE 4: Welcome DayStart ready instantly with background preparation", level: .info)
        
        // Set pending state immediately to show preparing view
        isWelcomePending = true
        logger.log("⏳ Welcome DayStart preparation started", level: .info)
        
        // PHASE 4: Make welcome instantly available, prepare content in background
        Task {
            await performDeferredInitialization()
            
            // After initialization, mark as ready immediately
            await MainActor.run {
                self.isWelcomeReadyToPlay = true
                self.isWelcomePending = false
                logger.log("✅ Welcome DayStart ready to play immediately", level: .info)
            }
            
            // Background: Prepare real content for future use
            await prepareWelcomeContentInBackground()
        }
    }
    
    private func startWelcomeCountdown(to targetTime: Date) {
        welcomeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeUntil = targetTime.timeIntervalSinceNow
            
            DispatchQueue.main.async {
                if timeUntil <= 0 {
                    self.welcomeTimer?.invalidate()
                    self.hasCountdownCompleted = true
                    self.logger.log("🎉 Welcome DayStart countdown complete!", level: .info)
                    self.checkIfReadyToShow()
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
        isAudioReady = false
        hasCountdownCompleted = false
        isWelcomeReadyToPlay = false
    }
    
    func stopAudioPolling() {
        logger.log("🛑 Stopping audio polling for welcome DayStart", level: .info)
        audioStatusTimer?.invalidate()
        audioStatusTimer = nil
    }
    
    private func checkIfReadyToShow() {
        logger.log("🔍 Checking if welcome ready to show: countdown=\(hasCountdownCompleted), audio=\(isAudioReady)", level: .debug)
        
        // Only show as ready when BOTH countdown is complete AND audio is ready
        if hasCountdownCompleted && isAudioReady {
            logger.log("✅ Welcome DayStart is ready to play! Transitioning to ready state.", level: .info)
            DispatchQueue.main.async {
                self.isWelcomePending = false
                self.isWelcomeReadyToPlay = true
                self.logger.log("🔄 Published state change: isWelcomePending=false, isWelcomeReadyToPlay=true", level: .debug)
            }
        } else {
            logger.log("⏳ Not ready yet: countdown=\(hasCountdownCompleted), audio=\(isAudioReady)", level: .debug)
        }
    }
    
    func startAudioPollingImmediately() {
        logger.log("🔍 Starting immediate audio polling for welcome DayStart", level: .info)
        beginPolling()
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
        
        // Poll every 10 seconds (consistent with regular DayStarts)
        audioStatusTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
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
            // Use canonical local date normalization via SupabaseClient
            let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: Date())
            
            if audioStatus.success && audioStatus.status == "ready" {
                logger.log("✅ Welcome DayStart audio is ready!", level: .info)
                
                // Stop polling
                await MainActor.run {
                    self.audioStatusTimer?.invalidate()
                    self.audioStatusTimer = nil
                    self.isAudioReady = true
                    self.checkIfReadyToShow()
                }
                
                // Send notification
                await sendReadyNotification()
                hasNotifiedReady = true
            } else if audioStatus.success && audioStatus.status == "queued", let jobId = audioStatus.jobId {
                logger.log("🚀 Welcome DayStart is queued, triggering immediate processing for job: \(jobId)", level: .info)
                
                // Trigger immediate processing
                do {
                    try await SupabaseClient.shared.invokeProcessJob(jobId: jobId)
                    logger.log("✅ Successfully triggered processing for welcome job: \(jobId)", level: .info)
                } catch {
                    logger.logError(error, context: "Failed to trigger processing for welcome job: \(jobId)")
                    // Continue polling normally if trigger fails
                }
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
    
    private func performDeferredInitialization() async {
        logger.log("🎆 Starting deferred initialization during countdown", level: .info)
        
        // PHASE 3: Service warmup integration
        await updateInitializationProgress("Warming up services...", step: 1)
        Task.detached {
            await AudioPrefetchManager.shared.checkForUpcomingDayStarts()
            _ = await LocationManager.shared.getCurrentLocation() // Pre-warm location
        }
        
        // Initialize AudioPlayerManager (now in background to prevent blocking)
        await updateInitializationProgress("Preparing audio system...", step: 2)
        Task.detached {
            _ = AudioPlayerManager.shared
            await DebugLogger.shared.log("✅ AudioPlayerManager initialized", level: .info)
        }
        
        // Initialize other services (now in background to prevent blocking)
        await updateInitializationProgress("Setting up notification system...", step: 3)
        Task.detached {
            _ = NotificationScheduler.shared
            _ = AudioPrefetchManager.shared
            _ = AudioCache.shared
            await DebugLogger.shared.log("✅ Notification and audio services initialized", level: .info)
        }
        
        // Configure audio session
        await updateInitializationProgress("Configuring audio settings...", step: 4)
        await configureAudioSessionAsync()
        
        // Request permissions
        await updateInitializationProgress("Requesting permissions...", step: 5)
        await requestPermissionsAsync()
        
        // Background tasks are already registered in AppDelegate
        await updateInitializationProgress("Setting up background tasks...", step: 6)
        await MainActor.run {
            logger.log("✅ Background tasks already registered in AppDelegate", level: .info)
        }
        
        // Start pre-creating today's audio
        await updateInitializationProgress("Creating your personalized content...", step: 7)
        Task {
            await prefetchTodaysAudio()
        }
    }
    
    private func updateInitializationProgress(_ message: String, step: Int) async {
        await MainActor.run {
            self.initializationProgress = message
            self.initializationStep = step
            logger.log("📦 Initialization progress: \(message) (\(step)/\(totalInitializationSteps))", level: .debug)
        }
    }
    
    private func configureAudioSessionAsync() async {
        await MainActor.run {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: []
                )
                try audioSession.setPreferredSampleRate(44100.0)
                try audioSession.setPreferredIOBufferDuration(256.0 / 44100.0)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                logger.log("✅ Audio session configured during countdown", level: .info)
            } catch {
                logger.logError(error, context: "Failed to configure audio session during countdown")
            }
        }
    }
    
    private func requestPermissionsAsync() async {
        // Request notification permissions
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            logger.log("🔔 Notification permissions: \(granted ? "granted" : "denied")", level: .info)
        } catch {
            logger.logError(error, context: "Failed to request notification permissions")
        }
        
        // Request location permissions if weather is enabled
        let settings = await UserPreferences.shared.settings
        if settings.includeWeather {
            _ = await LocationManager.shared.requestLocationPermission()
            logger.log("📍 Location permission requested", level: .info)
        }
    }
    
    private func prefetchTodaysAudio() async {
        logger.log("📦 Pre-creating today's audio during countdown", level: .info)
        
        // Skip if we're in the onboarding flow - job is already created there
        if UserDefaults.standard.bool(forKey: "shouldAutoStartWelcome") {
            logger.log("⏭️ Skipping prefetch - welcome job already created in onboarding", level: .info)
            return
        }
        
        let localDate = Date()
        let scheduler = await UserPreferences.shared.schedule
        let settings = await UserPreferences.shared.settings
        
        do {
            // Build snapshot for context
            let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: localDate)
            
            // Create job for today
            _ = try await SupabaseClient.shared.createJob(
                for: localDate,
                with: settings,
                schedule: scheduler,
                locationData: snapshot.location,
                weatherData: snapshot.weather,
                calendarEvents: snapshot.calendar,
                isWelcome: true
            )
            
            logger.log("✅ Today's audio job created during countdown", level: .info)
        } catch {
            logger.logError(error, context: "Failed to create audio job during countdown")
        }
    }
    
    // PHASE 4: Background content preparation without blocking user
    private func prepareWelcomeContentInBackground() async {
        logger.log("📦 Preparing welcome content in background", level: .info)
        
        // Skip if we're in the onboarding flow - job is already created there
        if UserDefaults.standard.bool(forKey: "shouldAutoStartWelcome") {
            logger.log("⏭️ Skipping background prep - welcome job already created in onboarding", level: .info)
            return
        }
        
        let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: Date())
        
        do {
            _ = try await SupabaseClient.shared.createJob(
                for: Date(),
                with: UserPreferences.shared.settings,
                schedule: UserPreferences.shared.schedule,
                locationData: snapshot.location,
                weatherData: snapshot.weather,
                calendarEvents: snapshot.calendar,
                isWelcome: true
            )
            logger.log("✅ Welcome content prepared in background", level: .info)
        } catch {
            logger.logError(error, context: "Background welcome content creation failed")
        }
    }
}