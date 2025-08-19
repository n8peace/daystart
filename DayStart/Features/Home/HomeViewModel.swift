import Foundation
import SwiftUI
import Combine

enum ConnectionError {
    case noInternet
    case supabaseError
    case timeout
    
    var icon: String {
        switch self {
        case .noInternet: return "📡"
        case .supabaseError: return "🔧"
        case .timeout: return "⏳"
        }
    }
    
    var title: String {
        switch self {
        case .noInternet: return "Looks like you're offline!"
        case .supabaseError: return "Our servers are taking a coffee break"
        case .timeout: return "Taking longer than expected..."
        }
    }
    
    var message: String {
        switch self {
        case .noInternet: return "Check your connection and we'll sync up when you're back online."
        case .supabaseError: return "We'll have your DayStart ready shortly!"
        case .timeout: return "Your personalized brief is worth the wait!"
        }
    }
}

/// Simplified HomeViewModel with aggressive service deferral via ServiceRegistry
/// No services loaded in init - everything loads on-demand when actually needed
class HomeViewModel: ObservableObject {
    // TIER 1: Only essential dependencies (no service loading)
    private let userPreferences = UserPreferences.shared
    private let loadingMessages = LoadingMessagesService.shared // Lightweight service
    private lazy var logger = DebugLogger.shared // Lazy even for logger
    
    // TIER 2: Services loaded only via ServiceRegistry when needed
    private var serviceRegistry: ServiceRegistry { ServiceRegistry.shared }
    
    enum AppState {
        case idle            // Default state, no scheduled DayStart nearby
        case welcomeCountdown
        case welcomeReady
        case countdown       // 0-10 hours before scheduled time
        case preparing      // Waiting for audio to be ready
        case ready          // Ready to play
        case playing        // Currently playing
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
    @Published var preparingCountdownText = ""
    @Published var preparingMessage = ""
    @Published var connectionError: ConnectionError?
    
    private var timer: Timer?
    private var pauseTimeoutTimer: Timer?
    private var loadingDelayTimer: Timer?
    private var loadingTimeoutTimer: Timer?
    private var preparingTimer: Timer?
    private var preparingMessageTimer: Timer?
    private var pollingTimer: Timer?
    private var preparingStartTime: Date?
    private var pollingStartTime: Date?
    private var pollingAttempts = 0
    private let maxPollingAttempts = 30 // 5 minutes at 10-second intervals
    private var hasAutoStartedWelcome = false // Track if we've auto-started welcome DayStart
    private let maxPollingDuration: TimeInterval = 300 // 5 minutes total
    private var cancellables = Set<AnyCancellable>()
    
    // Debouncing and state transition protection
    private var updateStateWorkItem: DispatchWorkItem?
    private var isTransitioning = false
    private var lastStateChangeTime = Date()
    
    // Background/foreground handling
    private var stateBeforeBackground: AppState?
    private var wasPollingBeforeBackground = false
    
    // Preparing state messages
    private let preparingMessages = [
        "✨🔭 Checking the stars for cosmic alignment...",
        "🍌🌅 Ripening your morning bananas...",
        "👖🪙 Checking all the pockets for loose change...",
        "🤖☕ Teaching the AI to speak fluent morning...",
        "🌅📡 Calibrating the sunrise sensors...",
        "🐹💾 Feeding the digital hamsters...",
        "🔮✨ Polishing your crystal ball...",
        "🌡️🔥 Warming up the forecast machine...",
        "📰🪢 Untangling the news wires...",
        "☕📊 Brewing your information espresso...",
        "🛸📡 Syncing with the mothership...",
        "🐑💤 Counting sheep backwards...",
        "📻🌀 Adjusting the reality frequency...",
        "📥✨ Downloading today's vibes...",
        "🧊💡 Defrosting the insight freezer...",
        "🎼🎻 Tuning the morning orchestra...",
        "🧙‍♂️💻 Waking up the data gnomes...",
        "🔋⚡ Charging the inspiration batteries...",
        "🎱🔮 Consulting the magic 8-ball...",
        "🪐⚡ Aligning the productivity planets...",
        "🥘💪 Stirring the motivation pot...",
        "☁️🧠 Fluffing the wisdom clouds...",
        "👻🥞 Summoning the breakfast spirits...",
        "⚛️🔗 Activating quantum entanglement...",
        "⏰🐌 Convincing time to slow down...",
        "🌦️⚡ Negotiating with the weather gods...",
        "🐦🎵 Translating bird songs...",
        "💡🏃‍♂️ Measuring the speed of light..."
    ]
    private var currentMessageIndex = 0
    
    init() {
        // INSTANT: No service loading, no dependencies
        logger.log("🏠 HomeViewModel initialized instantly - no services loaded", level: .info)
    }
    
    func onViewAppear() {
        // DEFERRED: Load only basic observers and update state
        Task {
            await loadBasicObservers()
            validateAndUpdateState()
        }
    }
    
