import Foundation
import SwiftUI
import Combine

enum ConnectionError {
    case noInternet
    case supabaseError
    case timeout
    case generationFailed
    case streamingFailed
    case generationTimeout
    case streamingTimeout
    
    var icon: String {
        switch self {
        case .noInternet: return "📡"
        case .supabaseError: return "🔧"
        case .timeout: return "⏳"
        case .generationFailed: return "🔧"
        case .streamingFailed: return "📱"
        case .generationTimeout: return "⏰"
        case .streamingTimeout: return "⏰"
        }
    }
    
    var title: String {
        switch self {
        case .noInternet: return "No internet connection"
        case .supabaseError: return "Our servers are taking a coffee break"
        case .timeout: return "Taking longer than expected..."
        case .generationFailed: return "Sorry, content generation failed"
        case .streamingFailed: return "Sorry, audio loading failed"
        case .generationTimeout: return "Content generation timed out"
        case .streamingTimeout: return "Audio loading timed out"
        }
    }
    
    var message: String {
        switch self {
        case .noInternet: return "Will retry when connected..."
        case .supabaseError: return "We'll have your DayStart ready shortly!"
        case .timeout: return "Your personalized brief is worth the wait!"
        case .generationFailed: return "Our team has been notified. Please try again tomorrow."
        case .streamingFailed: return "Please check your connection and try again later."
        case .generationTimeout: return "Please try again later."
        case .streamingTimeout: return "Please check your connection and try again later."
        }
    }
    
    var errorCode: String {
        switch self {
        case .noInternet: return "NETWORK_UNAVAILABLE"
        case .supabaseError: return "SERVER_ERROR"
        case .timeout: return "GENERAL_TIMEOUT"
        case .generationFailed: return "GENERATION_FAILED"
        case .streamingFailed: return "STREAMING_FAILED"
        case .generationTimeout: return "GENERATION_TIMEOUT"
        case .streamingTimeout: return "STREAMING_TIMEOUT"
        }
    }
}

// MARK: - State Transition Manager
@MainActor
class StateTransitionManager {
    private weak var viewModel: HomeViewModel?
    private let logger = DebugLogger.shared
    
    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }
    
    func transitionTo(_ newState: HomeViewModel.AppState, animated: Bool = true) {
        guard let viewModel = viewModel else { return }
        
        // Validate transition
        guard canTransition(from: viewModel.state, to: newState) else {
            logger.log("⚠️ Invalid state transition from \(viewModel.state) to \(newState)", level: .warning)
            return
        }
        
        // Log transition
        logger.log("🔄 State transition: \(viewModel.state) → \(newState)", level: .info)
        
        // Apply transition with consistent animation
        if animated {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                viewModel.state = newState
            }
        } else {
            viewModel.state = newState
        }
        
        // Handle state-specific actions
        switch newState {
        case .welcomeReady:
            // Start polling for audio status when entering welcome ready state
            WelcomeDayStartScheduler.shared.startAudioPollingImmediately()
        case .idle, .completed:
            // Stop polling when going back to idle or completed
            if viewModel.state == .welcomeReady || viewModel.state == .preparing {
                WelcomeDayStartScheduler.shared.stopAudioPolling()
            }
        case .preparing, .buffering, .playing:
            // Keep polling active during preparing, buffering, and playing for welcome
            break
        }
    }
    
    private func canTransition(from currentState: HomeViewModel.AppState, to newState: HomeViewModel.AppState) -> Bool {
        // Allow any transition for now - can add validation logic later
        return true
    }
}

/// Simplified HomeViewModel with aggressive service deferral via ServiceRegistry
/// No services loaded in init - everything loads on-demand when actually needed
@MainActor
class HomeViewModel: ObservableObject {
    // TIER 1: Only essential dependencies (no service loading)
    private let userPreferences = UserPreferences.shared
    private let loadingMessages = LoadingMessagesService.shared // Lightweight service
    private lazy var logger = DebugLogger.shared // Lazy even for logger
    
    // TIER 2: Services loaded only via ServiceRegistry when needed
    private var serviceRegistry: ServiceRegistry { ServiceRegistry.shared }
    
    // State transition management
    private lazy var stateTransitionManager = StateTransitionManager(viewModel: self)
    
    enum AppState {
        case idle            // Enhanced: handles countdown, welcome flows, and default state
        case welcomeReady   // Welcome DayStart is ready, waiting for user tap
        case preparing      // Waiting for audio to be ready
        case buffering      // Loading/buffering audio (show loading icon)
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
    @Published var toastMessage: String?
    @Published var showReviewGate = false
    @Published var showFeedbackSheet = false
    @Published var isManualRefreshing = false
    
