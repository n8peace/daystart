import SwiftUI

// MARK: - Instant Response Button Style for Phase 1 Optimization
struct InstantResponseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(BananaTheme.ColorToken.primary)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                    .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            )
    }
}

// MARK: - Phase 2 Micro-Components for Performance
struct HomeHeaderView: View {
    let userName: String
    let timeBasedGreeting: String
    
    var body: some View {
        VStack(spacing: 12) {
            if !userName.isEmpty {
                Text("\(timeBasedGreeting), \(userName)")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
        }
    }
}

struct PrimaryActionView: View {
    let state: HomeViewModel.AppState
    let nextTime: Date?
    let hasCompleted: Bool
    let showNoSchedule: Bool
    let connectionError: ConnectionError?
    let onStartTapped: () -> Void
    let onEditTapped: () -> Void
    let onReplayTapped: () -> Void
    
    var body: some View {
        VStack {
            switch state {
            case .idle:
                if connectionError != nil {
                    // No button shown for connection errors
                    EmptyView()
                } else if showNoSchedule {
                    Button(action: onEditTapped) {
                        Label("Schedule DayStart", systemImage: "calendar.badge.plus")
                            .adaptiveFont(BananaTheme.Typography.headline)
                            .foregroundColor(BananaTheme.ColorToken.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                    }
                    .buttonStyle(InstantResponseStyle())
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(BananaTheme.ColorToken.text)
                    )
                    .padding(.horizontal, 40)
                } else if let _ = nextTime, !hasCompleted {
                    Button(action: onStartTapped) {
                        Text("DayStart")
                            .adaptiveFont(BananaTheme.Typography.title)
                            .fontWeight(.bold)
                            .foregroundColor(BananaTheme.ColorToken.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                    }
                    .buttonStyle(InstantResponseStyle())
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                    )
                    .padding(.horizontal, 40)
                }
            case .welcomeReady:
                Button(action: onStartTapped) {
                    Text("DayStart")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .fontWeight(.bold)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                }
                .buttonStyle(InstantResponseStyle())
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                )
                .padding(.horizontal, 40)
            case .ready:
                Button(action: onStartTapped) {
                    Text(hasCompleted ? "Replay" : "DayStart")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .fontWeight(.bold)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                }
                .buttonStyle(InstantResponseStyle())
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                )
                .padding(.horizontal, 40)
            case .completed:
                Button(action: onReplayTapped) {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                }
                .buttonStyle(InstantResponseStyle())
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(BananaTheme.ColorToken.primary)
                )
                .padding(.horizontal, 40)
            default:
                EmptyView()
            }
        }
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var showEditSchedule = false
    @State private var showHistory = false
    @EnvironmentObject var userPreferences: UserPreferences
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var welcomeScheduler = WelcomeDayStartScheduler.shared
    // Removed heavy @ObservedObject - access directly when needed
    // Removed heavy @ObservedObject - access directly when needed
    @State private var previousState: HomeViewModel.AppState = .idle
    @State private var showStreakCelebration = false
    @State private var celebrationStreak = 0
    @State private var tomorrowWeatherForecast: String?
    @State private var isLoadingForecast = false
    @State private var isViewVisible = true
    @Environment(\.scenePhase) var scenePhase
    private let hapticManager = HapticManager.shared
    // Removed early LocationManager init - will access when needed
    private let formatters = FormatterCache.shared
    
    private func formattedDate(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let sevenDaysFromToday = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        
        if viewModel.isNextDayStartToday {
            return "Today, \(formatters.monthDayFormatter.string(from: date))"
        } else if viewModel.isNextDayStartTomorrow {
            return "Tomorrow, \(formatters.monthDayFormatter.string(from: date))"
        } else if date < sevenDaysFromToday {
            // Within next 7 days - add day name
            return "\(formatters.fullDayFormatter.string(from: date)), \(formatters.monthDayFormatter.string(from: date))"
        } else {
            return formatters.monthDayFormatter.string(from: date)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                DayStartGradientBackground()
                
                VStack(spacing: 0) {
                    HomeHeaderView(
                        userName: userPreferences.settings.preferredName,
                        timeBasedGreeting: timeBasedGreeting
                    )
                    .padding(.top, 20)
                    
                    // Main content in upper area
                    VStack {
                        Spacer(minLength: 40)
                        
                        mainContentView
                            .animation(isViewVisible ? .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0) : .none, value: viewModel.state)
                        
                        Spacer(minLength: 60)
                    }
                    
                    // Primary actions in thumb-friendly bottom zone
                    VStack(spacing: 20) {
                        PrimaryActionView(
                            state: viewModel.state,
                            nextTime: viewModel.nextDayStartTime,
                            hasCompleted: viewModel.hasCompletedCurrentOccurrence,
                            showNoSchedule: viewModel.showNoScheduleMessage,
                            connectionError: viewModel.connectionError,
                            onStartTapped: { 
                                hapticManager.impact(style: .medium)
                                if viewModel.state == .welcomeReady {
                                    viewModel.startWelcomeDayStart()
                                } else {
                                    viewModel.startDayStart()
                                }
                            },
                            onEditTapped: { 
                                hapticManager.impact(style: .light)
                                showEditSchedule = true 
                            },
                            onReplayTapped: {
                                hapticManager.impact(style: .light)
                                if let dayStart = viewModel.currentDayStart {
                                    viewModel.replayDayStart(dayStart)
                                }
                            }
                        )
                        .animation(isViewVisible ? .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0) : .none, value: viewModel.state)
                        
                        if viewModel.state == .playing {
                            AudioPlayerView(dayStart: viewModel.currentDayStart)
                                .onAppear {
                                    DebugLogger.shared.log("🎵 HomeView: AudioPlayerView appeared", level: .info)
                                }
                                .onDisappear {
                                    DebugLogger.shared.log("🎵 HomeView: AudioPlayerView disappeared", level: .info)
                                }
                        }
                        
                        // Streak counter at bottom
                        if StreakManager.shared.currentStreak > 0 {
                            streakCounterView
                        }
                        
                        // Weekly progress indicator at bottom
                        if StreakManager.shared.currentStreak > 0 {
                            weeklyProgressView
                        }
                    }
                    .padding(.bottom, 30)
                }
                .padding()
                .onChange(of: viewModel.state) { newState in
                    let logger = DebugLogger.shared
                    logger.log("🎵 HomeView: State changed from \(previousState) to \(newState)", level: .info)
                    logger.log("🎵 HomeView: currentDayStart is \(viewModel.currentDayStart?.id.uuidString ?? "nil")", level: .info)
                    handleStateTransition(from: previousState, to: newState)
                    previousState = newState
                }
                .onAppear {
                    previousState = viewModel.state
                }
                .onChange(of: scenePhase) { phase in
                    isViewVisible = phase == .active
                }
                .overlay(
                    // Streak celebration overlay
                    streakCelebrationOverlay
                )
            }
            .navigationTitle("DayStart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundColor(BananaTheme.ColorToken.text)
                    }
                    .tint(BananaTheme.ColorToken.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showEditSchedule = true }) {
                        Text("Edit")
                            .font(.title3.weight(.medium))
                            .foregroundColor(BananaTheme.ColorToken.text)
                    }
                    .tint(BananaTheme.ColorToken.primary)
                }
            }
            .sheet(isPresented: $showEditSchedule) {
                EditScheduleView()
                    .environmentObject(userPreferences)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
                    .environmentObject(userPreferences)
            }
        }
    }
    
    private func handleStateTransition(from oldState: HomeViewModel.AppState, to newState: HomeViewModel.AppState) {
        // Provide haptic feedback based on state transitions
        switch (oldState, newState) {
        case (_, .welcomeCountdown):
            hapticManager.notification(type: .success)
        case (_, .welcomeReady), (_, .ready):
            hapticManager.impact(style: .medium)
        case (_, .countdown):
            hapticManager.impact(style: .light)
        case (_, .playing):
            hapticManager.impact(style: .heavy)
        case (_, .completed):
            hapticManager.notification(type: .success)
        default:
            break
        }
    }
    
    private func triggerStreakCelebration(for streak: Int) {
        showStreakCelebration = true
        
        // Haptic feedback based on milestone
        switch streak {
        case 100...:
            hapticManager.notification(type: .success)
            // Triple haptic burst for major milestones
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hapticManager.notification(type: .success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                hapticManager.notification(type: .success)
            }
        case 30...:
            hapticManager.notification(type: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hapticManager.impact(style: .heavy)
            }
        case 7...:
            hapticManager.notification(type: .success)
        default:
            hapticManager.impact(style: .medium)
        }
        
        // Auto-hide celebration after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showStreakCelebration = false
        }
    }
    
    private var gradientColors: [Color] {
        // Not used anymore, keeping for compatibility
        return [BananaTheme.ColorToken.background]
    }
    
    // MARK: - Light Mode Adaptive Helpers
    
    private var streakBackgroundColor: Color {
        if colorScheme == .light {
            // Much stronger background for light mode
            return BananaTheme.ColorToken.primary.opacity(0.8)
        } else {
            return BananaTheme.ColorToken.primary.opacity(StreakManager.shared.currentStreak >= 7 ? 0.3 : 0.25)
        }
    }
    
    private var streakTextColor: Color {
        if colorScheme == .light {
            // Use white text on the stronger background
            return BananaTheme.ColorToken.background
        } else {
            return BananaTheme.ColorToken.primary
        }
    }
    
    private func streakBorderOpacity(for streak: Int) -> Double {
        if colorScheme == .light {
            return 0.0 // No border needed with solid background
        } else {
            return streak >= 7 ? 0.8 : 0.6
        }
    }
    
    private func streakBorderWidth(for streak: Int) -> CGFloat {
        if colorScheme == .light {
            return 0 // No border in light mode
        } else {
            return CGFloat(streak >= 14 ? 3 : 2)
        }
    }
    
    private func streakShadowRadius(for streak: Int) -> CGFloat {
        return colorScheme == .light ? 8 : CGFloat(streak >= 30 ? 8 : 0)
    }
    
    private var streakShadowColor: Color {
        if colorScheme == .light {
            return BananaTheme.ColorToken.primary.opacity(0.4)
        } else {
            return BananaTheme.ColorToken.primary.opacity(StreakManager.shared.currentStreak >= 30 ? 0.4 : 0)
        }
    }
    
    private var weeklyProgressCardBackground: Color {
        if colorScheme == .light {
            // Solid, highly visible background for light mode
            return BananaTheme.ColorToken.primary.opacity(0.15)
        } else {
            return BananaTheme.ColorToken.card
        }
    }
    
    private var weeklyProgressBorderColor: Color {
        if colorScheme == .light {
            return BananaTheme.ColorToken.primary.opacity(0.8)
        } else {
            return BananaTheme.ColorToken.primary.opacity(0.2)
        }
    }
    
    private var weeklyProgressBorderWidth: CGFloat {
        return colorScheme == .light ? 2.5 : 1
    }
    
    // PHASE 2: Removed headerView - replaced with HomeHeaderView micro-component
    
    private var timeBasedGreeting: String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        
        switch hour {
        case 4..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<20:
            return "Good evening"
        default:
            return "Rest well"
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        switch viewModel.state {
        case .idle:
            if let error = viewModel.connectionError {
                connectionErrorView(error: error)
            } else {
                idleViewContent
            }
        case .welcomeCountdown:
            welcomeCountdownView
        case .welcomeReady:
            welcomeReadyViewContent
        case .countdown:
            countdownView
        case .preparing:
            preparingView
        case .ready:
            readyViewContent
        case .playing:
            playingView  // Playing state includes loading
        case .completed:
            completedViewContent
        }
    }
    
    // PHASE 2: Removed primaryActionView - replaced with PrimaryActionView micro-component
    
    private var welcomeCountdownView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Text("🎉")
                    .font(.system(size: 80))
                    .scaleEffect(1.2)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: viewModel.state
                    )
                
                Text("Welcome to DayStart!")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .multilineTextAlignment(.center)
                
                Text("Your first DayStart is preparing...")
                    .font(.subheadline)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                // Countdown
                VStack(spacing: 8) {
                    Text("Ready in")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    
                    Text(welcomeScheduler.welcomeCountdownText)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(BananaTheme.ColorToken.primary)
                }
                
                // Progress indicator
                if !welcomeScheduler.initializationProgress.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(welcomeScheduler.initializationStep), 
                                   total: Double(welcomeScheduler.totalInitializationSteps))
                            .progressViewStyle(LinearProgressViewStyle(tint: BananaTheme.ColorToken.primary))
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                            .frame(maxWidth: 200)
                        
                        Text(welcomeScheduler.initializationProgress)
                            .font(.caption)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.3), value: welcomeScheduler.initializationProgress)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    
    private var welcomeReadyViewContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 60))
                .foregroundColor(BananaTheme.ColorToken.primary)
            
            Text("Your Welcome DayStart is Ready!")
                .adaptiveFont(BananaTheme.Typography.title2)
                .foregroundColor(BananaTheme.ColorToken.text)
                .multilineTextAlignment(.center)
            
            Text("Experience what your mornings will be like")
                .font(.subheadline)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
        }
    }
    
    private var welcomeReadyViewAction: some View {
        Button(action: { 
            hapticManager.impact(style: .medium)
            viewModel.startWelcomeDayStart() 
        }) {
            Text("DayStart")
                .adaptiveFont(BananaTheme.Typography.title)
                .fontWeight(.bold)
                .foregroundColor(BananaTheme.ColorToken.background)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
        }
        .buttonStyle(InstantResponseStyle())
        .background(
            RoundedRectangle(cornerRadius: 25)
                .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
        )
        .padding(.horizontal, 40)
        .scaleEffect(1.0)
        .animation(
            Animation.easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
            value: viewModel.state
        )
        .accessibilityLabel("Start welcome DayStart")
        .accessibilityHint("Tap to begin your introductory audio experience")
    }

    // Split idle view into content and action parts
    private var idleViewContent: some View {
        VStack(spacing: 20) {
            if viewModel.showNoScheduleMessage {
                Text("No DayStarts scheduled")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
            } else if let nextTime = viewModel.nextDayStartTime {
                // Check if today's DayStart is available and not completed
                if viewModel.isNextDayStartToday && !viewModel.hasCompletedCurrentOccurrence {
                    VStack(spacing: 12) {
                        Text("Today's DayStart")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        
                        Text(nextTime, style: .time)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            
                        Text("Available Now")
                            .font(.subheadline)
                            .foregroundColor(BananaTheme.ColorToken.primary)
                            .fontWeight(.medium)
                    }
                } else {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            Text("Next DayStart")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.secondaryText : BananaTheme.ColorToken.tertiaryText)
                            
                            Text(nextTime, style: .time)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.text : BananaTheme.ColorToken.tertiaryText)
                            
                            Text(formattedDate(for: nextTime))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                                .opacity(viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday ? 1.0 : 0.7)
                        }
                        
                        // Tomorrow's lineup preview
                        if viewModel.isNextDayStartTomorrow {
                            Button(action: {
                                hapticManager.impact(style: .light)
                                showEditSchedule = true
                            }) {
                                tomorrowsLineupPreview
                            }
                            .buttonStyle(PlainButtonStyle())
                            .task {
                                await loadTomorrowForecast()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var idleViewAction: some View {
        VStack {
            if viewModel.showNoScheduleMessage {
                Button(action: { 
                    hapticManager.impact(style: .light)
                    showEditSchedule = true 
                }) {
                    Label("Schedule DayStart", systemImage: "calendar.badge.plus")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                }
                .buttonStyle(InstantResponseStyle())
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(BananaTheme.ColorToken.text)
                )
                .padding(.horizontal, 40)
            } else if let _ = viewModel.nextDayStartTime, viewModel.isNextDayStartToday && !viewModel.hasCompletedCurrentOccurrence {
                Button(action: { 
                    hapticManager.impact(style: .medium)
                    viewModel.startDayStart() 
                }) {
                    Text("DayStart")
                        .adaptiveFont(BananaTheme.Typography.title)
                        .fontWeight(.bold)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                }
                .buttonStyle(InstantResponseStyle())
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                )
                .padding(.horizontal, 40)
                .accessibilityLabel("Start today's DayStart")
                .accessibilityHint("Tap to begin your daily audio briefing")
            }
        }
    }
    
    private var countdownView: some View {
        VStack(spacing: 20) {
            Text("Starting in")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
            
            Text(viewModel.countdownText)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(BananaTheme.ColorToken.primary)
            
            if let nextTime = viewModel.nextDayStartTime {
                VStack(spacing: 4) {
                    Text(nextTime, style: .time)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                    
                    Text(formattedDate(for: nextTime))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                }
            }
            
            // Progressive anticipation reveal
            countdownAnticipationView
        }
    }
    
    private var readyViewContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 60))
                .foregroundColor(BananaTheme.ColorToken.primary)
            
            Text("Ready to start your day?")
                .adaptiveFont(BananaTheme.Typography.title2)
                .foregroundColor(BananaTheme.ColorToken.text)
        }
    }
    
    private var readyViewAction: some View {
        Button(action: { 
            hapticManager.impact(style: .medium)
            viewModel.startDayStart() 
        }) {
            Text(viewModel.hasCompletedCurrentOccurrence ? "Replay" : "DayStart")
                .adaptiveFont(BananaTheme.Typography.title)
                .fontWeight(.bold)
                .foregroundColor(BananaTheme.ColorToken.background)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
        }
        .buttonStyle(InstantResponseStyle())
        .background(
            RoundedRectangle(cornerRadius: 25)
                .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
        )
        .padding(.horizontal, 40)
        .scaleEffect(1.0)
        .animation(
            Animation.easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
            value: viewModel.state
        )
        .accessibilityLabel(viewModel.hasCompletedCurrentOccurrence ? "Replay DayStart" : "Start DayStart")
        .accessibilityHint("Tap to begin your daily audio briefing")
    }
    
    private var preparingView: some View {
        VStack(spacing: 30) {
            // Progress ring with countdown
            ZStack {
                // Background ring
                Circle()
                    .stroke(BananaTheme.ColorToken.tertiaryText.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: preparingProgress)
                    .stroke(
                        LinearGradient(
                            colors: [BananaTheme.ColorToken.primary, BananaTheme.ColorToken.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: preparingProgress)
                
                // Countdown text
                VStack(spacing: 4) {
                    Text(viewModel.preparingCountdownText)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(BananaTheme.ColorToken.text)
                    
                    Text("Ready in")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
            }
            
            // Rotating message
            Text(viewModel.preparingMessage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .frame(height: 50)
                .animation(.easeInOut(duration: 0.3), value: viewModel.preparingMessage)
            
            // Subtle loading indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(BananaTheme.ColorToken.primary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(loadingDotScale(for: index))
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: isViewVisible
                        )
                }
            }
        }
    }
    
    private var preparingProgress: Double {
        let countdownText = viewModel.preparingCountdownText.components(separatedBy: ":").compactMap({ Int($0) })
        guard countdownText.count == 2 else { return 0 }
        
        let totalSeconds = 120.0 // 2 minutes
        let remainingSeconds = Double(countdownText[0] * 60 + countdownText[1])
        return max(0, min(1, (totalSeconds - remainingSeconds) / totalSeconds))
    }
    
    private func loadingDotScale(for index: Int) -> CGFloat {
        return isViewVisible ? 1.3 : 0.8
    }
    
    private func connectionErrorView(error: ConnectionError) -> some View {
        VStack(spacing: 20) {
            Text(error.icon)
                .font(.system(size: 60))
            
            VStack(spacing: 12) {
                Text(error.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Text(error.message)
                    .font(.system(size: 16))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    private var playingView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                // Show music note when loading, waveform when playing
                /*
                if AudioPlayerManager.shared.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(BananaTheme.ColorToken.text)
                } else {
                    Text("🎵")
                        .font(.system(size: 80))
                        .scaleEffect(1.2)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: viewModel.state
                        )
                }
                
                // Show different text based on playing state
                Text(AudioPlayerManager.shared.isPlaying ? "Playing your DayStart" : "Getting ready...")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .multilineTextAlignment(.center)
                */
                
                // Show loading messages when not playing
                if !AudioPlayerManager.shared.isPlaying {
                    Text(LoadingMessagesService.shared.currentMessage)
                        .font(.subheadline)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private var completedViewContent: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button(action: {
                    hapticManager.impact(style: .light)
                    viewModel.exitCompletedState()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                }
                .accessibilityLabel("Close completed view")
                .accessibilityHint("Return to main view")
            }
            .padding(.top, -10)
            
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("DayStart Complete!")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
            }
            
            if let nextTime = viewModel.nextDayStartTime {
                VStack(spacing: 8) {
                    Text("Next DayStart")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                    
                    VStack(spacing: 2) {
                        Text(nextTime, style: .time)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.text : BananaTheme.ColorToken.tertiaryText)
                        
                        Text(formattedDate(for: nextTime))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                    }
                }
            }
        }
    }
    
    private var recentlyPlayedViewAction: some View {
        VStack(spacing: 16) {
            if let dayStart = viewModel.currentDayStart {
                // Primary Replay button
                Button(action: { 
                    hapticManager.impact(style: .light)
                    viewModel.replayDayStart(dayStart) 
                }) {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                }
                .buttonStyle(InstantResponseStyle())
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(BananaTheme.ColorToken.primary)
                )
                .padding(.horizontal, 40)
                .accessibilityLabel("Replay DayStart")
                .accessibilityHint("Tap to replay the audio briefing you just completed")
                
                // Secondary Share button
                Button(action: { 
                    hapticManager.impact(style: .light)
                    shareDayStart(dayStart) 
                }) {
                    Label("Share Achievement", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundColor(BananaTheme.ColorToken.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(BananaTheme.ColorToken.primary.opacity(0.15))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .accessibilityLabel("Share DayStart achievement")
                .accessibilityHint("Tap to share your morning briefing completion")
            }
        }
    }
    
    private var streakCelebrationOverlay: some View {
        ZStack {
            if showStreakCelebration {
                // Semi-transparent background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showStreakCelebration = false
                    }
                
                // Celebration content
                VStack(spacing: 20) {
                    // Animated celebration emoji
                    Text(celebrationEmojiFor(streak: celebrationStreak))
                        .font(.system(size: 80))
                        .scaleEffect(showStreakCelebration ? 1.2 : 0.5)
                        .rotationEffect(.degrees(showStreakCelebration ? 360 : 0))
                        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showStreakCelebration)
                    
                    VStack(spacing: 8) {
                        Text(celebrationTitleFor(streak: celebrationStreak))
                            .font(.title.bold())
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .multilineTextAlignment(.center)
                        
                        Text("\(celebrationStreak) Day Streak!")
                            .font(.title2.bold())
                            .foregroundColor(BananaTheme.ColorToken.primary)
                        
                        Text(celebrationMessageFor(streak: celebrationStreak))
                            .font(.subheadline)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button(action: {
                        showStreakCelebration = false
                    }) {
                        Text("Awesome! 🎉")
                            .font(.headline)
                            .foregroundColor(BananaTheme.ColorToken.background)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(BananaTheme.ColorToken.primary)
                            .cornerRadius(25)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(BananaTheme.ColorToken.card)
                        .shadow(radius: 20)
                )
                .padding(.horizontal, 40)
                .scaleEffect(showStreakCelebration ? 1.0 : 0.8)
                .opacity(showStreakCelebration ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showStreakCelebration)
            }
        }
    }
    
    private func celebrationEmojiFor(streak: Int) -> String {
        switch streak {
        case 100...: return "🏆"
        case 75...: return "👑"
        case 50...: return "🌟"
        case 30...: return "💪"
        case 21...: return "🔥"
        case 14...: return "⭐️"
        case 7...: return "🎉"
        default: return "🎊"
        }
    }
    
    private func celebrationTitleFor(streak: Int) -> String {
        switch streak {
        case 100...: return "LEGENDARY!"
        case 75...: return "PHENOMENAL!"
        case 50...: return "INCREDIBLE!"
        case 30...: return "AMAZING!"
        case 21...: return "FANTASTIC!"
        case 14...: return "OUTSTANDING!"
        case 7...: return "GREAT JOB!"
        default: return "WELL DONE!"
        }
    }
    
    private func celebrationMessageFor(streak: Int) -> String {
        switch streak {
        case 100...: return "You're a true DayStart legend! 100 days of consistent morning excellence."
        case 75...: return "Absolutely phenomenal dedication! You're in the top 1% of users."
        case 50...: return "Incredible milestone! Your morning routine is now a superpower."
        case 30...: return "Amazing consistency! You've built an unshakeable morning habit."
        case 21...: return "Fantastic! It takes 21 days to form a habit, and you've done it!"
        case 14...: return "Outstanding progress! You're building incredible momentum."
        case 7...: return "Great work! You've completed your first week of consistent DayStarts."
        default: return "Keep up the excellent work!"
        }
    }
    
    private var streakCounterView: some View {
        Button(action: {
            hapticManager.impact(style: .light)
            showHistory = true
        }) {
            HStack(spacing: 8) {
                Text("🔥")
                    .font(.title2)
                    .scaleEffect(StreakManager.shared.currentStreak >= 7 ? 1.3 : 1.0)
                    .rotationEffect(.degrees(StreakManager.shared.currentStreak >= 14 ? 10 : 0))
                    .animation(isViewVisible && StreakManager.shared.currentStreak >= 7 ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .none, value: StreakManager.shared.currentStreak >= 7)
                
                Text("\(StreakManager.shared.currentStreak) day streak")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(streakTextColor)
                    .scaleEffect(showStreakCelebration && celebrationStreak == StreakManager.shared.currentStreak ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showStreakCelebration)
                
                // Enhanced streak milestone celebrations
                Group {
                    if StreakManager.shared.currentStreak >= 100 {
                        Text("🏆✨🎊")
                            .font(.caption)
                            .scaleEffect(1.2)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: StreakManager.shared.currentStreak)
                    } else if StreakManager.shared.currentStreak >= 50 {
                        Text("👑🎆✨")
                            .font(.caption)
                            .scaleEffect(1.1)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: StreakManager.shared.currentStreak)
                    } else if StreakManager.shared.currentStreak >= 30 {
                        Text("💪🎆")
                            .font(.caption)
                            .scaleEffect(1.05)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: StreakManager.shared.currentStreak)
                    } else if StreakManager.shared.currentStreak >= 14 {
                        Text("⭐️🎆")
                            .font(.caption)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: StreakManager.shared.currentStreak)
                    } else if StreakManager.shared.currentStreak >= 7 {
                        Text("🎆")
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(streakBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(BananaTheme.ColorToken.primary.opacity(streakBorderOpacity(for: StreakManager.shared.currentStreak)), lineWidth: streakBorderWidth(for: StreakManager.shared.currentStreak))
                    )
            )
            .shadow(
                color: streakShadowColor, 
                radius: streakShadowRadius(for: StreakManager.shared.currentStreak)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Current streak: \(StreakManager.shared.currentStreak) days")
        .accessibilityHint("Tap to view your streak history")
        .onChange(of: StreakManager.shared.currentStreak) { newStreak in
            // Trigger celebration for milestone streaks
            let isMilestone = [7, 14, 21, 30, 50, 75, 100].contains(newStreak)
            if isMilestone && newStreak > celebrationStreak {
                triggerStreakCelebration(for: newStreak)
            }
            celebrationStreak = max(celebrationStreak, newStreak)
        }
    }
    
    private var weeklyProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("This Week")
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                Spacer()
                Text("\(weeklyCompletionCount)/7")
                    .font(.caption.bold())
                    .foregroundColor(BananaTheme.ColorToken.primary)
            }
            
            // 7-day progress bar
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    let dayStatus = weeklyStatuses[dayIndex]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor(for: dayStatus))
                        .frame(height: 8)
                        .animation(.easeInOut(duration: 0.3).delay(Double(dayIndex) * 0.05), value: dayStatus)
                }
            }
            
            // Progress percentage
            HStack {
                Text(weeklyProgressText)
                    .font(.caption2)
                    .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                Spacer()
                if weeklyCompletionCount == 7 {
                    Text("Perfect Week! 🏆")
                        .font(.caption2.bold())
                        .foregroundColor(BananaTheme.ColorToken.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(weeklyProgressCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(weeklyProgressBorderColor, lineWidth: weeklyProgressBorderWidth)
                )
        )
        .shadow(
            color: colorScheme == .light ? 
                BananaTheme.ColorToken.primary.opacity(0.25) : 
                Color.clear, 
            radius: colorScheme == .light ? 8 : 0
        )
    }
    
    private var weeklyStatuses: [StreakManager.DayStatus] {
        StreakManager.shared.lastNDaysStatuses(7).reversed().map { $0.status }
    }
    
    private var weeklyCompletionCount: Int {
        weeklyStatuses.filter { $0 == .completedSameDay }.count
    }
    
    private var weeklyProgressText: String {
        let percentage = Int((Double(weeklyCompletionCount) / 7.0) * 100)
        switch percentage {
        case 100: return "Perfect consistency!"
        case 71...99: return "Excellent progress (\(percentage)%)"
        case 43...70: return "Good momentum (\(percentage)%)"
        case 15...42: return "Building habits (\(percentage)%)"
        default: return "Getting started (\(percentage)%)"
        }
    }
    
    private func progressColor(for status: StreakManager.DayStatus) -> Color {
        switch status {
        case .completedSameDay:
            return BananaTheme.ColorToken.primary
        case .completedLate:
            return BananaTheme.ColorToken.primary.opacity(0.6)
        case .inProgress:
            return BananaTheme.ColorToken.primary.opacity(0.8)
        case .notStarted:
            return BananaTheme.ColorToken.primary.opacity(0.2)
        }
    }
    
    // MARK: - Share Functionality
    
    private func shareDayStart(_ dayStart: DayStartData) {
        let duration = Int(dayStart.duration / 60) // Convert to minutes
        let shareText = "📈 Just got my personalized morning brief - market insights, weather, and productivity tips in \(duration) minutes! #DayStart"
        
        let items: [Any] = [shareText]
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            // Find the topmost presented view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            topController.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Anticipation Design Components
    
    private var tomorrowsLineupPreview: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Tomorrow's Lineup")
                    .font(.caption.bold())
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                Spacer()
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.primary.opacity(0.7))
            }
            
            LazyVStack(spacing: 8) {
                ForEach(previewTopics, id: \.self) { topic in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(BananaTheme.ColorToken.primary.opacity(0.6))
                            .frame(width: 6, height: 6)
                        
                        Text(topic)
                            .font(.caption)
                            .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .light ? 
                    BananaTheme.ColorToken.primary.opacity(0.08) : 
                    BananaTheme.ColorToken.card.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(BananaTheme.ColorToken.primary.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var countdownAnticipationView: some View {
        VStack(spacing: 8) {
            // Personality-driven teaser message
            Text(anticipationMessage)
                .font(.caption)
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Progressive content reveal based on countdown
            if shouldShowContentPreview {
                HStack(spacing: 16) {
                    ForEach(revealedContentTypes, id: \.self) { contentType in
                        VStack(spacing: 4) {
                            Image(systemName: contentType.icon)
                                .font(.title3)
                                .foregroundColor(BananaTheme.ColorToken.primary)
                            
                            Text(contentType.name)
                                .font(.caption2)
                                .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                        }
                        .scaleEffect(1.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(contentType.rawValue) * 0.1), value: shouldShowContentPreview)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Forecast Loading
    
    private func loadTomorrowForecast() async {
        guard userPreferences.settings.includeWeather,
              LocationManager.shared.hasLocationAccess(),
              tomorrowWeatherForecast == nil else { return }
        
        isLoadingForecast = true
        
        if #available(iOS 16.0, *) {
            tomorrowWeatherForecast = await LocationManager.shared.getTomorrowForecast()
        }
        
        isLoadingForecast = false
    }
    
    // MARK: - Anticipation Data & Logic
    
    private var previewTopics: [String] {
        var topics: [String] = []
        
        // Weather forecast if enabled and available
        if userPreferences.settings.includeWeather {
            if let forecast = tomorrowWeatherForecast {
                topics.append("Weather: \(forecast)")
            } else if LocationManager.shared.hasLocationAccess() {
                topics.append("Weather forecast for your location")
            }
        }
        
        // Stocks if enabled
        if userPreferences.settings.includeStocks && !userPreferences.settings.stockSymbols.isEmpty {
            let symbols = userPreferences.settings.stockSymbols.prefix(3).joined(separator: ", ")
            let remaining = userPreferences.settings.stockSymbols.count - 3
            if remaining > 0 {
                topics.append("Stocks: \(symbols) and \(remaining) more")
            } else {
                topics.append("Stocks: \(symbols)")
            }
        }
        
        // News if enabled
        if userPreferences.settings.includeNews {
            topics.append("Personalized news brief")
        }
        
        // Sports if enabled
        if userPreferences.settings.includeSports {
            topics.append("Sports highlights and scores")
        }
        
        // Calendar if enabled
        if userPreferences.settings.includeCalendar {
            topics.append("Your schedule and reminders")
        }
        
        // Quotes if enabled
        if userPreferences.settings.includeQuotes {
            topics.append("\(userPreferences.settings.quotePreference.name) inspiration")
        }
        
        // If nothing is enabled, show a generic message
        if topics.isEmpty {
            topics.append("Customize your DayStart in settings")
        }
        
        return topics
    }
    
    private var anticipationMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeUntilStart = timeUntilNextDayStart
        
        switch timeUntilStart {
        case 0..<300: // < 5 minutes
            return "Your personalized morning brief is ready to go! ☀️"
        case 300..<900: // 5-15 minutes
            return "Almost time! Your daily insights are being fine-tuned..."
        case 900..<1800: // 15-30 minutes
            return "Your morning intelligence is brewing ☕️"
        default:
            switch hour {
            case 6..<12:
                return "Tomorrow's briefing will be crafted with fresh insights 🌅"
            case 12..<18:
                return "Your next DayStart is being personalized for you ⚡️"
            case 18..<22:
                return "While you rest, we're preparing tomorrow's perfect start 🌙"
            default:
                return "Sweet dreams! Your morning briefing awaits 💫"
            }
        }
    }
    
    private var timeUntilNextDayStart: TimeInterval {
        guard let nextTime = viewModel.nextDayStartTime else { return 86400 }
        return nextTime.timeIntervalSince(Date())
    }
    
    private var shouldShowContentPreview: Bool {
        timeUntilNextDayStart <= 1800 // Show preview in last 30 minutes
    }
    
    private enum ContentType: Int, CaseIterable {
        case news = 0
        case weather = 1
        case calendar = 2
        case insights = 3
        
        var name: String {
            switch self {
            case .news: return "News"
            case .weather: return "Weather"
            case .calendar: return "Schedule"
            case .insights: return "Insights"
            }
        }
        
        var icon: String {
            switch self {
            case .news: return "newspaper"
            case .weather: return "cloud.sun"
            case .calendar: return "calendar"
            case .insights: return "lightbulb"
            }
        }
    }
    
    private var revealedContentTypes: [ContentType] {
        let timeUntil = timeUntilNextDayStart
        
        switch timeUntil {
        case 0..<300: // < 5 minutes - show all
            return Array(ContentType.allCases)
        case 300..<900: // 5-15 minutes - show 3
            return Array(ContentType.allCases.prefix(3))
        case 900..<1800: // 15-30 minutes - show 2
            return Array(ContentType.allCases.prefix(2))
        default:
            return []
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}