    private func validateAndUpdateState() {
        // Detect and recover from invalid states
        validateCurrentState()
        updateState()
    }
    
    private func validateCurrentState() {
        let currentState = state
        
        // Check for impossible state combinations
        switch currentState {
        case .playing:
            // If in playing state but no current DayStart, that's invalid
            if currentDayStart == nil {
                logger.log("⚠️ Invalid state: playing with no currentDayStart", level: .warning)
                state = .idle
                return
            }
            
            // If in playing state but audio player isn't loaded, check if it should be
            if serviceRegistry.loadedServices.contains("AudioPlayerManager") {
                let audioPlayer = serviceRegistry.audioPlayerManager
                if !audioPlayer.isPlaying {
                    logger.log("⚠️ Invalid state: playing but audio not playing", level: .warning)
                    // Try to recover by restarting audio or go to completed
                    if currentDayStart != nil {
                        state = .completed
                    } else {
                        state = .idle
                    }
                    return
                }
            }
            
        case .preparing:
            // If in preparing state but no polling is active, that's invalid
            if pollingTimer == nil || pollingStartTime == nil {
                logger.log("⚠️ Invalid state: preparing but no active polling", level: .warning)
                state = .idle
                return
            }
            
        case .completed:
            // If in completed state but no current DayStart, that's invalid
            if currentDayStart == nil {
                logger.log("⚠️ Invalid state: completed with no currentDayStart", level: .warning)
                state = .idle
                return
            }
            
        default:
            break
        }
        
        // Check for timer leaks
        validateTimerStates()
    }
    
    private func validateTimerStates() {
        let activeTimers = [
            timer != nil,
            pauseTimeoutTimer != nil,
            preparingTimer != nil,
            preparingMessageTimer != nil,
            pollingTimer != nil,
            loadingDelayTimer != nil,
            loadingTimeoutTimer != nil
        ]
        
        let timerCount = activeTimers.filter { $0 }.count
        
        if timerCount > 3 {
            logger.log("⚠️ Potential timer leak: \(timerCount) active timers", level: .warning)
            
            // In most states, we shouldn't have more than 2-3 active timers
            switch state {
            case .preparing:
                // Preparing can have: preparing timer, message timer, polling timer (3 max)
                if timerCount > 3 {
                    logger.log("🧹 Cleaning up excess timers in preparing state", level: .info)
                    cleanupAllTimers()
                    startPreparingState(isWelcome: false)
                }
            case .countdown:
                // Countdown should only have countdown timer
                if timer == nil || timerCount > 1 {
                    logger.log("🧹 Cleaning up timers for countdown state", level: .info)
                    cleanupAllTimers()
                    startCountdown()
                }
            case .playing:
                // Playing can have: pause timeout, loading timers
                if timerCount > 3 {
                    logger.log("🧹 Cleaning up excess timers in playing state", level: .info)
                    cleanupAllTimers()
                }
            default:
                // Most other states should have no timers
                if timerCount > 0 {
                    logger.log("🧹 Cleaning up timers for \(state) state", level: .info)
                    cleanupAllTimers()
                }
            }
        }
    }
    
    func onViewDisappear() {
        // Clean up all timers when view disappears
        cleanupAllTimers()
    }
    
    func onAppBackground() {
        logger.log("📱 App entering background, state: \(state)", level: .info)
        
        // Save current state
        stateBeforeBackground = state
        wasPollingBeforeBackground = pollingTimer != nil
        
        // Pause timers that shouldn't run in background
        switch state {
        case .preparing:
            // Keep polling for job completion, but pause UI timers
            preparingTimer?.invalidate()
            preparingTimer = nil
            preparingMessageTimer?.invalidate()
            preparingMessageTimer = nil
            loadingMessages.stopRotatingMessages()
            
        case .countdown:
            // Pause countdown display but keep the main timer
            // Timer will continue to track time until DayStart is ready
            break
            
        case .playing:
            // Audio should continue playing in background
            // But pause loading timers
            loadingDelayTimer?.invalidate()
            loadingDelayTimer = nil
            loadingTimeoutTimer?.invalidate()
            loadingTimeoutTimer = nil
            loadingMessages.stopRotatingMessages()
            
        default:
            // For other states, clean up all timers
            cleanupAllTimers()
        }
    }
    
