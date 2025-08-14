import Foundation
import SwiftUI
import Combine

class HomeViewModel: ObservableObject {
    private let logger = DebugLogger.shared
    
    // PHASE 3: State update priority system
    enum StateUpdatePriority {
        case immediate    // User actions: startDayStart(), button taps
        case coalesced   // Background: schedule changes, observers
    }
    
    enum AppState {
        case idle            // Default state, no scheduled DayStart nearby
        case welcomeCountdown
        case welcomeReady
        case countdown       // 0-10 hours before scheduled time
        case ready          // Ready to play (includes welcome)
        case playing        // Currently playing (includes loading)
        case completed      // Completed (replay available)
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
    // Lazy initialization for heavy services
    private var audioPlayer: AudioPlayerManager?
    private var notificationScheduler: NotificationScheduler?
    // Removed MockDataService - using bundled audio files instead
    private let welcomeScheduler = WelcomeDayStartScheduler.shared
    private var audioPrefetchManager: AudioPrefetchManager?
    private var audioCache: AudioCache?
    private let loadingMessages = LoadingMessagesService.shared
    
    // Track initialization state
    private var isFullyInitialized = false
    private let lazyInit: Bool
    
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
    
    init(lazyInit: Bool = false) {
        self.lazyInit = lazyInit
        logger.log("🏠 HomeViewModel initialized (lazy: \(lazyInit))", level: .info)
        
        if !lazyInit {
            // Normal initialization for existing flows
            initializeServices()
        }
        // For lazy init, services will be initialized during countdown
        
        // Don't setup observers or update state on init - wait for view to appear
    }
    
    func onViewAppear() {
        // Initialize on first view appearance
        if !isFullyInitialized && lazyInit {
            setupObservers()
            updateState()
        } else if isFullyInitialized {
            // Just update state if already initialized
            updateState()
        }
    }
    
    func onViewDisappear() {
        // Clean up timers when view disappears
        timer?.invalidate()
        timer = nil
        pauseTimeoutTimer?.invalidate()
        pauseTimeoutTimer = nil
        stopLoadingTimers()
    }
    
    private func initializeServices() {
        guard !isFullyInitialized else { return }
        
        logger.log("🎵 Initializing audio and notification services", level: .info)
        audioPlayer = AudioPlayerManager.shared
        notificationScheduler = NotificationScheduler.shared
        audioPrefetchManager = AudioPrefetchManager.shared
        audioCache = AudioCache.shared
        isFullyInitialized = true
        
        // Re-setup observers that depend on these services
        setupAudioObservers()
    }
    
    // Ensure services are initialized before use
    private func ensureServicesInitialized() {
        if !isFullyInitialized {
            initializeServices()
        }
    }
    
    private var requireAudioPlayer: AudioPlayerManager {
        ensureServicesInitialized()
        return audioPlayer!
    }
    
    private var requireNotificationScheduler: NotificationScheduler {
        ensureServicesInitialized()
        return notificationScheduler!
    }
    
    private var requireAudioCache: AudioCache {
        ensureServicesInitialized()
        return audioCache!
    }
    
    private func setupObservers() {
        // Only observe schedule changes after initial load
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.userPreferences.$schedule
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.debouncedUpdateState()
                    self?.scheduleNotifications()
                }
                .store(in: &self.cancellables)
        }
        