    private var timer: Timer?
    private var pauseTimeoutTimer: Timer?
    private var loadingDelayTimer: Timer?
    private var loadingTimeoutTimer: Timer?
    private var preparingTimer: Timer?
    private var preparingMessageTimer: Timer?
    private var pollingTimer: Timer?
    private var errorDismissTimer: Timer?
    private var retryTimer: Timer?
    private var preparingStartTime: Date?
    private var pollingStartTime: Date?
    private var pollingAttempts = 0
    private let maxPollingAttempts = 30 // 5 minutes at 10-second intervals
    private let maxPollingDuration: TimeInterval = 300 // 5 minutes total
    private var retryAttempts = 0
    private let maxRetryAttempts = 5
    private var currentJobId: String?
    private var failureStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    // Debouncing and state transition protection
    private var updateStateWorkItem: DispatchWorkItem?
    private var isTransitioning = false
    private var lastStateChangeTime = Date()
    
    // Background/foreground handling
    private var stateBeforeBackground: AppState?
    private var wasPollingBeforeBackground = false
    
    // Background failure persistence
    private let backgroundFailureKey = "DayStart_BackgroundFailure"
    private let backgroundFailureTimestampKey = "DayStart_BackgroundFailureTimestamp"
    
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
        
        // Listen for state change notifications from other components
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HomeViewModelStateChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let stateString = notification.userInfo?["state"] as? String {
                switch stateString {
                case "completed":
                    self?.state = .completed
                case "idle":
                    self?.exitPlayingState()
                default:
                    break
                }
            }
        }
    }
    
    func onViewAppear() {
        // DEFERRED: Load only basic observers and update state
        Task {
            await loadBasicObservers()
            
            // Check if we should auto-start welcome DayStart after onboarding
            if UserDefaults.standard.bool(forKey: "shouldAutoStartWelcome") {
                UserDefaults.standard.removeObject(forKey: "shouldAutoStartWelcome")
                logger.log("🚀 Auto-starting welcome DayStart after onboarding", level: .info)
                startWelcomeImmediately()
                return
            }
            
            validateAndUpdateState()
            
            // Check if today needs a job (backfill for users returning after being away)
            await checkAndCreateTodayJobIfNeeded()
            
            // Initialize snapshot update system if user has active schedule
            if !userPreferences.schedule.repeatDays.isEmpty {
                await initializeSnapshotUpdateSystem()
            }
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
            case .buffering:
                // Buffering should only have loading timers (2 max)
                if timerCount > 2 {
                    logger.log("🧹 Cleaning up excess timers in buffering state", level: .info)
                    stopLoadingTimers()
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
            
        case .buffering:
            // Stop loading timers while in background
            stopLoadingTimers()
        
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
        
        // Check for background failures first
        if let backgroundFailure = loadAndCheckBackgroundFailure() {
            connectionError = backgroundFailure
            state = .idle
            // Show toast notification for background failure
            showBackgroundFailureToast(backgroundFailure)
            // Start auto-dismiss timer
            startErrorDismissTimer()
            return
        }
        
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
            
        case .buffering:
            // If buffering on foreground, check if audio actually started
            if serviceRegistry.loadedServices.contains("AudioPlayerManager") {
                let audioPlayer = serviceRegistry.audioPlayerManager
                if audioPlayer.isPlaying {
                    state = .playing
                } else {
                    // Give a brief grace period by restarting loading timers
                    startLoadingDelayTimer()
                    startLoadingTimeoutTimer()
                }
            } else {
                startLoadingDelayTimer()
                startLoadingTimeoutTimer()
            }
            
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
    
    private func cleanupTimersExceptCountdown() {
        // Preserve countdown timer when transitioning to/from idle state
        let shouldPreserveCountdownTimer = (state == .idle || isTransitioningToIdle())
        
        if !shouldPreserveCountdownTimer {
            timer?.invalidate()
            timer = nil
        }
        
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
    
    private func isTransitioningToIdle() -> Bool {
        // Check if we're likely transitioning to idle based on current conditions
        guard let nextOccurrence = userPreferences.schedule.nextOccurrence else { return true }
        
        let timeUntil = nextOccurrence.timeIntervalSinceNow
        let hasCompleted = hasCompletedOccurrence(nextOccurrence)
        
        // Will likely end up in idle if completed or far from next occurrence
        return hasCompleted || timeUntil > 300 || timeUntil < -21600 // 5 min before or 6 hours after
    }
    
    // MARK: - Lazy Service Loading
    
    /// Load only basic observers (no heavy services)
    private func loadBasicObservers() async {
        // Only observe user preferences changes (no service dependencies)
        setupBasicObservers()
    }
    
    private func setupBasicObservers() {
        // Lightweight observers (no service loading)
        userPreferences.$schedule
            .sink { [weak self] newSchedule in
                self?.logger.log("📅 Schedule observer triggered: time=\(FormatterCache.shared.shortTimeFormatter.string(from: newSchedule.time))", level: .debug)
                // Use same pattern as settings observer for immediate UI updates
                Task { @MainActor in
                    self?.objectWillChange.send() // Force SwiftUI refresh
                    self?.debouncedUpdateState()
                    self?.scheduleNotificationsIfNeeded()
                }
            }
            .store(in: &cancellables)
        
        userPreferences.$settings
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                    self?.performStateUpdate()
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
            .sink { [weak self] _ in
                self?.debouncedUpdateState()
            }
            .store(in: &cancellables)
        
        welcomeScheduler.$isWelcomeReadyToPlay
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
                guard let self = self else { return }
                if self.state == .playing && didFinish {
                    // Trigger completion transition
                    self.transitionToRecentlyPlayed()
                    // One-time review gate after first successful completion
                    if !ReviewRequestManager.shared.hasPromptedAfterFirstCompletion {
                        self.showReviewGate = true
                    }
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
            // Check for stuck transitions and clear if needed
            if let self = self, self.isTransitioning {
                let timeSinceLastChange = Date().timeIntervalSince(self.lastStateChangeTime)
                if timeSinceLastChange > 2.0 {
                    // Transition has been stuck for more than 2 seconds, force clear
                    self.logger.log("⚠️ Clearing stuck transition after \(timeSinceLastChange)s", level: .warning)
                    self.isTransitioning = false
                }
            }
            self?.performStateUpdate()
        }
        
        if let workItem = updateStateWorkItem {
            workItem.perform()
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
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                self?.performStateUpdate()
            }
            return
        }
        
        isTransitioning = true
        lastStateChangeTime = now
        
        cleanupTimersExceptCountdown()
        
        // Check for welcome DayStart first (only if enabled)
        if !userPreferences.schedule.repeatDays.isEmpty {
            let welcomeScheduler = WelcomeDayStartScheduler.shared
            
            if welcomeScheduler.isWelcomePending {
                // Show preparing view while welcome is being prepared
                startPreparingState(isWelcome: true)
                logger.log("⏳ Welcome DayStart is being prepared - showing preparing view", level: .info)
                
                // Start polling for welcome audio
                Task {
                    await checkWelcomeAudioStatus()
                }
                isTransitioning = false
                return
            }
            
            if welcomeScheduler.isWelcomeReadyToPlay {
                // Show welcome ready screen - user must tap to start
                stateTransitionManager.transitionTo(.welcomeReady)
                logger.log("🎁 Welcome DayStart is ready - showing welcome ready screen", level: .info)
                isTransitioning = false
                return
            }
        }
        
        // Don't update state if currently playing audio
        if state == .playing {
            isTransitioning = false
            return
        }
        
        // Check if we need to skip today due to existing audio
        let hasAudioForToday = checkIfAudioExistsForToday()
        let nextOccurrence: Date?
        
        if hasAudioForToday {
            // Skip today and get tomorrow's occurrence
            nextOccurrence = userPreferences.schedule.nextOccurrenceAfterToday
        } else {
            // Use normal next occurrence
            nextOccurrence = userPreferences.schedule.nextOccurrence
        }
        
        guard let nextOccurrence = nextOccurrence else {
            // No schedule found
            withAnimation(.none) {
                stateTransitionManager.transitionTo(.idle, animated: false)
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
        
        let hasCompletedThisOccurrence = hasCompletedOccurrence(nextOccurrence)
        hasCompletedCurrentOccurrence = hasCompletedThisOccurrence
        
        // Simplified state logic - idle handles countdown display
        if hasCompletedThisOccurrence && timeUntil >= -sixHoursInSeconds {
            stateTransitionManager.transitionTo(.completed)
        } else if (timeUntil > 0 && timeUntil <= 300) || (timeUntil <= 0 && timeUntil >= -sixHoursInSeconds) {
            // Within 5 minutes of start time or past scheduled time - check if audio is ready
            if !hasCompletedThisOccurrence {
                checkAudioReadiness(for: nextOccurrence)
            } else {
                stateTransitionManager.transitionTo(.idle)
            }
        } else {
            // Default to idle state (which will show countdown if within 10 hours)
            stateTransitionManager.transitionTo(.idle)
            // Restart countdown display when returning to idle
            updateCountdownDisplay()
        }
        
        // Mark transition as complete
        isTransitioning = false
    }
    
    // Countdown functionality is now handled within idle state
    func updateCountdownDisplay() {
        guard let nextTime = nextDayStartTime else { return }
        let timeUntil = nextTime.timeIntervalSinceNow
        
        if timeUntil > 0 && timeUntil <= 36000 { // 10 hours
            updateCountdownText(timeInterval: timeUntil)
            
            // Set up timer if we don't have one
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { @MainActor [weak self] _ in
                    guard let self = self, let nextTime = self.nextDayStartTime else { return }
                    
                    let timeUntil = nextTime.timeIntervalSinceNow
                    
                    if timeUntil <= 0 {
                        self.timer?.invalidate()
                        self.timer = nil
                        // When countdown reaches 0, update state
                        self.updateState()
                    } else {
                        self.updateCountdownText(timeInterval: timeUntil)
                    }
                }
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
            stateTransitionManager.transitionTo(.playing)
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
        stateTransitionManager.transitionTo(.preparing)
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
        
        preparingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { @MainActor [weak self] _ in
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
                if self.state == .preparing {
                    self.connectionError = .timeout
                    self.state = .idle
                }
            }
        }
    }
    
    private func startPreparingMessageRotation() {
        // Set initial message
        currentMessageIndex = Int.random(in: 0..<preparingMessages.count)
        preparingMessage = preparingMessages[currentMessageIndex]
        
        preparingMessageTimer?.invalidate()
        
        // Rotate messages every 5-7 seconds
        preparingMessageTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5...7), repeats: true) { @MainActor [weak self] _ in
            guard let self = self else { return }
            
            self.currentMessageIndex = (self.currentMessageIndex + 1) % self.preparingMessages.count
            
            withAnimation(.easeInOut(duration: 0.3)) {
                self.preparingMessage = self.preparingMessages[self.currentMessageIndex]
            }
            
            // Reset timer with new random interval
            self.preparingMessageTimer?.invalidate()
            self.preparingMessageTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5...7), repeats: true) { @MainActor _ in
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
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { @MainActor [weak self] _ in
            Task {
                await self?.checkAudioStatusWithLimits(for: scheduledTime)
            }
        }
    }
    
    private func checkAudioStatusWithLimits(for scheduledTime: Date) async {
        guard let startTime = pollingStartTime else { return }
        
        pollingAttempts += 1
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Check if we've exceeded limits (3 minutes preparing + 5 minutes buffering attempts)
        if pollingAttempts >= maxPollingAttempts || elapsed >= maxPollingDuration {
            logger.log("⚠️ Polling timeout after \(pollingAttempts) attempts in \(elapsed)s", level: .warning)
            
            await MainActor.run {
                // Use appropriate error type based on elapsed time
                let error: ConnectionError = elapsed >= 180 ? .generationTimeout : .streamingTimeout
                handleFinalFailure(error: error, jobId: currentJobId)
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
                    
                    // Haptic feedback for early completion
                    HapticManager.shared.notification(type: .success)
                    
                    // Load audio services and start playing (will handle state transitions)
                    Task {
                        await loadAudioServicesAndStart(scheduledTime: scheduledTime)
                    }
                } else if audioStatus.success && audioStatus.status == "queued", let jobId = audioStatus.jobId {
                    logger.log("🚀 DayStart is queued, triggering immediate processing for job: \(jobId)", level: .info)
                    
                    // Trigger immediate processing
                    Task {
                        do {
                            try await serviceRegistry.supabaseClient.invokeProcessJob(jobId: jobId)
                            logger.log("✅ Successfully triggered processing for job: \(jobId)", level: .info)
                        } catch {
                            logger.logError(error, context: "Failed to trigger processing for job: \(jobId)")
                            // Continue polling normally if trigger fails
                        }
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
    
    // MARK: - Background Failure Persistence
    
    private func saveBackgroundFailure(_ error: ConnectionError) {
        UserDefaults.standard.set(error.errorCode, forKey: backgroundFailureKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: backgroundFailureTimestampKey)
        logger.log("💾 Saved background failure: \(error.errorCode)", level: .info)
    }
    
    private func loadAndCheckBackgroundFailure() -> ConnectionError? {
        guard let errorCode = UserDefaults.standard.string(forKey: backgroundFailureKey) else {
            return nil
        }
        
        let timestamp = UserDefaults.standard.double(forKey: backgroundFailureTimestampKey)
        let failureTime = Date(timeIntervalSince1970: timestamp)
        
        // Only show failures from the last hour
        if Date().timeIntervalSince(failureTime) > 3600 {
            clearBackgroundFailure()
            return nil
        }
        
        // Convert error code back to ConnectionError
        let error: ConnectionError
        switch errorCode {
        case "NETWORK_UNAVAILABLE": error = .noInternet
        case "SERVER_ERROR": error = .supabaseError
        case "GENERAL_TIMEOUT": error = .timeout
        case "GENERATION_FAILED": error = .generationFailed
        case "STREAMING_FAILED": error = .streamingFailed
        case "GENERATION_TIMEOUT": error = .generationTimeout
        case "STREAMING_TIMEOUT": error = .streamingTimeout
        default: return nil
        }
        
        logger.log("📱 Loaded background failure: \(errorCode)", level: .info)
        return error
    }
    
    private func clearBackgroundFailure() {
        UserDefaults.standard.removeObject(forKey: backgroundFailureKey)
        UserDefaults.standard.removeObject(forKey: backgroundFailureTimestampKey)
    }
    
    private func showBackgroundFailureToast(_ error: ConnectionError) {
        logger.log("🍞 Background failure toast: \(error.title)", level: .info)
        toastMessage = "DayStart failed while app was in background: \(error.title)"
        
        // Auto-clear toast message after 4 seconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
            self?.toastMessage = nil
        }
    }
    
    // MARK: - Enhanced Error Handling
    
    private func handleFinalFailure(error: ConnectionError, jobId: String? = nil) {
        logger.log("🚨 Final failure: \(error.errorCode)", level: .error)
        
        // Stop all timers and polling
        stopAllTimers()
        
        // Save failure for background persistence
        saveBackgroundFailure(error)
        
        // Mark job as failed if we have a job ID
        if let jobId = jobId {
            Task {
                do {
                    try await SupabaseClient.shared.markJobAsFailed(jobId: jobId, errorCode: error.errorCode)
                } catch {
                    logger.logError(error, context: "Failed to mark job as failed")
                }
            }
        }
        
        // Set error state
        connectionError = error
        state = .idle
        
        // Start auto-dismiss timer (2 minutes)
        startErrorDismissTimer()
    }
    
    private func startErrorDismissTimer() {
        errorDismissTimer?.invalidate()
        
        errorDismissTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { @MainActor [weak self] _ in
            self?.dismissError()
        }
    }
    
    private func dismissError() {
        errorDismissTimer?.invalidate()
        errorDismissTimer = nil
        connectionError = nil
        retryAttempts = 0
        currentJobId = nil
        failureStartTime = nil
        
        // Clear background failure
        clearBackgroundFailure()
        
        // Return to normal state
        updateState()
    }
    
    private func stopAllTimers() {
        timer?.invalidate()
        timer = nil
        pauseTimeoutTimer?.invalidate()
        pauseTimeoutTimer = nil
        loadingDelayTimer?.invalidate()
        loadingDelayTimer = nil
        loadingTimeoutTimer?.invalidate()
        loadingTimeoutTimer = nil
        preparingTimer?.invalidate()
        preparingTimer = nil
        preparingMessageTimer?.invalidate()
        preparingMessageTimer = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        errorDismissTimer?.invalidate()
        errorDismissTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
    }
    
    private func checkAndCreateJobIfNeeded(for scheduledTime: Date) async {
        do {
            let supabaseClient = serviceRegistry.supabaseClient
            let audioStatus = try await supabaseClient.getAudioStatus(for: scheduledTime)
            
            // If job doesn't exist or failed, create a new one
            if audioStatus.status == "not_found" || audioStatus.status == "failed" {
                logger.log("🔄 Creating on-demand job for \(scheduledTime) - status: \(audioStatus.status)", level: .info)
                
                // Load snapshot builder to get current data
                let snapshot = await serviceRegistry.snapshotBuilder.buildSnapshot(for: scheduledTime)
                
                // Use "NOW" for immediate processing since user clicked DayStart
                let jobResponse = try await supabaseClient.createJob(
                    for: Date(), // Use current time for "NOW" scheduling
                    targetDate: Calendar.current.startOfDay(for: scheduledTime), // But target the correct date
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
            
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { @MainActor [weak self] _ in
                Task {
                    await self?.checkWelcomeAudioStatusOnce()
                }
            }
        }
        
        // Initial check
        await checkWelcomeAudioStatusOnce()
    }
    
    private func checkAndCreateWelcomeJobIfNeeded() async {
        // Don't create jobs if user hasn't purchased
        guard case .purchased = PurchaseManager.shared.purchaseState else {
            logger.log("⚠️ Skipping welcome job creation - user hasn't purchased yet", level: .warning)
            return
        }
        
        do {
            let supabaseClient = serviceRegistry.supabaseClient
            let currentDate = Date()
            let audioStatus = try await supabaseClient.getAudioStatus(for: currentDate)
            
            // If job doesn't exist or failed, create a welcome job
            if audioStatus.status == "not_found" || audioStatus.status == "failed" {
                logger.log("🔄 Creating welcome job - status: \(audioStatus.status)", level: .info)
                
                // Load snapshot builder to get tomorrow's data for welcome DayStart
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
                let snapshot = await serviceRegistry.snapshotBuilder.buildSnapshot(for: tomorrow)
                
                let jobResponse = try await supabaseClient.createJob(
                    for: currentDate,
                    with: userPreferences.settings,
                    schedule: userPreferences.schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar,
                    isWelcome: true
                )
                
                logger.log("✅ Welcome job created: \(jobResponse.jobId ?? "unknown") with status: \(jobResponse.status ?? "unknown")", level: .info)
                
                // Validate that this is actually a welcome job
                if jobResponse.isWelcome != true {
                    logger.log("⚠️ WARNING: Created job is not marked as welcome! This may result in incorrect content.", level: .error)
                }
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
                    
                    // Load audio services and play (will handle state transitions)
                    Task {
                        await loadAudioServicesAndStart()
                        await startWelcomeDayStartWithSupabase()
                    }
                    
                    // Haptic feedback for early completion
                    HapticManager.shared.notification(type: .success)
                } else if audioStatus.success && audioStatus.status == "queued", let jobId = audioStatus.jobId {
                    logger.log("🚀 Welcome DayStart is queued, triggering immediate processing for job: \(jobId)", level: .info)
                    
                    // Trigger immediate processing
                    Task {
                        do {
                            try await serviceRegistry.supabaseClient.invokeProcessJob(jobId: jobId)
                            logger.log("✅ Successfully triggered processing for welcome job: \(jobId)", level: .info)
                        } catch {
                            logger.logError(error, context: "Failed to trigger processing for welcome job: \(jobId)")
                            // Continue polling normally if trigger fails
                        }
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
    
    func isDayStartScheduled(for date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard let weekDay = WeekDay(weekday: weekday) else { return false }
        return userPreferences.schedule.repeatDays.contains(weekDay)
    }
    
    private func checkIfAudioExistsForToday() -> Bool {
        // Check for regular DayStart audio
        if let todayScheduledTime = getTodayScheduledTime(),
           serviceRegistry.audioCache.hasAudio(for: todayScheduledTime) {
            return true
        }
        
        // Check for welcome DayStart audio (uses Date() for today)
        if serviceRegistry.audioCache.hasAudio(for: Date()) {
            return true
        }
        
        // Also check history as a backup
        let calendar = Calendar.current
        let hasHistoryToday = userPreferences.history.contains { dayStart in
            if let scheduledTime = dayStart.scheduledTime {
                return calendar.isDateInToday(scheduledTime)
            }
            return calendar.isDateInToday(dayStart.date)
        }
        
        return hasHistoryToday
    }
    
    func startDayStart() {
        logger.logUserAction("Start DayStart", details: ["time": Date().description])
        
        // Use today's scheduled time instead of nextDayStartTime
        guard let scheduledTime = getTodayScheduledTime() else {
            logger.log("❌ No scheduled time for DayStart today", level: .error)
            return
        }
        
        // Trigger snapshot update for remaining scheduled jobs
        triggerSnapshotUpdateAfterDayStart()
        
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
        
        // Don't cancel the entire welcome scheduler - we want polling to continue
        // Just update the UI state
        WelcomeDayStartScheduler.shared.isWelcomeReadyToPlay = false
        
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
    
    private func startWelcomeImmediately() {
        logger.logUserAction("Auto-start Welcome DayStart", details: ["time": Date().description])
        
        // Check network connectivity first
        guard NetworkMonitor.shared.isConnected else {
            connectionError = .noInternet
            state = .idle
            return
        }
        
        // Go directly to preparing state (skip welcome ready screen)
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
    
    func exitPlayingState() {
        logger.logUserAction("Exit Playing State", details: ["time": Date().description])
        
        // Clean up pause timeout timer
        stopPauseTimeoutTimer()
        
        // Stop loading timers if any
        stopLoadingTimers()
        
        // Check if this was a welcome DayStart being dismissed
        let isWelcomeFlow = WelcomeDayStartScheduler.shared.isWelcomeReadyToPlay || 
                           (currentDayStart?.scheduledTime != nil && 
                            abs(currentDayStart!.scheduledTime!.timeIntervalSince(Date())) < 300)
        
        // Reset current DayStart
        currentDayStart = nil
        
        if isWelcomeFlow {
            // For welcome flow, clean up welcome scheduler and go to idle
            WelcomeDayStartScheduler.shared.cancelWelcomeDayStart()
            state = .idle
            connectionError = nil
            // Set up idle state manually without calling updateState()
            setupIdleStateAfterExit()
        } else {
            // For regular DayStart, go to idle and set up proper idle content
            state = .idle
            connectionError = nil
            
            // Set up idle state manually without calling updateState()
            setupIdleStateAfterExit()
        }
    }
    
    private func setupIdleStateAfterExit() {
        // Calculate next DayStart time based on current schedule
        // Check if we need to skip today due to existing audio
        if checkIfAudioExistsForToday() {
            nextDayStartTime = userPreferences.schedule.nextOccurrenceAfterToday
        } else {
            nextDayStartTime = userPreferences.schedule.nextOccurrence
        }
        
        // Start countdown display if there's a scheduled time
        if nextDayStartTime != nil {
            updateCountdownDisplay()
        } else {
            // No schedule set - show appropriate message
            countdownText = ""
        }
        
        // Clear any completion flags since user manually exited
        hasCompletedCurrentOccurrence = false
        
        logger.log("🏠 Idle state set up after user exit - next: \(nextDayStartTime?.description ?? "none")", level: .info)
    }
    
    /// Trigger snapshot update after playing a DayStart
    private func triggerSnapshotUpdateAfterDayStart() {
        // Only trigger if user has active schedule
        guard !userPreferences.schedule.repeatDays.isEmpty else {
            return
        }
        
        // Trigger update in background for remaining scheduled jobs
        Task {
            await ServiceRegistry.shared.snapshotUpdateManager.updateSnapshotsForUpcomingJobs(trigger: .dayStartPlayed)
        }
    }
    
    /// Check if today needs a job created (backfill for users returning after being away)
    private func checkAndCreateTodayJobIfNeeded() async {
        do {
            let created = try await serviceRegistry.supabaseClient.createTodayJobIfNeeded(
                with: userPreferences.settings,
                schedule: userPreferences.schedule
            )
            
            if created {
                logger.log("✅ Today job backfill created successfully", level: .info)
            }
        } catch {
            logger.logError(error, context: "Failed to create today job backfill")
            // Don't show UI error for backfill failures - this is background operation
        }
    }
    
    /// Initialize the snapshot update system
    private func initializeSnapshotUpdateSystem() async {
        logger.log("🔄 Initializing snapshot update system", level: .info)
        await serviceRegistry.snapshotUpdateManager.initialize()
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
                    // Update jobId for share functionality
                    if let jobId = audioStatus.jobId {
                        dayStartWithScheduledTime.jobId = jobId
                        currentDayStart?.jobId = jobId
                    }
                    
                    // Update transcript from audio status if available
                    if let transcript = audioStatus.transcript, !transcript.isEmpty {
                        dayStartWithScheduledTime.transcript = transcript
                        currentDayStart?.transcript = transcript
                    }
                    
                    // Update duration from audio status if available
                    if let duration = audioStatus.duration {
                        dayStartWithScheduledTime.duration = TimeInterval(duration)
                        currentDayStart?.duration = TimeInterval(duration)
                    }
                    
                    // Update history with transcript and duration
                    userPreferences.updateHistory(
                        with: dayStartWithScheduledTime.id,
                        transcript: audioStatus.transcript,
                        duration: audioStatus.duration.map { TimeInterval($0) }
                    )
                    
                    await streamAudio(from: audioUrl)
                    
                    // Background download
                    let dayStartId = dayStartWithScheduledTime.id
                    Task {
                        let audioDownloader = ServiceRegistry.shared.audioDownloader
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
        
        // Add to history immediately with placeholder (like regular DayStart)
        currentDayStart = welcomeDayStart
        userPreferences.addToHistory(welcomeDayStart)
        let welcomeDayStartId = welcomeDayStart.id
        
        do {
            // LAZY: SupabaseClient already loaded from previous call
            let audioStatus = try await serviceRegistry.supabaseClient.getAudioStatus(for: Date())
            
            if audioStatus.success && audioStatus.status == "ready", let audioUrl = audioStatus.audioUrl {
                // Update jobId for share functionality
                if let jobId = audioStatus.jobId {
                    welcomeDayStart.jobId = jobId
                    currentDayStart?.jobId = jobId
                }
                
                // Update transcript from audio status if available
                if let transcript = audioStatus.transcript, !transcript.isEmpty {
                    welcomeDayStart.transcript = transcript
                    currentDayStart?.transcript = transcript
                }
                
                // Update duration from audio status if available
                if let duration = audioStatus.duration {
                    welcomeDayStart.duration = TimeInterval(duration)
                    currentDayStart?.duration = TimeInterval(duration)
                }
                
                // Update history with transcript and duration (like regular DayStart)
                userPreferences.updateHistory(
                    with: welcomeDayStartId,
                    transcript: audioStatus.transcript,
                    duration: audioStatus.duration.map { TimeInterval($0) }
                )
                
                await streamAudio(from: audioUrl)
                
                // Background download (like regular DayStart)
                Task {
                    let audioDownloader = ServiceRegistry.shared.audioDownloader
                    let success = await audioDownloader.download(from: audioUrl, for: Date())
                    if success {
                        await MainActor.run {
                            let audioPath = ServiceRegistry.shared.audioCache.getAudioPath(for: Date())
                            UserPreferences.shared.updateHistory(
                                with: welcomeDayStartId,
                                audioFilePath: audioPath.path
                            )
                        }
                    }
                }
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
        // Start buffering state immediately
        await MainActor.run {
            self.state = .buffering
        }
        
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
                    
                    // Stop polling since audio is now ready and playing
                    WelcomeDayStartScheduler.shared.stopAudioPolling()
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
        
        // Try scheduledTime first, then fall back to date
        if let scheduledTime = dayStart.scheduledTime,
           audioCache.hasAudio(for: scheduledTime) {
            let audioUrl = audioCache.getAudioPath(for: scheduledTime)
            audioPlayer.loadAudio(from: audioUrl)
        } else if audioCache.hasAudio(for: dayStart.date) {
            // Fallback: try using the completion date
            let audioUrl = audioCache.getAudioPath(for: dayStart.date)
            audioPlayer.loadAudio(from: audioUrl)
        } else {
            // No cached audio available for replay - this shouldn't happen
            // but if it does, we'll load without audio
            logger.log("⚠️ No cached audio found for replay - scheduledTime: \(dayStart.scheduledTime?.description ?? "nil"), date: \(dayStart.date)", level: .warning)
            audioPlayer.loadAudio()
        }
        
        audioPlayer.play()
        state = .playing
        stopPauseTimeoutTimer()
    }
    
    // MARK: - Helper Methods (Lightweight)
    
    private func generateBasicDayStart(for settings: UserSettings) -> DayStartData {
        return DayStartData(
            jobId: nil, // No job ID for offline content
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
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
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
        
        // No delay needed since buffering state shows immediate feedback
        // Start loading messages immediately for buffering state
        loadingMessages.startRotatingMessages()
    }
    
    private func startLoadingTimeoutTimer() {
        loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { @MainActor [weak self] _ in
            guard let self = self else { return }
            // Only act if we're still buffering and not actually playing
            if self.state == .buffering,
               self.serviceRegistry.loadedServices.contains("AudioPlayerManager"),
               self.serviceRegistry.audioPlayerManager.isPlaying == false {
                self.stopLoadingTimers()
                self.connectionError = .timeout
                self.state = .idle
            } else {
                // No error if playback started or state moved on
                self.stopLoadingTimers()
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
    
    // MARK: - Manual Refresh
    
    func manualRefresh() async {
        // Only allow refresh in appropriate states
        guard state == .idle || state == .completed else {
            logger.log("🔄 Manual refresh blocked - inappropriate state: \(state)", level: .info)
            return
        }
        
        // Check 4-hour lockout through existing business logic
        guard let nextTime = nextDayStartTime, 
              !userPreferences.isWithinLockoutPeriod(of: nextTime) else {
            await MainActor.run {
                toastMessage = "Please wait before requesting your next DayStart"
            }
            logger.log("🔄 Manual refresh blocked - 4-hour lockout active", level: .info)
            return
        }
        
        await MainActor.run {
            isManualRefreshing = true
            // Haptic feedback
            HapticManager.shared.impact(style: .light)
            logger.log("🔄 Manual refresh started", level: .info)
        }
        
        // Store start time for minimum duration
        let refreshStartTime = Date()
        
        // Use existing audio status check logic
        if let nextTime = nextDayStartTime {
            await checkAudioStatus(for: nextTime)
        } else {
            // Update other state without audio check
            await MainActor.run {
                validateAndUpdateState()
            }
        }
        
        // Ensure minimum 2.5 second duration for UX feedback
        let elapsed = Date().timeIntervalSince(refreshStartTime)
        let minimumDuration: TimeInterval = 2.5
        
        if elapsed < minimumDuration {
            try? await Task.sleep(nanoseconds: UInt64((minimumDuration - elapsed) * 1_000_000_000))
        }
        
        await MainActor.run {
            isManualRefreshing = false
            logger.log("🔄 Manual refresh completed", level: .info)
        }
    }
    
    // MARK: - Pause Timeout Management
    
    private func startPauseTimeoutTimer() {
        stopPauseTimeoutTimer()
        
        pauseTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { @MainActor [weak self] _ in
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