    func onAppForeground() {
        logger.log("📱 App entering foreground, state: \(state)", level: .info)
        
        // Validate state after returning from background
        validateAndUpdateState()
        
        // Restart appropriate timers based on current state
        switch state {
        case .preparing:
            // Restart preparing UI if we were preparing before
            if stateBeforeBackground == .preparing {
                // Restart message rotation
                startPreparingMessageRotation()
                
                // Restart countdown if we have a start time
                if let startTime = preparingStartTime {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let remaining = max(0, 120 - elapsed) // 2 minutes total
                    if remaining > 0 {
                        startPreparingCountdown(duration: remaining)
                    }
                }
                
                // Restart polling if it was active
                if wasPollingBeforeBackground && pollingTimer == nil {
                    if let nextTime = nextDayStartTime {
                        startPollingForAudio(scheduledTime: nextTime)
                    }
                }
            }
            
        case .countdown:
            // Countdown should continue automatically
            break
            
        case .playing:
            // Check if audio is still playing, update UI accordingly
            if serviceRegistry.loadedServices.contains("AudioPlayerManager") {
                let audioPlayer = serviceRegistry.audioPlayerManager
                if !audioPlayer.isPlaying {
                    // Audio stopped while in background, transition to completed
                    transitionToRecentlyPlayed()
                }
            }
            
        default:
            break
        }
        
        // Clear background state tracking
        stateBeforeBackground = nil
        wasPollingBeforeBackground = false
    }
    
    private func cleanupAllTimers() {
        timer?.invalidate()
        timer = nil
        pauseTimeoutTimer?.invalidate()
        pauseTimeoutTimer = nil
        preparingTimer?.invalidate()
        preparingTimer = nil
        preparingMessageTimer?.invalidate()
        preparingMessageTimer = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        loadingDelayTimer?.invalidate()
        loadingDelayTimer = nil
        loadingTimeoutTimer?.invalidate()
        loadingTimeoutTimer = nil
        
        // Reset preparing state data
        preparingStartTime = nil
        pollingStartTime = nil
        pollingAttempts = 0
        
        // Stop any rotating messages
        loadingMessages.stopRotatingMessages()
    }
    
    // MARK: - Lazy Service Loading
    
    /// Load only basic observers (no heavy services)
    private func loadBasicObservers() async {
        await MainActor.run {
            // Only observe user preferences changes (no service dependencies)
            setupBasicObservers()
        }
    }
    
    private func setupBasicObservers() {
        // Lightweight observers (no service loading)
        userPreferences.$schedule
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateState()
                self?.scheduleNotificationsIfNeeded()
            }
            .store(in: &cancellables)
        
        userPreferences.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        // LAZY: Only observe welcome scheduler if it's enabled
        if !userPreferences.schedule.repeatDays.isEmpty {
            observeWelcomeSchedulerIfNeeded()
        }
    }
    
    /// Load welcome scheduler observers only when needed
    private func observeWelcomeSchedulerIfNeeded() {
        // LAZY: WelcomeScheduler is loaded on-demand
        let welcomeScheduler = WelcomeDayStartScheduler.shared
        
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
    }
    
    /// Load audio observers only when audio services are needed
    private func setupAudioObserversIfNeeded() {
        // LAZY: Only load if audio services are actually loaded
        guard serviceRegistry.loadedServices.contains("AudioPlayerManager") else { return }
        
        let audioPlayer = serviceRegistry.audioPlayerManager
        
        audioPlayer.$didFinishPlaying
            .sink { [weak self] didFinish in
                if self?.state == .playing && didFinish {
                    self?.transitionToRecentlyPlayed()
                }
            }
            .store(in: &cancellables)
        
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
    }
    
    // MARK: - State Management (No Service Dependencies)
    
    private func debouncedUpdateState() {
        updateStateWorkItem?.cancel()
        
        updateStateWorkItem = DispatchWorkItem { [weak self] in
            self?.performStateUpdate()
        }
        
        if let workItem = updateStateWorkItem {
            DispatchQueue.main.async(execute: workItem)
        }
    }
    
    private func updateState() {
        performStateUpdate()
    }
    
    private func performStateUpdate() {
        logger.log("🎵 HomeViewModel: updateState() called", level: .debug)
        
        // Prevent rapid state transitions
        guard !isTransitioning else {
            logger.log("⚠️ State transition already in progress, skipping", level: .debug)
            return
        }
        
        let now = Date()
        let timeSinceLastChange = now.timeIntervalSince(lastStateChangeTime)
        
        // Minimum 100ms between state changes to prevent flicker
        guard timeSinceLastChange > 0.1 else {
            logger.log("⚠️ State change too rapid, debouncing", level: .debug)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performStateUpdate()
            }
            return
        }
        
        isTransitioning = true
        lastStateChangeTime = now
        
        cleanupAllTimers()
        