        userPreferences.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Force UI update when settings change - defer to avoid publishing during view updates
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        // Welcome scheduler observers
        welcomeScheduler.$isWelcomePending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateState()
            }
            .store(in: &cancellables)
        
        welcomeScheduler.$isWelcomeReadyToPlay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateState()
            }
            .store(in: &cancellables)
        
        // Audio observers will be set up after services are initialized
        if isFullyInitialized {
            setupAudioObservers()
        }
    }
    
    private func setupAudioObservers() {
        guard let audioPlayer = audioPlayer else { return }
        
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
    
    // PHASE 3: Coalesced state updates - no artificial delays for user actions
    private func updateState(priority: StateUpdatePriority = .coalesced) {
        switch priority {
        case .immediate:
            // Direct update for user interactions - no delay
            performStateUpdate()
        case .coalesced:
            // Coalesce background updates to next runloop to prevent thrashing
            coalescedUpdateState()
        }
    }
    
    private func coalescedUpdateState() {
        // Cancel any pending update
        updateStateWorkItem?.cancel()
        
        // Schedule for next runloop instead of 100ms delay
        updateStateWorkItem = DispatchWorkItem { [weak self] in
            self?.performStateUpdate()
        }
        
        if let workItem = updateStateWorkItem {
            DispatchQueue.main.async(execute: workItem)
        }
    }
    
    private func debouncedUpdateState() {
        // PHASE 3: Redirect old calls to coalesced updates
        updateState(priority: .coalesced)
    }
    
    private func performStateUpdate() {
        logger.log("🎵 HomeViewModel: updateState() called", level: .debug)
        logger.log("🎵 HomeViewModel: Current state: \(state), currentDayStart: \(currentDayStart?.id.uuidString ?? "nil")", level: .debug)
        logger.log("🎵 HomeViewModel: Welcome pending: \(welcomeScheduler.isWelcomePending), ready: \(welcomeScheduler.isWelcomeReadyToPlay)", level: .debug)
        
        timer?.invalidate()
        pauseTimeoutTimer?.invalidate()
        stopLoadingTimers()
        
        // Check for welcome DayStart first
        if welcomeScheduler.isWelcomePending {
            logger.log("🎵 HomeViewModel: Welcome pending, setting state to .welcomeCountdown", level: .debug)
            state = .welcomeCountdown
            return
        }
        
        // Check if welcome DayStart is ready to play
        if welcomeScheduler.isWelcomeReadyToPlay {
            logger.log("🎵 HomeViewModel: Welcome ready to play, setting state to .welcomeReady", level: .debug)
            state = .welcomeReady
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
        // dayAfterTomorrow not needed - removed to fix unused variable warning
        
        let nextOccurrenceDay = calendar.startOfDay(for: nextOccurrence)
        
        // Batch these related updates
        withAnimation(.none) {
            isNextDayStartToday = nextOccurrenceDay == today
            isNextDayStartTomorrow = nextOccurrenceDay == tomorrow
        }
        
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        let sixHoursInSeconds: TimeInterval = 6 * 3600 // 6 hours
        let tenHoursInSeconds: TimeInterval = 10 * 3600 // 10 hours
        
        // Check if THIS occurrence has been completed
        let hasCompletedThisOccurrence = hasCompletedOccurrence(nextOccurrence)
        hasCompletedCurrentOccurrence = hasCompletedThisOccurrence
        
        // Apply the enhanced 4-state rules
        
        // COUNTDOWN: Next DayStart is 0-10 hours away
        if timeUntil > 0 && timeUntil <= tenHoursInSeconds {
            logger.log("⏰ Countdown state: \(Int(timeUntil))s until scheduled time", level: .info)
            startCountdown()
        }
        // READY: Within 6-hour window AND haven't completed THIS occurrence
        else if timeUntil <= 0 && timeUntil >= -sixHoursInSeconds && !hasCompletedThisOccurrence {
            logger.log("⏰ Ready state: Within window and not completed", level: .info)
            state = .ready
        }
        // COMPLETED: Finished THIS occurrence, still in 6-hour window
        else if hasCompletedThisOccurrence && timeUntil >= -sixHoursInSeconds {
            logger.log("⏰ Completed state: Done with this occurrence", level: .info)
            state = .completed
        }
        // IDLE: Everything else
        else {
            logger.log("⏰ Idle state: Outside all windows", level: .info)
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
        
        // PHASE 3: Immediate state change for button responsiveness
        state = .playing  // Playing state includes loading
        
        // Ensure services are initialized before starting
        ensureServicesInitialized()
        
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
        if requireAudioCache.hasAudio(for: scheduledTime) {
            logger.log("Audio already cached, playing from local file", level: .info)
            
            // Update history with cached audio path
            let audioPath = requireAudioCache.getAudioPath(for: scheduledTime)
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
                            await DebugLogger.shared.log("Background download completed for \(scheduledTime)", level: .info)
                            
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
                    // Audio not ready, create job (only if not processing/ready) with snapshot, then fall back to mock
                    logger.log("Audio not ready (status: \(audioStatus.status)), falling back to mock", level: .warning)
                    
                    if audioStatus.status == "not_found" || audioStatus.status == "failed" || audioStatus.status == "queued" {
                        let snapshot = await SnapshotBuilder.shared.buildSnapshot()
                        _ = try? await SupabaseClient.shared.createJob(
                            for: scheduledTime,
                            with: userPreferences.settings,
                            schedule: userPreferences.schedule,
                            locationData: snapshot.location,
                            weatherData: snapshot.weather,
                            calendarEvents: snapshot.calendar
                        )
                    }
                    
                    await playFallbackAudio()
                }
            } catch {
                logger.logError(error, context: "Failed to check audio status")
                await playFallbackAudio()
            }
        }
    }
    
    private func playCachedAudio(for date: Date) async {
        logger.logAudioEvent("Loading cached audio for DayStart")
        
        // PHASE 4: Try preloaded player item first for instant start
        if requireAudioPlayer.loadAudioInstantly(for: date) {
            logger.log("🚀 Using preloaded audio item for instant playback", level: .info)
        } else {
            // Fallback to regular cached audio loading
            let audioUrl = requireAudioCache.getAudioPath(for: date)
            requireAudioPlayer.loadAudio(from: audioUrl)
        }
        
        requireAudioPlayer.play()
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
        requireAudioPlayer.loadAudio(from: url) { [weak self] success, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Stop all loading timers
                self.stopLoadingTimers()
                
                if success {
                    self.logger.logAudioEvent("Audio loaded successfully, starting playback")
                    self.requireAudioPlayer.play()
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
        
        loadingDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Only start loading messages if we're in playing state
                if self.state == .playing {
                    self.logger.log("Audio taking longer than 200ms, showing loading messages", level: .info)
                    self.loadingMessages.startRotatingMessages()
                }
            }
        }
    }
    
    private func startLoadingTimeoutTimer() {
        loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                self.logger.log("Audio loading timeout after 8s, falling back to fallback audio", level: .warning)
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
            requireAudioPlayer.loadAudio(from: audioUrl)
        } else {
            // Ultimate fallback - use the old method if bundled files aren't found
            logger.log("Bundled fallback audio not found, using AudioPlayerManager default", level: .warning)
            requireAudioPlayer.loadAudio()
        }
        
        requireAudioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
        
        await cancelTodaysNotifications()
        
        // Delay scheduling to prevent immediate observer-triggered state change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.scheduleNextNotifications()
        }
    }
    
    private func cancelTodaysNotifications() async {
        await requireNotificationScheduler.cancelTodaysMissedNotification()
        await requireNotificationScheduler.cancelTodaysEveningReminder()
    }
    
    func startWelcomeDayStart() {
        logger.logUserAction("Start Welcome DayStart", details: ["time": Date().description])
        
        // PHASE 3: Immediate state change for button responsiveness
        state = .playing  // Playing state includes loading
        
        // Ensure services are initialized before starting
        ensureServicesInitialized()
        
        // Cancel the welcome scheduler since we're starting the DayStart
        welcomeScheduler.cancelWelcomeDayStart()
        
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
            // Check if audio exists (should have been created during onboarding) using canonical local date normalization
            let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: Date())
            
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
                    let success = await AudioDownloader.shared.download(from: audioUrl, for: Date())
                    if success {
                        await DebugLogger.shared.log("Welcome audio downloaded for caching", level: .info)
                        
                        // Update history with cached audio path
                        await MainActor.run {
                            let audioPath = AudioCache.shared.getAudioPath(for: Date())
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
        
        // Ensure services are initialized before replay
        ensureServicesInitialized()
        
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
           requireAudioCache.hasAudio(for: scheduledTime) {
            let audioUrl = requireAudioCache.getAudioPath(for: scheduledTime)
            logger.logAudioEvent("Loading cached audio for replay")
            logger.log("🎵 HomeViewModel: Loading cached audio from \(audioUrl)", level: .info)
            requireAudioPlayer.loadAudio(from: audioUrl)
        } else {
            // Fall back to bundled fallback audio for replay
            logger.logAudioEvent("Loading fallback audio for replay")
            logger.log("🎵 HomeViewModel: No cached audio, loading fallback audio", level: .info)
            
            let selectedVoice = userPreferences.settings.selectedVoice
            if let fallbackPath = getFallbackAudioPath(for: selectedVoice),
               let audioUrl = URL(string: "file://\(fallbackPath)") {
                logger.log("Loading fallback audio from: \(fallbackPath)", level: .info)
                requireAudioPlayer.loadAudio(from: audioUrl)
            } else {
                // Ultimate fallback
                logger.log("Bundled fallback audio not found, using AudioPlayerManager default", level: .warning)
                requireAudioPlayer.loadAudio()
            }
        }
        
        logger.log("🎵 HomeViewModel: Calling audioPlayer.play()", level: .info)
        requireAudioPlayer.play()
        
        logger.log("🎵 HomeViewModel: Setting state to .playing", level: .info)
        state = .playing
        
        logger.log("🎵 HomeViewModel: Stopping pause timeout timer", level: .info)
        stopPauseTimeoutTimer()
    }
    
    private func transitionToRecentlyPlayed() {
        logger.log("✅ DayStart completed, transitioning to completed state", level: .info)
        
        // Update completion status for current occurrence
        if let scheduledTime = nextDayStartTime {
            hasCompletedCurrentOccurrence = hasCompletedOccurrence(scheduledTime)
        }
        
        state = .completed
        stopPauseTimeoutTimer()
        
        // After 30 seconds, update state to see if we should transition elsewhere
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.state == .completed {
                self?.updateState()
            }
        }
    }
    
    private func scheduleNotifications() {
        Task {
            await notificationScheduler?.scheduleNotifications(for: userPreferences.schedule)
        }
    }
    
    private func scheduleNextNotifications() {
        var nextSchedule = userPreferences.schedule
        nextSchedule.skipTomorrow = false
        userPreferences.schedule = nextSchedule
    }
    
    private func hasCompletedOccurrence(_ scheduledTime: Date) -> Bool {
        // calendar not needed - removed to fix unused variable warning
        
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
        guard state == .playing, audioPlayer?.isPlaying == false else { return }
        
        // Check if we're still within a reasonable window to be in playing state
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            // No schedule - transition out of playing state
            logger.log("No schedule found while paused, exiting playing state", level: .info)
            audioPlayer?.reset()
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
            audioPlayer?.reset()
            updateState()
        } else if timeUntil > 0 && timeUntil <= tenHoursInSeconds {
            // Next DayStart countdown should start
            logger.log("Time for next DayStart countdown, exiting playing state", level: .info)
            audioPlayer?.reset()
            updateState()
        }
    }
}