import SwiftUI
import AVFoundation
import Combine

enum WelcomeGenerationStage: String, CaseIterable {
    case connecting = "connecting"
    case fetching = "fetching"
    case analyzing = "analyzing"
    case scripting = "scripting"
    case recording = "recording"
    case finalizing = "finalizing"
    
    var displayText: String {
        switch self {
        case .connecting:
            return "Connecting to secure servers..."
        case .fetching:
            return "Fetching fresh news, weather, stocks..."
        case .analyzing:
            return "Analyzing your preferences..."
        case .scripting:
            return "Crafting your personalized script..."
        case .recording:
            return "Creating high-quality audio..."
        case .finalizing:
            return "Finalizing your DayStart..."
        }
    }
    
    var icon: String {
        switch self {
        case .connecting:
            return "📡"
        case .fetching:
            return "📰"
        case .analyzing:
            return "🧠"
        case .scripting:
            return "✍️"
        case .recording:
            return "🎙️"
        case .finalizing:
            return "✨"
        }
    }
    
    var estimatedDuration: TimeInterval {
        switch self {
        case .connecting:
            return 1.0
        case .fetching:
            return 3.0
        case .analyzing:
            return 2.0
        case .scripting:
            return 5.0
        case .recording:
            return 12.0 // Longest stage
        case .finalizing:
            return 2.0
        }
    }
}

struct WelcomeDayStartView: View {
    let onComplete: () -> Void
    let preferences: OnboardingPreferences
    
    @State private var currentStage: WelcomeGenerationStage = .connecting
    @State private var progress: Double = 0.0
    @State private var hasStartedGeneration = false
    @State private var generationStartTime: Date?
    @State private var stageTimer: Timer?
    @State private var timeoutTimer: Timer?
    @State private var audioURL: URL?
    @State private var showPlayer = false
    @State private var showError = false
    @State private var shouldGrantTrial = false
    @State private var animationTrigger = false
    @State private var textOpacity: Double = 0.0
    @State private var currentJobStatus: String = "connecting"
    @State private var stageStartTime: Date = Date()
    
    @ObservedObject private var welcomeScheduler = WelcomeDayStartScheduler.shared
    @ObservedObject private var audioManager = AudioPlayerManager.shared
    private let logger = DebugLogger.shared
    
    private let timeoutDuration: TimeInterval = 180.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main scrollable content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer(minLength: geometry.size.height * 0.06)
                        
                        // Main content area
                        if showError {
                            errorView(geometry: geometry)
                        } else if showPlayer {
                            playerView(geometry: geometry)
                        } else {
                            generationView(geometry: geometry)
                        }
                        