        // Check for welcome DayStart first (only if enabled)
        if !userPreferences.schedule.repeatDays.isEmpty {
            let welcomeScheduler = WelcomeDayStartScheduler.shared
            
            if welcomeScheduler.isWelcomePending {
                state = .welcomeCountdown
                return
            }
            
            if welcomeScheduler.isWelcomeReadyToPlay {
                state = .welcomeReady
                
                // Auto-start welcome DayStart if we haven't already
                if !hasAutoStartedWelcome {
                    hasAutoStartedWelcome = true
                    logger.log("🚀 Auto-starting welcome DayStart after onboarding", level: .info)
                    // Delay slightly to ensure UI has updated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.startWelcomeDayStart()
                    }
                }
                
                return
            }
        }
        
        // Don't update state if currently playing audio
        if state == .playing {
            return
        }
        
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            // No schedule found
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
        
        // Update schedule info
        withAnimation(.none) {
            showNoScheduleMessage = false
            nextDayStartTime = nextOccurrence
        }
        
        // Calculate date flags
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextOccurrenceDay = calendar.startOfDay(for: nextOccurrence)
        
        withAnimation(.none) {
            isNextDayStartToday = nextOccurrenceDay == today
            isNextDayStartTomorrow = nextOccurrenceDay == tomorrow
        }
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        let sixHoursInSeconds: TimeInterval = 6 * 3600
        let tenHoursInSeconds: TimeInterval = 10 * 3600
        
        let hasCompletedThisOccurrence = hasCompletedOccurrence(nextOccurrence)
        hasCompletedCurrentOccurrence = hasCompletedThisOccurrence
        
        // State logic (no service dependencies)
        if timeUntil > 300 && timeUntil <= tenHoursInSeconds {
            // More than 5 minutes until start - show countdown
            startCountdown()
        } else if timeUntil > 0 && timeUntil <= 300 && !hasCompletedThisOccurrence {
            // Less than 5 minutes until start - check if audio is ready
            checkAudioReadiness(for: nextOccurrence)
        } else if timeUntil <= 0 && timeUntil >= -sixHoursInSeconds && !hasCompletedThisOccurrence {
            // Past scheduled time - check if audio is ready
            checkAudioReadiness(for: nextOccurrence)
        } else if hasCompletedThisOccurrence && timeUntil >= -sixHoursInSeconds {
            state = .completed
        } else {
            state = .idle
        }
        
        // Mark transition as complete
        isTransitioning = false
    }
    
    private func startCountdown() {
        state = .countdown
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let nextTime = self.nextDayStartTime else { return }
            
            let timeUntil = nextTime.timeIntervalSinceNow
            
            if timeUntil <= 0 {
                self.timer?.invalidate()
                // When countdown reaches 0, check if audio is ready
                self.checkAudioReadiness(for: nextTime)
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
        
        if newText != countdownText {
            countdownText = newText
        }
    }
    
    // MARK: - Audio Readiness & Preparing State
    
    private func checkAudioReadiness(for scheduledTime: Date) {
        // First check if we have cached audio
        if serviceRegistry.audioCache.hasAudio(for: scheduledTime) {
            state = .ready
            return
        }
        
        // Check network connectivity
        guard NetworkMonitor.shared.isConnected else {
            connectionError = .noInternet
            state = .idle
            return
        }
        
        // Start preparing state
        startPreparingState(isWelcome: false)
        
        // Check if job exists and create if needed, then start polling
        Task {
            await checkAndCreateJobIfNeeded(for: scheduledTime)
            await MainActor.run {
                startPollingForAudio(scheduledTime: scheduledTime)
            }
        }
    }
    
    private func startPreparingState(isWelcome: Bool) {
        state = .preparing
        preparingStartTime = Date()
        connectionError = nil
        
        // Start countdown timer
        let expectedDuration: TimeInterval = isWelcome ? 120 : 120 // 2 minutes for both initially
        startPreparingCountdown(duration: expectedDuration)
        
        // Start message rotation
        startPreparingMessageRotation()
    }
    
    private func startPreparingCountdown(duration: TimeInterval) {
        preparingTimer?.invalidate()
        
        preparingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.preparingStartTime else { return }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, duration - elapsed)
            
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            self.preparingCountdownText = String(format: "%d:%02d", minutes, seconds)
            
            if remaining <= 0 {
                self.preparingTimer?.invalidate()
                self.preparingCountdownText = "0:00"
                
                // When preparing countdown reaches 0, show timeout error
                self.connectionError = .timeout
                self.state = .idle
            }
        }
    }
    
    private func startPreparingMessageRotation() {
        // Set initial message
        currentMessageIndex = Int.random(in: 0..<preparingMessages.count)
        preparingMessage = preparingMessages[currentMessageIndex]
        
        preparingMessageTimer?.invalidate()
        
        // Rotate messages every 5-7 seconds
        preparingMessageTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5...7), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.currentMessageIndex = (self.currentMessageIndex + 1) % self.preparingMessages.count
            
            withAnimation(.easeInOut(duration: 0.3)) {
                self.preparingMessage = self.preparingMessages[self.currentMessageIndex]
            }
            
            // Reset timer with new random interval
            self.preparingMessageTimer?.invalidate()
            self.preparingMessageTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5...7), repeats: true) { _ in
                self.rotatePreparingMessage()
            }
        }
    }
    
    private func rotatePreparingMessage() {
        currentMessageIndex = (currentMessageIndex + 1) % preparingMessages.count
        withAnimation(.easeInOut(duration: 0.3)) {
            preparingMessage = preparingMessages[currentMessageIndex]
        }
    }
    
    private func startPollingForAudio(scheduledTime: Date) {
        pollingTimer?.invalidate()
        
        // Reset polling counters
        pollingStartTime = Date()
        pollingAttempts = 0
        
        // Initial check
        Task {
            await checkAudioStatus(for: scheduledTime)
        }
        
        // Poll every 10 seconds with safety limits
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task {
                await self?.checkAudioStatusWithLimits(for: scheduledTime)
            }
        }
    }
    
    private func checkAudioStatusWithLimits(for scheduledTime: Date) async {
        guard let startTime = pollingStartTime else { return }
        
        pollingAttempts += 1
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Check if we've exceeded limits
        if pollingAttempts >= maxPollingAttempts || elapsed >= maxPollingDuration {
            logger.log("⚠️ Polling timeout after \(pollingAttempts) attempts in \(elapsed)s", level: .warning)
            
            await MainActor.run {
                connectionError = .timeout
                stopPreparingState()
                state = .idle
            }
            return
        }
        
        // Continue with normal polling
        await checkAudioStatus(for: scheduledTime)
    }
    
    private func checkAudioStatus(for scheduledTime: Date) async {
        do {
            let supabaseClient = serviceRegistry.supabaseClient
            let audioStatus = try await supabaseClient.getAudioStatus(for: scheduledTime)
            
            await MainActor.run {
                if audioStatus.success && audioStatus.status == "ready" {
                    // Audio is ready!
                    stopPreparingState()
                    state = .playing
                    
                    // Haptic feedback for early completion
                    HapticManager.shared.notification(type: .success)
                    
                    // Load audio services and start playing
                    Task {
                        await loadAudioServicesAndStart(scheduledTime: scheduledTime)
                    }
                } else if audioStatus.status == "failed" {
                    // Job failed
                    connectionError = .supabaseError
                    stopPreparingState()
                    state = .idle
                }
                // Continue polling if still processing
            }
        } catch {
            await MainActor.run {
                // Check if it's a network error
                if !NetworkMonitor.shared.isConnected {
                    connectionError = .noInternet
                } else {
                    connectionError = .supabaseError
                }
                logger.logError(error, context: "Failed to check audio status while preparing")
            }
        }
    }
    
    private func stopPreparingState() {
        preparingTimer?.invalidate()
        preparingTimer = nil
        
        preparingMessageTimer?.invalidate()
        preparingMessageTimer = nil
        
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        preparingStartTime = nil
        pollingStartTime = nil
        pollingAttempts = 0
    }
    
    private func checkAndCreateJobIfNeeded(for scheduledTime: Date) async {
        do {
            let supabaseClient = serviceRegistry.supabaseClient
            let audioStatus = try await supabaseClient.getAudioStatus(for: scheduledTime)
            
            // If job doesn't exist or failed, create a new one
            if audioStatus.status == "not_found" || audioStatus.status == "failed" {
                logger.log("🔄 Creating job for \(scheduledTime) - status: \(audioStatus.status)", level: .info)
                
                // Load snapshot builder to get current data
                let snapshot = await serviceRegistry.snapshotBuilder.buildSnapshot()
                
                let jobResponse = try await supabaseClient.createJob(
                    for: scheduledTime,
                    with: userPreferences.settings,
                    schedule: userPreferences.schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar
                )
                
                logger.log("✅ Job created: \(jobResponse.jobId ?? "unknown") with status: \(jobResponse.status ?? "unknown")", level: .info)
            }
        } catch {
            logger.logError(error, context: "Failed to check/create job for \(scheduledTime)")
            await MainActor.run {
                if !NetworkMonitor.shared.isConnected {
                    connectionError = .noInternet
                } else {
                    connectionError = .supabaseError
                }
                stopPreparingState()
                state = .idle
            }
        }
    }
    
    private func checkWelcomeAudioStatus() async {
        // First try to create welcome job if needed
        await checkAndCreateWelcomeJobIfNeeded()
        
        // Then start polling every 10 seconds for welcome audio
        await MainActor.run {
            pollingTimer?.invalidate()
            
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task {
                    await self?.checkWelcomeAudioStatusOnce()
                }
            }
        }
        
        // Initial check
        await checkWelcomeAudioStatusOnce()
    }
    
    private func checkAndCreateWelcomeJobIfNeeded() async {
        do {
            let supabaseClient = serviceRegistry.supabaseClient
            let currentDate = Date()
            let audioStatus = try await supabaseClient.getAudioStatus(for: currentDate)
            
            // If job doesn't exist or failed, create a welcome job
            if audioStatus.status == "not_found" || audioStatus.status == "failed" {
                logger.log("🔄 Creating welcome job - status: \(audioStatus.status)", level: .info)
                
                // Load snapshot builder to get current data
                let snapshot = await serviceRegistry.snapshotBuilder.buildSnapshot()
                
                let jobResponse = try await supabaseClient.createJob(
                    for: currentDate,
                    with: userPreferences.settings,
                    schedule: userPreferences.schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar
                )
                
                logger.log("✅ Welcome job created: \(jobResponse.jobId ?? "unknown") with status: \(jobResponse.status ?? "unknown")", level: .info)
            }
        } catch {
            logger.logError(error, context: "Failed to check/create welcome job")
            await MainActor.run {
                if !NetworkMonitor.shared.isConnected {
                    connectionError = .noInternet
                } else {
                    connectionError = .supabaseError
                }
                stopPreparingState()
                state = .idle
            }
        }
    }
    
    private func checkWelcomeAudioStatusOnce() async {
        do {
            let supabaseClient = serviceRegistry.supabaseClient
            let audioStatus = try await supabaseClient.getAudioStatus(for: Date())
            
            await MainActor.run {
                if audioStatus.success && audioStatus.status == "ready" {
                    // Welcome audio is ready!
                    stopPreparingState()
                    state = .playing
                    
                    // Load audio services and play
                    Task {
                        await loadAudioServicesAndStart()
                        await startWelcomeDayStartWithSupabase()
                    }
                    
                    // Haptic feedback for early completion
                    HapticManager.shared.notification(type: .success)
                } else if audioStatus.status == "failed" {
                    // Job failed
                    connectionError = .supabaseError
                    stopPreparingState()
                    state = .idle
                }
                // Continue polling if still processing
            }
        } catch {
            await MainActor.run {
                // Check if it's a network error
                if !NetworkMonitor.shared.isConnected {
                    connectionError = .noInternet
                } else {
                    connectionError = .supabaseError
                }
                stopPreparingState()
                state = .idle
                logger.logError(error, context: "Failed to check welcome audio status")
            }
        }
    }
    
    // MARK: - User Actions (Load Services On-Demand)
    
    private func getTodayScheduledTime() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let todayComponents = calendar.dateComponents([.hour, .minute], from: userPreferences.schedule.time)
        
        // Get today's scheduled time
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = todayComponents.hour
        components.minute = todayComponents.minute
        
        guard let todayScheduledTime = calendar.date(from: components) else { return nil }
        
        // Check if today is a scheduled day
        let weekday = calendar.component(.weekday, from: now)
        guard let weekDay = WeekDay(weekday: weekday),
              userPreferences.schedule.repeatDays.contains(weekDay) else { return nil }
        
        return todayScheduledTime
    }
    
    func startDayStart() {
        logger.logUserAction("Start DayStart", details: ["time": Date().description])
        
        // Use today's scheduled time instead of nextDayStartTime
        guard let scheduledTime = getTodayScheduledTime() else {
            logger.log("❌ No scheduled time for DayStart today", level: .error)
            return
        }
        
        // Check if audio is already cached
        if serviceRegistry.audioCache.hasAudio(for: scheduledTime) {
            // IMMEDIATE: State change for responsiveness
            state = .playing
            
            // LAZY: Load audio services only when needed
            Task {
                await loadAudioServicesAndStart(scheduledTime: scheduledTime)
            }
        } else {
            // Check network connectivity
            guard NetworkMonitor.shared.isConnected else {
                connectionError = .noInternet
                return
            }
            
            // Start preparing state
            startPreparingState(isWelcome: false)
            
            // Start polling for audio status
            startPollingForAudio(scheduledTime: scheduledTime)
        }
    }
    
    private func loadAudioServicesAndStart(scheduledTime: Date? = nil) async {
        // TIER 2: Load audio services on-demand
        _ = serviceRegistry.audioPlayerManager
        _ = serviceRegistry.audioCache
        
        // Setup audio observers now that services are loaded
        await MainActor.run {
            setupAudioObserversIfNeeded()
        }
        
        await startDayStartWithAudio(scheduledTime: scheduledTime)
    }
    
    func startWelcomeDayStart() {
        logger.logUserAction("Start Welcome DayStart", details: ["time": Date().description])
        
        // Cancel welcome scheduler
        WelcomeDayStartScheduler.shared.cancelWelcomeDayStart()
        
        // Check network connectivity first
        guard NetworkMonitor.shared.isConnected else {
            connectionError = .noInternet
            state = .idle
            return
        }
        
        // Start preparing state for welcome
        startPreparingState(isWelcome: true)
        
        // Start polling for welcome audio
        Task {
            await checkWelcomeAudioStatus()
        }
    }
    
    func replayDayStart(_ dayStart: DayStartData) {
        logger.logUserAction("Replay DayStart", details: ["id": dayStart.id])
        
        currentDayStart = dayStart
        state = .playing
        
        // LAZY: Load audio services when needed
        Task {
            // Only load audio services by accessing them (they load on-demand)
            _ = serviceRegistry.audioPlayerManager
            _ = serviceRegistry.audioCache
            
            // Setup audio observers now that services are loaded
            await MainActor.run {
                setupAudioObserversIfNeeded()
            }
            
            await replayDayStartWithAudio(dayStart)
        }
    }
    
    func exitCompletedState() {
        logger.logUserAction("Exit Completed State", details: ["time": Date().description])
        
        // Clean up any timers and reset to appropriate state
        timer?.invalidate()
        timer = nil
        pauseTimeoutTimer?.invalidate()
        pauseTimeoutTimer = nil
        stopLoadingTimers()
        stopPreparingState()
        
        // Reset current DayStart
        currentDayStart = nil
        
        // Update to appropriate state based on schedule
        updateState()
    }
    
    // MARK: - Audio Playback (Services Loaded On-Demand)
    
    private func startDayStartWithAudio(scheduledTime: Date? = nil) async {
        let dayStart = generateBasicDayStart(for: userPreferences.settings)
        
        var dayStartWithScheduledTime = dayStart
        // Use the passed scheduledTime or fall back to nextDayStartTime
        let effectiveScheduledTime = scheduledTime ?? nextDayStartTime
        if let time = effectiveScheduledTime {
            dayStartWithScheduledTime.scheduledTime = time
        }
        
        currentDayStart = dayStartWithScheduledTime
        userPreferences.addToHistory(dayStartWithScheduledTime)
        
        guard let effectiveScheduledTime = scheduledTime ?? nextDayStartTime else {
            await MainActor.run {
                connectionError = .supabaseError
                state = .idle
            }
            return
        }
        
        // Check if audio is cached
        if serviceRegistry.audioCache.hasAudio(for: effectiveScheduledTime) {
            await playCachedAudio(for: effectiveScheduledTime)
        } else {
            // Stream from CDN
            do {
                // LAZY: Load SupabaseClient only when needed
                let supabaseClient = serviceRegistry.supabaseClient
                let audioStatus = try await supabaseClient.getAudioStatus(for: effectiveScheduledTime)
                
                if audioStatus.success && audioStatus.status == "ready", let audioUrl = audioStatus.audioUrl {
                    await streamAudio(from: audioUrl)
                    
                    // Background download
                    let dayStartId = dayStartWithScheduledTime.id
                    Task.detached {
                        let audioDownloader = await MainActor.run { ServiceRegistry.shared.audioDownloader }
                        let success = await audioDownloader.download(from: audioUrl, for: effectiveScheduledTime)
                        if success {
                            await MainActor.run {
                                let audioPath = ServiceRegistry.shared.audioCache.getAudioPath(for: effectiveScheduledTime)
                                UserPreferences.shared.updateHistory(
                                    with: dayStartId,
                                    audioFilePath: audioPath.path
                                )
                            }
                        }
                    }
                } else {
                    // Audio not ready - show error
                    await MainActor.run {
                        if audioStatus.status == "not_found" || audioStatus.status == "failed" {
                            connectionError = .supabaseError
                        } else {
                            connectionError = .timeout
                        }
                        state = .idle
                    }
                }
            } catch {
                logger.logError(error, context: "Failed to check audio status")
                await MainActor.run {
                    if !NetworkMonitor.shared.isConnected {
                        connectionError = .noInternet
                    } else {
                        connectionError = .supabaseError
                    }
                    state = .idle
                }
            }
        }
    }
    
    private func startWelcomeDayStartWithSupabase() async {
        let dayStart = generateBasicDayStart(for: userPreferences.settings)
        
        var welcomeDayStart = dayStart
        welcomeDayStart.id = UUID()
        welcomeDayStart.scheduledTime = Date()
        
        currentDayStart = welcomeDayStart
        userPreferences.addToHistory(welcomeDayStart)
        
        do {
            // LAZY: SupabaseClient already loaded from previous call
            let audioStatus = try await serviceRegistry.supabaseClient.getAudioStatus(for: Date())
            
            if audioStatus.success && audioStatus.status == "ready", let audioUrl = audioStatus.audioUrl {
                await streamAudio(from: audioUrl)
            } else {
                await MainActor.run {
                    connectionError = .supabaseError
                    state = .idle
                }
            }
        } catch {
            logger.logError(error, context: "Welcome DayStart Supabase failed")
            await MainActor.run {
                if !NetworkMonitor.shared.isConnected {
                    connectionError = .noInternet
                } else {
                    connectionError = .supabaseError
                }
                state = .idle
            }
        }
    }
    
    private func playCachedAudio(for date: Date) async {
        let audioPlayer = serviceRegistry.audioPlayerManager
        let audioCache = serviceRegistry.audioCache
        
        let audioUrl = audioCache.getAudioPath(for: date)
        audioPlayer.loadAudio(from: audioUrl)
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
        
        await cancelTodaysNotifications()
        scheduleNextNotifications()
    }
    
    private func streamAudio(from url: URL) async {
        startLoadingDelayTimer()
        startLoadingTimeoutTimer()
        
        let audioPlayer = serviceRegistry.audioPlayerManager
        
        audioPlayer.loadAudio(from: url) { [weak self] success, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                self.stopLoadingTimers()
                
                if success {
                    audioPlayer.play()
                    self.state = .playing
                    self.stopPauseTimeoutTimer()
                    await self.cancelTodaysNotifications()
                    self.scheduleNextNotifications()
                } else {
                    self.connectionError = .timeout
                    self.state = .idle
                }
            }
        }
    }
    
    
    private func replayDayStartWithAudio(_ dayStart: DayStartData) async {
        let audioPlayer = serviceRegistry.audioPlayerManager
        let audioCache = serviceRegistry.audioCache
        
        if let scheduledTime = dayStart.scheduledTime,
           audioCache.hasAudio(for: scheduledTime) {
            let audioUrl = audioCache.getAudioPath(for: scheduledTime)
            audioPlayer.loadAudio(from: audioUrl)
        } else {
            // No cached audio available for replay - this shouldn't happen
            // but if it does, we'll load without audio
            audioPlayer.loadAudio()
        }
        
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
    }
    
    // MARK: - Helper Methods (Lightweight)
    
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
    
    
    private func hasCompletedOccurrence(_ scheduledTime: Date) -> Bool {
        return userPreferences.history.contains { dayStart in
            guard !dayStart.isDeleted,
                  let dayStartScheduledTime = dayStart.scheduledTime else {
                return false
            }
            return abs(dayStartScheduledTime.timeIntervalSince(scheduledTime)) < 60
        }
    }
    
    private func transitionToRecentlyPlayed() {
        if let scheduledTime = nextDayStartTime {
            hasCompletedCurrentOccurrence = hasCompletedOccurrence(scheduledTime)
        }
        
        state = .completed
        stopPauseTimeoutTimer()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.state == .completed {
                self?.updateState()
            }
        }
    }
    
    // MARK: - Notification Management (Lazy Loading)
    
    private func scheduleNotificationsIfNeeded() {
        // LAZY: Only load NotificationScheduler if user has active schedule
        guard !userPreferences.schedule.repeatDays.isEmpty else { return }
        
        Task {
            let notificationScheduler = serviceRegistry.notificationScheduler
            await notificationScheduler.scheduleNotifications(for: userPreferences.schedule)
        }
    }
    
    private func cancelTodaysNotifications() async {
        // LAZY: Only if NotificationScheduler is loaded
        guard serviceRegistry.loadedServices.contains("NotificationScheduler") else { return }
        
        let notificationScheduler = serviceRegistry.notificationScheduler
        await notificationScheduler.cancelTodaysMissedNotification()
        await notificationScheduler.cancelTodaysEveningReminder()
    }
    
    private func scheduleNextNotifications() {
        var nextSchedule = userPreferences.schedule
        nextSchedule.skipTomorrow = false
        userPreferences.schedule = nextSchedule
    }
    
    // MARK: - Loading State Management
    
    private func startLoadingDelayTimer() {
        stopLoadingTimers()
        
        loadingDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let weakSelf = self else { return }
            Task { @MainActor in
                guard weakSelf.state == .playing else { return }
                weakSelf.loadingMessages.startRotatingMessages()
            }
        }
    }
    
    private func startLoadingTimeoutTimer() {
        loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let weakSelf = self else { return }
            Task { @MainActor in
                weakSelf.stopLoadingTimers()
                weakSelf.connectionError = .timeout
                weakSelf.state = .idle
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
    
    // MARK: - Pause Timeout Management
    
    private func startPauseTimeoutTimer() {
        stopPauseTimeoutTimer()
        
        pauseTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIfShouldExitPlayingState()
        }
    }
    
    private func stopPauseTimeoutTimer() {
        pauseTimeoutTimer?.invalidate()
        pauseTimeoutTimer = nil
    }
    
    private func checkIfShouldExitPlayingState() {
        // LAZY: Only check if AudioPlayerManager is loaded
        guard state == .playing,
              serviceRegistry.loadedServices.contains("AudioPlayerManager"),
              serviceRegistry.audioPlayerManager.isPlaying == false else { return }
        
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else {
            serviceRegistry.audioPlayerManager.reset()
            updateState()
            return
        }
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        let sixHoursInSeconds: TimeInterval = 6 * 3600
        let tenHoursInSeconds: TimeInterval = 10 * 3600
        
        if timeUntil < -sixHoursInSeconds {
            serviceRegistry.audioPlayerManager.reset()
            updateState()
        } else if timeUntil > 0 && timeUntil <= tenHoursInSeconds {
            serviceRegistry.audioPlayerManager.reset()
            updateState()
        }
    }
}