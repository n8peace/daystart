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
        case audioLoading
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
    private var loadingDelayTimer: Timer?
    private var loadingTimeoutTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let userPreferences = UserPreferences.shared
    private let audioPlayer = AudioPlayerManager.shared
    private let notificationScheduler = NotificationScheduler.shared
    // Removed MockDataService - using bundled audio files instead
    private let welcomeScheduler = WelcomeDayStartScheduler.shared
    private let audioPrefetchManager = AudioPrefetchManager.shared
    private let audioCache = AudioCache.shared
    private let loadingMessages = LoadingMessagesService.shared
    
    // Debouncing
    private var updateStateWorkItem: DispatchWorkItem?
    
    // MARK: - Bundled Audio Helpers
    private func getSampleAudioPath(for voice: VoiceOption) -> String? {
        let fileName = "voice\(voice.rawValue + 1)_sample"
        return Bundle.main.path(forResource: fileName, ofType: "mp3", inDirectory: "Audio/Samples")
    }
    
    private func getFallbackAudioPath(for voice: VoiceOption) -> String? {
        let fileName = "voice\(voice.rawValue + 1)_fallback"
        return Bundle.main.path(forResource: fileName, ofType: "mp3", inDirectory: "Audio/Fallbacks")
    }
    
    private func generateBasicDayStart(for settings: UserSettings) -> DayStartData {
        return DayStartData(
            date: Date(),
            scheduledTime: nil,
            weather: "Weather information will be available when connected",
            news: ["News updates will be available when connected"],
            sports: ["Sports updates will be available when connected"],
            stocks: settings.stockSymbols.map { "\($0): Data unavailable offline" },
            quote: "Stay positive and have a great day!",
            customPrompt: "",
            transcript: "Welcome to your DayStart! Please connect to the internet for full content.",
            duration: Double(settings.dayStartLength * 60),
            audioFilePath: nil
        )
    }
    
    init() {
        logger.log("🏠 HomeViewModel initialized", level: .info)
        setupObservers()
        updateState()
        
        // New users start with empty history - no mock data needed
    }
    
    private func setupObservers() {
        userPreferences.$schedule
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateState()
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
    
    private func debouncedUpdateState() {
        // Cancel any pending update
        updateStateWorkItem?.cancel()
        
        // Schedule new update with 0.1s delay
        updateStateWorkItem = DispatchWorkItem { [weak self] in
            self?.updateState()
        }
        
        if let workItem = updateStateWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }
    }
    
    private func updateState() {
        logger.log("🎵 HomeViewModel: updateState() called", level: .debug)
        logger.log("🎵 HomeViewModel: Current state: \(state), currentDayStart: \(currentDayStart?.id.uuidString ?? "nil")", level: .debug)
        
        timer?.invalidate()
        pauseTimeoutTimer?.invalidate()
        stopLoadingTimers()
        
        // Check for welcome DayStart first
        if welcomeScheduler.isWelcomePending {
            logger.log("🎵 HomeViewModel: Welcome pending, setting state to .welcomeCountdown", level: .debug)
            state = .welcomeCountdown
            return
        }
        
        // Don't update state if currently playing audio (prevents interruption)
        if state == .playing {
            logger.log("🎵 HomeViewModel: Currently playing audio, skipping state update", level: .debug)
            return
        }
        
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            logger.log("📅 No schedule found, showing no schedule message", level: .info)
            // Batch all updates together
            withAnimation(.none) {
                state = .idle
                showNoScheduleMessage = true
                nextDayStartTime = nil
                hasCompletedCurrentOccurrence = false
                isNextDayStartTomorrow = false
                isNextDayStartToday = false
            }
            return
        }
        
        // Batch updates together
        withAnimation(.none) {
            showNoScheduleMessage = false
            nextDayStartTime = nextOccurrence
        }
        
        // Check if next DayStart is today or tomorrow
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!
        
        let nextOccurrenceDay = calendar.startOfDay(for: nextOccurrence)
        
        // Batch these related updates
        withAnimation(.none) {
            isNextDayStartToday = nextOccurrenceDay == today
            isNextDayStartTomorrow = nextOccurrenceDay == tomorrow
        }
        
        
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
        
        let newText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Only update if text actually changed (prevents unnecessary redraws)
        if newText != countdownText {
            countdownText = newText
        }
    }
    
    func startDayStart() {
        logger.logUserAction("Start DayStart", details: ["time": Date().description])
        
        Task {
            await startDayStartWithAudio()
        }
    }
    
    private func startDayStartWithAudio() async {
        let dayStart = generateBasicDayStart(for: userPreferences.settings)
        
        // Mark this occurrence with the scheduled time for tracking
        var dayStartWithScheduledTime = dayStart
        if let scheduledTime = nextDayStartTime {
            dayStartWithScheduledTime.scheduledTime = scheduledTime
        }
        
        currentDayStart = dayStartWithScheduledTime
        userPreferences.addToHistory(dayStartWithScheduledTime)
        
        guard let scheduledTime = nextDayStartTime else {
            // Fallback to bundled audio if no scheduled time
            await playFallbackAudio()
            return
        }
        
        // Check if audio is already cached locally
        if audioCache.hasAudio(for: scheduledTime) {
            logger.log("Audio already cached, playing from local file", level: .info)
            
            // Update history with cached audio path
            let audioPath = audioCache.getAudioPath(for: scheduledTime)
            userPreferences.updateHistory(
                with: dayStartWithScheduledTime.id,
                audioFilePath: audioPath.path
            )
            
            // Still fetch audio status to get transcript/duration if missing
            Task {
                do {
                    let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: scheduledTime)
                    if let transcript = audioStatus.transcript,
                       let duration = audioStatus.duration {
                        userPreferences.updateHistory(
                            with: dayStartWithScheduledTime.id,
                            transcript: transcript,
                            duration: TimeInterval(duration)
                        )
                    }
                } catch {
                    logger.logError(error, context: "Failed to fetch transcript/duration for cached audio")
                }
            }
            
            await playCachedAudio(for: scheduledTime)
        } else {
            // Stream from CDN while downloading in background
            do {
                let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: scheduledTime)
                
                if audioStatus.success && audioStatus.status == "ready", let audioUrl = audioStatus.audioUrl {
                    logger.log("Streaming audio from CDN: \(audioUrl.absoluteString)", level: .info)
                    
                    // Update history with transcript and duration from API
                    if let transcript = audioStatus.transcript, 
                       let duration = audioStatus.duration {
                        userPreferences.updateHistory(
                            with: dayStartWithScheduledTime.id,
                            transcript: transcript,
                            duration: TimeInterval(duration)
                        )
                    }
                    
                    // Stream immediately
                    await streamAudio(from: audioUrl)
                    
                    // Download in background for future replays (no user waiting)
                    let dayStartId = dayStartWithScheduledTime.id
                    Task.detached {
                        let success = await AudioDownloader.shared.download(from: audioUrl, for: scheduledTime)
                        if success {
                            DebugLogger.shared.log("Background download completed for \(scheduledTime)", level: .info)
                            
                            // Update history with cached audio path
                            await MainActor.run {
                                let audioPath = AudioCache.shared.getAudioPath(for: scheduledTime)
                                UserPreferences.shared.updateHistory(
                                    with: dayStartId,
                                    audioFilePath: audioPath.path
                                )
                            }
                        }
                    }
                } else {
                    // Audio not ready, create job and fall back to mock
                    logger.log("Audio not ready (status: \(audioStatus.status)), falling back to mock", level: .warning)
                    
                    // Create job for future
                    try? await SupabaseClient.shared.createJob(
                        for: scheduledTime,
                        with: userPreferences.settings,
                        schedule: userPreferences.schedule
                    )
                    
                    await playFallbackAudio()
                }
            } catch {
                logger.logError(error, context: "Failed to check audio status")
                await playFallbackAudio()
            }
        }
    }
    
    private func playCachedAudio(for date: Date) async {
        let audioUrl = audioCache.getAudioPath(for: date)
        
        logger.logAudioEvent("Loading cached audio for DayStart")
        audioPlayer.loadAudio(from: audioUrl)
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
        
        await cancelTodaysNotifications()
        scheduleNextNotifications()
    }
    
    private func streamAudio(from url: URL) async {
        logger.logAudioEvent("Starting smart audio loading from CDN")
        
        // Start loading delay timer - if audio doesn't load within 1 second, show loading screen
        startLoadingDelayTimer()
        
        // Start timeout timer - if audio doesn't load within 30 seconds, fall back to mock
        startLoadingTimeoutTimer()
        
        // Load audio with completion callback
        audioPlayer.loadAudio(from: url) { [weak self] success, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Stop all loading timers
                self.stopLoadingTimers()
                
                if success {
                    self.logger.logAudioEvent("Audio loaded successfully, starting playback")
                    self.audioPlayer.play()
                    self.state = .playing
                    self.stopPauseTimeoutTimer()
                    
                    await self.cancelTodaysNotifications()
                    self.scheduleNextNotifications()
                } else {
                    if let error = error {
                        self.logger.logError(error, context: "Smart audio loading failed")
                        
                        // Check if this is an expired URL error
                        if (error as NSError).code == 403 {
                            self.logger.log("CDN URL expired (403), attempting to refresh", level: .warning)
                            await self.handleExpiredUrl(originalUrl: url)
                            return
                        }
                    }
                    
                    self.logger.log("Audio loading failed, falling back to fallback audio", level: .warning)
                    await self.playFallbackAudio()
                }
            }
        }
    }
    
    private func startLoadingDelayTimer() {
        stopLoadingTimers()
        
        loadingDelayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Only show loading screen if we're not already playing
                if self.state != .playing {
                    self.logger.log("Audio taking longer than 1s, showing loading screen", level: .info)
                    self.state = .audioLoading
                    self.loadingMessages.startRotatingMessages()
                }
            }
        }
    }
    
    private func startLoadingTimeoutTimer() {
        loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                self.logger.log("Audio loading timeout after 30s, falling back to fallback audio", level: .warning)
                self.stopLoadingTimers()
                await self.playFallbackAudio()
            }
        }
    }
    
    private func stopLoadingTimers() {
        loadingDelayTimer?.invalidate()
        loadingDelayTimer = nil
        
        loadingTimeoutTimer?.invalidate()
        loadingTimeoutTimer = nil
        
        loadingMessages.stopRotatingMessages()
    }
    
    private func handleExpiredUrl(originalUrl: URL) async {
        guard let scheduledTime = nextDayStartTime else {
            await playFallbackAudio()
            return
        }
        
        do {
            // Re-fetch audio status to get fresh signed URL
            let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: scheduledTime)
            
            if audioStatus.success && audioStatus.status == "ready", let freshUrl = audioStatus.audioUrl {
                logger.log("Successfully refreshed signed URL", level: .info)
                // Recursive call with fresh URL (avoid infinite loops by checking if URL changed)
                if freshUrl.absoluteString != originalUrl.absoluteString {
                    await streamAudio(from: freshUrl)
                } else {
                    logger.logError(NSError(domain: "URLRefresh", code: 1), context: "Refreshed URL is same as expired URL")
                    await playFallbackAudio()
                }
            } else {
                logger.log("Audio not ready after URL refresh, falling back to mock", level: .warning)
                await playFallbackAudio()
            }
        } catch {
            logger.logError(error, context: "Failed to refresh expired URL")
            await playFallbackAudio()
        }
    }
    
    private func playFallbackAudio() async {
        logger.logAudioEvent("Loading fallback audio for DayStart")
        logger.log("[DEBUG] User's selected voice: \(userPreferences.settings.selectedVoice.name)", level: .debug)
        
        let selectedVoice = userPreferences.settings.selectedVoice
        
        if let fallbackPath = getFallbackAudioPath(for: selectedVoice),
           let audioUrl = URL(string: "file://\(fallbackPath)") {
            logger.log("Loading fallback audio from: \(fallbackPath)", level: .info)
            audioPlayer.loadAudio(from: audioUrl)
        } else {
            // Ultimate fallback - use the old method if bundled files aren't found
            logger.log("Bundled fallback audio not found, using AudioPlayerManager default", level: .warning)
            audioPlayer.loadAudio()
        }
        
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
        
        await cancelTodaysNotifications()
        
        // Delay scheduling to prevent immediate observer-triggered state change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.scheduleNextNotifications()
        }
    }
    
    private func cancelTodaysNotifications() async {
        await notificationScheduler.cancelTodaysMissedNotification()
        await notificationScheduler.cancelTodaysEveningReminder()
    }
    
    func startWelcomeDayStart() {
        logger.logUserAction("Start Welcome DayStart", details: ["time": Date().description])
        
        Task {
            await startWelcomeDayStartWithSupabase()
        }
    }
    
    private func startWelcomeDayStartWithSupabase() async {
        let dayStart = generateBasicDayStart(for: userPreferences.settings)
        
        var welcomeDayStart = dayStart
        welcomeDayStart.id = UUID() // Generate new UUID for welcome DayStart
        welcomeDayStart.scheduledTime = Date() // Use current time as scheduled time
        
        currentDayStart = welcomeDayStart
        userPreferences.addToHistory(welcomeDayStart)
        
        // Try to use Supabase for welcome DayStart
        do {
            // Check if audio exists (should have been created during onboarding)
            // Use the same local date calculation as createJob to ensure consistency
            let localDate: Date = {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                let localDateString = formatter.string(from: Date())
                formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
                return formatter.date(from: localDateString) ?? Date()
            }()
            let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: localDate)
            
            if audioStatus.success && audioStatus.status == "ready", let audioUrl = audioStatus.audioUrl {
                logger.log("✅ Welcome DayStart audio ready from Supabase, streaming...", level: .info)
                
                // Update history with transcript and duration from API
                if let transcript = audioStatus.transcript,
                   let duration = audioStatus.duration {
                    userPreferences.updateHistory(
                        with: welcomeDayStart.id,
                        transcript: transcript,
                        duration: TimeInterval(duration)
                    )
                }
                
                await streamAudio(from: audioUrl)
                
                // Download in background for future replays
                let welcomeId = welcomeDayStart.id
                Task.detached {
                    let success = await AudioDownloader.shared.download(from: audioUrl, for: localDate)
                    if success {
                        DebugLogger.shared.log("Welcome audio downloaded for caching", level: .info)
                        
                        // Update history with cached audio path
                        await MainActor.run {
                            let audioPath = AudioCache.shared.getAudioPath(for: localDate)
                            UserPreferences.shared.updateHistory(
                                with: welcomeId,
                                audioFilePath: audioPath.path
                            )
                        }
                    }
                }
            } else if audioStatus.status == "processing" {
                // Audio still processing, show status
                logger.log("⏳ Welcome DayStart audio still processing (status: \(audioStatus.status))", level: .info)
                await playFallbackAudio()
            } else {
                // Something went wrong, fall back to mock
                logger.log("⚠️ Welcome DayStart audio not ready (status: \(audioStatus.status)), using mock", level: .warning)
                await playFallbackAudio()
            }
        } catch {
            // Supabase failed, fall back to mock audio
            logger.logError(error, context: "Welcome DayStart Supabase failed, using mock audio")
            await playFallbackAudio()
        }
        
        welcomeScheduler.cancelWelcomeDayStart()
    }
    
    func replayDayStart(_ dayStart: DayStartData) {
        logger.logUserAction("Replay DayStart", details: ["id": dayStart.id])
        logger.log("🎵 HomeViewModel: replayDayStart called for \(dayStart.id)", level: .info)
        logger.log("🎵 HomeViewModel: Setting currentDayStart to \(dayStart.id)", level: .info)
        logger.log("🎵 HomeViewModel: Current state before replay: \(state)", level: .info)
        
        currentDayStart = dayStart
        
        Task {
            logger.log("🎵 HomeViewModel: Starting async audio replay", level: .info)
            await replayDayStartWithAudio(dayStart)
        }
    }
    
    private func replayDayStartWithAudio(_ dayStart: DayStartData) async {
        logger.log("🎵 HomeViewModel: replayDayStartWithAudio started", level: .info)
        
        // Check if we have cached audio for this DayStart
        if let scheduledTime = dayStart.scheduledTime,
           audioCache.hasAudio(for: scheduledTime) {
            let audioUrl = audioCache.getAudioPath(for: scheduledTime)
            logger.logAudioEvent("Loading cached audio for replay")
            logger.log("🎵 HomeViewModel: Loading cached audio from \(audioUrl)", level: .info)
            audioPlayer.loadAudio(from: audioUrl)
        } else {
            // Fall back to bundled fallback audio for replay
            logger.logAudioEvent("Loading fallback audio for replay")
            logger.log("🎵 HomeViewModel: No cached audio, loading fallback audio", level: .info)
            
            let selectedVoice = userPreferences.settings.selectedVoice
            if let fallbackPath = getFallbackAudioPath(for: selectedVoice),
               let audioUrl = URL(string: "file://\(fallbackPath)") {
                logger.log("Loading fallback audio from: \(fallbackPath)", level: .info)
                audioPlayer.loadAudio(from: audioUrl)
            } else {
                // Ultimate fallback
                logger.log("Bundled fallback audio not found, using AudioPlayerManager default", level: .warning)
                audioPlayer.loadAudio()
            }
        }
        
        logger.log("🎵 HomeViewModel: Calling audioPlayer.play()", level: .info)
        audioPlayer.play()
        
        logger.log("🎵 HomeViewModel: Setting state to .playing", level: .info)
        state = .playing
        
        logger.log("🎵 HomeViewModel: Stopping pause timeout timer", level: .info)
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