                        Spacer(minLength: max(140, geometry.size.height * 0.25))
                    }
                }
                .scrollIndicators(.hidden)
                
                // Fixed bottom button overlay for all states
                if showError {
                    OnboardingBottomButton(
                        buttonText: "Continue with Free Trial",
                        action: {
                            logger.logUserAction("Welcome error continue tapped - trial granted")
                            onComplete()
                        },
                        geometry: geometry,
                        animationTrigger: true,
                        textOpacity: 1.0
                    )
                } else if showPlayer {
                    OnboardingBottomButton(
                        buttonText: "Continue",
                        action: {
                            logger.logUserAction("Welcome DayStart CTA tapped")
                            onComplete()
                        },
                        geometry: geometry,
                        animationTrigger: true,
                        textOpacity: textOpacity,
                        poweredByText: "You'll be able to revisit later",
                        poweredByURL: nil
                    )
                } else {
                    OnboardingBottomButton(
                        buttonText: "Continue",
                        action: {
                            logger.logUserAction("Welcome DayStart Skip tapped during generation")
                            onComplete()
                        },
                        geometry: geometry,
                        animationTrigger: true,
                        textOpacity: textOpacity,
                        poweredByText: "You'll be able to revisit later",
                        poweredByURL: nil
                    )
                }
            }
        }
        .onAppear {
            startGeneration()
            startAnimations()
        }
        .onDisappear {
            cleanup()
            resetWelcomeState()
        }
        .onReceive(welcomeScheduler.$isWelcomeReadyToPlay) { isReady in
            if isReady {
                currentJobStatus = "ready"
                handleGenerationComplete()
            }
        }
        .onReceive(welcomeScheduler.$currentJobStatus) { newStatus in
            // Prevent duplicate status updates
            guard newStatus != currentJobStatus else { return }
            logger.log("📊 Job status updated: \(currentJobStatus) → \(newStatus)", level: .debug)
            currentJobStatus = newStatus
        }
        .onChange(of: currentJobStatus) { newStatus in
            logger.log("📊 Job status changed: \(newStatus)", level: .debug)
        }
    }
    
    private func generationView(geometry: GeometryProxy) -> some View {
        VStack(spacing: geometry.size.height * 0.04) {
            // Stage icon animation - fixed positioning with no layout shifts
            ZStack {
                // Invisible placeholder to maintain consistent size
                Text("📡")
                    .font(.system(size: min(80, geometry.size.width * 0.2)))
                    .opacity(0)
                
                // Actual icon with animations
                Text(currentStage.icon)
                    .font(.system(size: min(80, geometry.size.width * 0.2)))
                    .scaleEffect(animationTrigger ? 1.1 : 0.9)
                    .rotationEffect(.degrees(animationTrigger ? 5 : -5))
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
                    .id(currentStage) // Force SwiftUI to treat as new view for instant updates
            }
            .frame(width: min(80, geometry.size.width * 0.2), height: min(80, geometry.size.width * 0.2))
            .frame(maxWidth: .infinity) // Center in available space
            .animation(nil) // Disable all layout animations
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(BananaTheme.ColorToken.secondaryText.opacity(0.3), lineWidth: 8)
                    .frame(width: min(180, geometry.size.width * 0.4))
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: min(180, geometry.size.width * 0.4))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: min(24, geometry.size.width * 0.06), weight: .bold, design: .rounded))
                    .foregroundColor(BananaTheme.ColorToken.text)
            }
            
            VStack(spacing: geometry.size.height * 0.015) {
                Text("Creating Your Welcome DayStart")
                    .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .multilineTextAlignment(.center)
                    .opacity(textOpacity)
                
                Text(currentStage.displayText)
                    .font(.system(size: min(18, geometry.size.width * 0.045), weight: .medium))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, geometry.size.width * 0.1)
                    .opacity(textOpacity)
                    .animation(.easeInOut(duration: 0.3), value: currentStage)
                
                VStack(spacing: 4) {
                    Text("This will just take a moment...")
                        .font(.system(size: min(14, geometry.size.width * 0.035), weight: .regular))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .italic()
                    
                    Text("Going forward, your DayStart will be ready before your scheduled time.")
                        .font(.system(size: min(13, geometry.size.width * 0.032), weight: .regular))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .opacity(textOpacity * 0.8)
            }
            .padding(.horizontal, geometry.size.width * 0.05)
        }
    }
    
    private func playerView(geometry: GeometryProxy) -> some View {
        VStack(spacing: geometry.size.height * 0.04) {
            // Success animation
            HStack(spacing: 15) {
                ForEach(["🎉", "✨", "🎉"], id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: min(40, geometry.size.width * 0.08)))
                        .scaleEffect(animationTrigger ? 1.2 : 0.8)
                        .rotationEffect(.degrees(animationTrigger ? 15 : -15))
                        .animation(.easeInOut(duration: 1.0).repeatForever().delay(Double(["🎉", "✨", "🎉"].firstIndex(of: emoji) ?? 0) * 0.3), value: animationTrigger)
                }
            }
            
            VStack(spacing: geometry.size.height * 0.02) {
                Text("Your Welcome DayStart is Ready!")
                    .font(.system(size: min(28, geometry.size.width * 0.07), weight: .bold, design: .rounded))
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .multilineTextAlignment(.center)
                    .opacity(textOpacity)
                
                Text("Listen to your personalized briefing")
                    .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
                    .opacity(textOpacity)
            }
        
        // Simple audio player
        if let audioURL = audioURL {
            VStack(spacing: 16) {
                // Play/Pause button
                Button(action: {
                    if audioManager.isPlaying {
                        audioManager.pause()
                    } else {
                        playWelcomeAudio()
                    }
                }) {
                    Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: min(64, geometry.size.width * 0.16)))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                }
                .scaleEffect(audioManager.isPlaying ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: audioManager.isPlaying)
                
                // Progress bar with slider (if playing)
                if audioManager.isPlaying || audioManager.currentTime > 0 {
                    VStack(spacing: 8) {
                        // Custom slider with bubble
                        GeometryReader { sliderGeometry in
                            ZStack(alignment: .leading) {
                                // Track background
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(BananaTheme.ColorToken.secondaryText.opacity(0.3))
                                    .frame(height: 4)
                                
                                // Filled track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(BananaTheme.ColorToken.primary)
                                    .frame(width: sliderGeometry.size.width * CGFloat(audioManager.currentTime / max(audioManager.duration, 1.0)), height: 4)
                                
                                // Slider bubble
                                Circle()
                                    .fill(BananaTheme.ColorToken.primary)
                                    .frame(width: 16, height: 16)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                    .offset(x: sliderGeometry.size.width * CGFloat(audioManager.currentTime / max(audioManager.duration, 1.0)) - 8)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                let progress = min(max(0, value.location.x / sliderGeometry.size.width), 1)
                                                let newTime = progress * audioManager.duration
                                                audioManager.seek(to: newTime)
                                            }
                                    )
                            }
                            .frame(height: 16)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let progress = min(max(0, location.x / sliderGeometry.size.width), 1)
                                let newTime = progress * audioManager.duration
                                audioManager.seek(to: newTime)
                            }
                        }
                        .frame(height: 16)
                        
                        HStack {
                            Text(formatTime(audioManager.currentTime))
                                .font(.caption)
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            Spacer()
                            Text(formatTime(audioManager.duration))
                                .font(.caption)
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(BananaTheme.ColorToken.card)
                    .shadow(color: BananaTheme.ColorToken.shadow.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, geometry.size.width * 0.1)
        }
        }
    }
    
    private func errorView(geometry: GeometryProxy) -> some View {
        VStack(spacing: geometry.size.height * 0.03) {
            Text("🎁")
                .font(.system(size: min(80, geometry.size.width * 0.2)))
                .scaleEffect(animationTrigger ? 1.1 : 0.9)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animationTrigger)
            
            VStack(spacing: geometry.size.height * 0.02) {
                Text("Something Went Wrong...")
                    .font(.system(size: min(24, geometry.size.width * 0.06), weight: .bold, design: .rounded))
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .multilineTextAlignment(.center)
                
                Text("But we've got you covered! We've given you a **free week** of DayStart to try out.")
                    .font(.system(size: min(16, geometry.size.width * 0.04), weight: .medium))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, geometry.size.width * 0.1)
            }
        }
    }
    
    private func startGeneration() {
        guard !hasStartedGeneration else { return }
        hasStartedGeneration = true
        generationStartTime = Date()
        
        logger.log("🎉 Starting welcome DayStart generation", level: .info)
        
        // Create job using existing scheduler but with onboarding preferences
        createWelcomeJobWithPreferences()
        
        // Start stage progression
        startStageProgression()
        
        // Start timeout timer
        startTimeoutTimer()
    }
    
    private func createWelcomeJobWithPreferences() {
        // Set flag to indicate we're in onboarding mode
        UserDefaults.standard.set(true, forKey: "shouldAutoStartWelcome")
        
        // Save preferences to UserPreferences first so scheduler can use them
        savePreferencesToUserDefaults()
        
        // Create the job directly instead of using scheduler's background logic
        Task {
            do {
                let settings = UserPreferences.shared.settings
                let schedule = UserPreferences.shared.schedule
                let snapshot = await SnapshotBuilder.shared.buildSnapshot(for: Date())
                
                _ = try await SupabaseClient.shared.createJob(
                    for: Date(),
                    with: settings,
                    schedule: schedule,
                    locationData: snapshot.location,
                    weatherData: snapshot.weather,
                    calendarEvents: snapshot.calendar,
                    isWelcome: true
                )
                
                logger.log("✅ Welcome job created successfully", level: .info)
                
                // Now start polling
                await MainActor.run {
                    welcomeScheduler.startAudioPollingImmediately()
                }
            } catch {
                logger.logError(error, context: "Failed to create welcome job in onboarding")
                await MainActor.run {
                    handleGenerationFailure()
                }
            }
        }
    }
    
    private func savePreferencesToUserDefaults() {
        let settings = UserSettings(
            preferredName: preferences.name.isEmpty ? "" : preferences.name,
            includeWeather: preferences.includeWeather,
            includeNews: preferences.includeNews,
            includeSports: preferences.includeSports,
            includeStocks: preferences.includeStocks,
            stockSymbols: preferences.stockSymbols.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            includeCalendar: preferences.includeCalendar,
            includeQuotes: preferences.includeQuotes,
            quotePreference: preferences.selectedQuoteType,
            selectedVoice: preferences.selectedVoice ?? VoiceOption.voice1,
            dayStartLength: 60,
            themePreference: .system,
            selectedSports: [],
            selectedNewsCategories: [],
            allowReengagementNotifications: true
        )
        
        let schedule = DayStartSchedule(
            time: preferences.selectedTime,
            repeatDays: preferences.selectedDays,
            skipTomorrow: false
        )
        
        // Temporarily save to UserPreferences so scheduler can access them
        UserPreferences.shared.settings = settings
        UserPreferences.shared.schedule = schedule
    }
    
    private func startStageProgression() {
        var stageIndex = 0
        let stages = WelcomeGenerationStage.allCases
        
        // Start with first stage immediately
        currentStage = stages[0]
        
        stageTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            
            let elapsedTime = Date().timeIntervalSince(generationStartTime ?? Date())
            let stageElapsedTime = Date().timeIntervalSince(stageStartTime)
            
            // Status-based progression mapped to actual job lifecycle
            let newStageIndex: Int
            switch currentJobStatus {
            case "connecting":
                // Before job is created - stay in connecting stage
                newStageIndex = 0 // connecting
            case "queued":
                // Job created but not yet processing - fetching/analyzing
                if elapsedTime < 8 {
                    newStageIndex = 1 // fetching
                } else {
                    newStageIndex = 2 // analyzing
                }
            case "processing":
                // Job is actively being processed - scripting/recording
                let processingTime = elapsedTime - 10.0 // Assume ~10s to get to processing
                if processingTime < 10 {
                    newStageIndex = 3 // scripting
                } else {
                    newStageIndex = 4 // recording
                }
            case "ready":
                newStageIndex = 5 // finalizing
            default:
                // For initial state, stay in connecting
                newStageIndex = 0
            }
            
            // Update stage if changed
            if newStageIndex != stageIndex && newStageIndex < stages.count {
                stageIndex = newStageIndex
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        self.currentStage = stages[stageIndex]
                        // Don't reset stageStartTime - use cumulative time instead
                    }
                }
            }
            
            // Smoother progress based on status - aligned with actual job lifecycle
            let targetProgress: Double
            switch currentJobStatus {
            case "connecting":
                // Initial state before job is created - very slow progress
                targetProgress = min(0.05, elapsedTime / 20.0)
            case "queued":
                // Job created but waiting in queue - progress from 5% to 25%
                let queueProgress = min(0.2, (elapsedTime - 5.0) / 30.0)
                targetProgress = 0.05 + queueProgress
            case "processing":
                // Job actively being processed - progress from 25% to 95%
                let processingProgress = min(0.7, (elapsedTime - 15.0) / 50.0)
                targetProgress = 0.25 + processingProgress
            case "ready":
                targetProgress = 1.0
            default:
                // Initial connecting state
                targetProgress = min(0.05, elapsedTime / 20.0)
            }
            
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.progress = targetProgress
                }
            }
        }
    }
    
    private func startTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutDuration, repeats: false) { _ in
            Task { @MainActor in
                // Only fail if we haven't already succeeded
                if !self.showPlayer && !self.showError {
                    self.handleGenerationFailure()
                }
            }
        }
    }
    
    private func handleGenerationComplete() {
        logger.log("✅ Welcome generation complete", level: .info)
        cleanup()
        
        // Get audio URL
        Task {
            do {
                let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: Date())
                if let url = audioStatus.audioUrl {
                    await MainActor.run {
                        self.audioURL = url
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            self.progress = 1.0
                            self.showPlayer = true
                        }
                        
                        // Mark that user has experienced welcome DayStart
                        UserDefaults.standard.set(true, forKey: "hasExperiencedWelcomeDayStart")
                        UserDefaults.standard.set(Date(), forKey: "welcomeExperienceDate")
                        UserDefaults.standard.set(Date(), forKey: "welcomeCreationDate")
                        
                        // Auto-play the welcome
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.playWelcomeAudio()
                        }
                    }
                } else {
                    handleGenerationFailure()
                }
            } catch {
                handleGenerationFailure()
            }
        }
    }
    
    private func handleGenerationFailure() {
        logger.log("❌ Welcome generation failed, auto-granting free trial", level: .warning)
        cleanup()
        
        // Auto-grant 7-day trial as compensation
        grantCompensationTrial()
        
        shouldGrantTrial = true
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showError = true
        }
    }
    
    private func grantCompensationTrial() {
        // Set a flag that can be checked by the paywall to automatically apply trial
        UserDefaults.standard.set(true, forKey: "welcomeGenerationFailedTrialGranted")
        UserDefaults.standard.set(Date(), forKey: "welcomeTrialGrantedDate")
        
        logger.log("✅ Compensation trial flag set for welcome generation failure", level: .info)
        
        // Also log this for analytics/support
        logger.logUserAction("Welcome generation failed - auto trial granted")
    }
    
    private func playWelcomeAudio() {
        guard let audioURL = audioURL else { return }
        audioManager.loadAudio(from: audioURL) { success, error in
            if success {
                DispatchQueue.main.async {
                    self.audioManager.play()
                }
            } else {
                self.logger.logError(error ?? NSError(domain: "WelcomeAudio", code: -1), context: "Failed to load welcome audio")
            }
        }
    }
    
    private func startAnimations() {
        withAnimation(.easeIn(duration: 0.5)) {
            textOpacity = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.linear(duration: 0.1)) {
                animationTrigger = true
            }
        }
    }
    
    private func cleanup() {
        stageTimer?.invalidate()
        stageTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    private func resetWelcomeState() {
        // Clear the onboarding flag
        UserDefaults.standard.removeObject(forKey: "shouldAutoStartWelcome")
        
        // Reset the welcome scheduler state when navigating away
        welcomeScheduler.cancelWelcomeDayStart()
        
        // Reset our local state
        hasStartedGeneration = false
        generationStartTime = nil
        audioURL = nil
        showPlayer = false
        showError = false
        shouldGrantTrial = false
        progress = 0.0
        currentStage = .connecting
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct OnboardingPreferences {
    let name: String
    let selectedTime: Date
    let selectedDays: Set<WeekDay>
    let includeWeather: Bool
    let includeNews: Bool
    let includeSports: Bool
    let includeStocks: Bool
    let stockSymbols: String
    let includeCalendar: Bool
    let includeQuotes: Bool
    let selectedQuoteType: QuotePreference
    let selectedVoice: VoiceOption?
}