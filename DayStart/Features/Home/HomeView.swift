import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var showEditSchedule = false
    @State private var showHistory = false
    @EnvironmentObject var userPreferences: UserPreferences
    @ObservedObject private var welcomeScheduler = WelcomeDayStartScheduler.shared
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter
    }
    
    private func formattedDate(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let sevenDaysFromToday = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        
        if viewModel.isNextDayStartToday {
            return "Today, \(dateFormatter.string(from: date))"
        } else if viewModel.isNextDayStartTomorrow {
            return "Tomorrow, \(dateFormatter.string(from: date))"
        } else if date < sevenDaysFromToday {
            // Within next 7 days - add day name
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE" // Full day name
            return "\(dayFormatter.string(from: date)), \(dateFormatter.string(from: date))"
        } else {
            return dateFormatter.string(from: date)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                DayStartGradientBackground()
                
                VStack(spacing: 30) {
                    headerView
                    
                    Spacer()
                    
                    mainContentView
                    
                    Spacer()
                    
                    if viewModel.state == .playing {
                        AudioPlayerView(dayStart: viewModel.currentDayStart)
                    }
                }
                .padding()
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
                HistoryView(onReplay: viewModel.replayDayStart)
                    .environmentObject(userPreferences)
            }
        }
    }
    
    private var gradientColors: [Color] {
        // Not used anymore, keeping for compatibility
        return [BananaTheme.ColorToken.background]
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            let name = userPreferences.settings.preferredName
            if !name.isEmpty {
                Text("\(timeBasedGreeting), \(name)")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
        }
    }
    
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
            idleView
        case .welcomeCountdown:
            welcomeCountdownView
        case .welcomeReady:
            welcomeReadyView
        case .countdown:
            countdownView
        case .ready:
            readyView
        case .playing:
            playingView
        case .recentlyPlayed:
            recentlyPlayedView
        }
    }
    
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
            
            VStack(spacing: 8) {
                Text("Ready in")
                    .font(.headline)
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
                
                Text(welcomeScheduler.welcomeCountdownText)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(BananaTheme.ColorToken.primary)
            }
        }
    }
    
    private var welcomeReadyView: some View {
        VStack(spacing: 30) {
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
            
            Button(action: { viewModel.startWelcomeDayStart() }) {
                Text("DayStart")
                    .adaptiveFont(BananaTheme.Typography.title)
                    .fontWeight(.bold)
                    .foregroundColor(BananaTheme.ColorToken.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(BananaTheme.ColorToken.primary)
                            .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                    )
            }
            .padding(.horizontal, 40)
            .scaleEffect(1.0)
            .animation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                value: viewModel.state
            )
        }
    }

    private var idleView: some View {
        VStack(spacing: 20) {
            if viewModel.showNoScheduleMessage {
                Text("No DayStarts scheduled")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
                
                Button(action: { showEditSchedule = true }) {
                    Label("Schedule DayStart", systemImage: "calendar.badge.plus")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.background)
                        .padding()
                        .background(BananaTheme.ColorToken.text)
                        .cornerRadius(12)
                }
            } else if let nextTime = viewModel.nextDayStartTime {
                // Check if today's DayStart is available and not completed
                if viewModel.isNextDayStartToday && !viewModel.hasCompletedCurrentOccurrence {
                    VStack(spacing: 30) {
                        VStack(spacing: 12) {
                            Text("Today's DayStart")
                                .adaptiveFont(BananaTheme.Typography.headline)
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            
                            Text(nextTime, style: .time)
                                .font(.system(size: 42, weight: .semibold, design: .rounded))
                                .foregroundColor(BananaTheme.ColorToken.text)
                                
                            Text("Available Now")
                                .font(.subheadline)
                                .foregroundColor(BananaTheme.ColorToken.primary)
                                .fontWeight(.medium)
                        }
                        
                        Button(action: { viewModel.startDayStart() }) {
                            Text("DayStart")
                                .adaptiveFont(BananaTheme.Typography.title)
                                .fontWeight(.bold)
                                .foregroundColor(BananaTheme.ColorToken.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(BananaTheme.ColorToken.primary)
                                        .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                                )
                        }
                        .padding(.horizontal, 40)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("Next DayStart")
                            .adaptiveFont(BananaTheme.Typography.headline)
                            .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.secondaryText : BananaTheme.ColorToken.tertiaryText)
                        
                        Text(nextTime, style: .time)
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.text : BananaTheme.ColorToken.tertiaryText)
                        
                        Text(formattedDate(for: nextTime))
                            .font(.subheadline)
                            .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                            .opacity(viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday ? 1.0 : 0.7)
                    }
                }
            }
        }
    }
    
    private var countdownView: some View {
        VStack(spacing: 20) {
            Text("Starting in")
                .adaptiveFont(BananaTheme.Typography.headline)
                .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
            
            Text(viewModel.countdownText)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundColor(BananaTheme.ColorToken.text)
            
            if let nextTime = viewModel.nextDayStartTime {
                VStack(spacing: 4) {
                    Text(nextTime, style: .time)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                    
                    Text(formattedDate(for: nextTime))
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                }
            }
        }
    }
    
    private var readyView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 60))
                    .foregroundColor(BananaTheme.ColorToken.primary)
                
                Text("Ready to start your day?")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
            }
            
            Button(action: { viewModel.startDayStart() }) {
                Text(viewModel.hasCompletedCurrentOccurrence ? "Replay" : "DayStart")
                    .adaptiveFont(BananaTheme.Typography.title)
                    .fontWeight(.bold)
                    .foregroundColor(BananaTheme.ColorToken.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(BananaTheme.ColorToken.primary)
                            .shadow(color: BananaTheme.ColorToken.primary.opacity(0.5), radius: 20)
                    )
            }
            .padding(.horizontal, 40)
            .scaleEffect(1.0)
            .animation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                value: viewModel.state
            )
        }
    }
    
    private var playingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(BananaTheme.ColorToken.text)
            
            Text("Playing your DayStart")
                .adaptiveFont(BananaTheme.Typography.title2)
                .foregroundColor(BananaTheme.ColorToken.text)
        }
    }
    
    private var recentlyPlayedView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("DayStart Complete!")
                    .adaptiveFont(BananaTheme.Typography.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
            }
            
            if let dayStart = viewModel.currentDayStart {
                Button(action: { viewModel.replayDayStart(dayStart) }) {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .adaptiveFont(BananaTheme.Typography.headline)
                        .foregroundColor(BananaTheme.ColorToken.text)
                        .padding()
                        .background(BananaTheme.ColorToken.card)
                        .cornerRadius(12)
                }
            }
            
            if let nextTime = viewModel.nextDayStartTime {
                VStack(spacing: 8) {
                    Text("Next DayStart")
                        .font(.subheadline)
                        .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.secondaryText : BananaTheme.ColorToken.tertiaryText)
                    
                    VStack(spacing: 2) {
                        Text(nextTime, style: .time)
                            .font(.title3.weight(.semibold))
                            .foregroundColor((viewModel.isNextDayStartTomorrow || viewModel.isNextDayStartToday) ? BananaTheme.ColorToken.text : BananaTheme.ColorToken.tertiaryText)
                        
                        Text(formattedDate(for: nextTime))
                            .font(.caption2)
                            .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                    }
                }
            }
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