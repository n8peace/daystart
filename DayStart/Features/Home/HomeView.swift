import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var showEditSchedule = false
    @State private var showHistory = false
    @EnvironmentObject var userPreferences: UserPreferences
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    headerView
                    
                    Spacer()
                    
                    mainContentView
                    
                    Spacer()
                    
                    if viewModel.state == .playing {
                        AudioPlayerView()
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showEditSchedule = true }) {
                        Image(systemName: "pin")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
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
        switch viewModel.state {
        case .idle:
            return [Color(hex: "1a1a2e"), Color(hex: "16213e")]
        case .countdown:
            return [Color(hex: "0f3460"), Color(hex: "16213e")]
        case .ready:
            return [Color(hex: "e94560"), Color(hex: "0f3460")]
        case .playing, .recentlyPlayed:
            return [Color(hex: "f39c12"), Color(hex: "e94560")]
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("DayStart")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            let name = userPreferences.settings.preferredName
            if !name.isEmpty {
                Text("Good morning, \(name)")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        switch viewModel.state {
        case .idle:
            idleView
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
    
    private var idleView: some View {
        VStack(spacing: 20) {
            if viewModel.showNoScheduleMessage {
                Text("No DayStarts scheduled")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Button(action: { showEditSchedule = true }) {
                    Label("Schedule DayStart", systemImage: "calendar.badge.plus")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                }
            } else if let nextTime = viewModel.nextDayStartTime {
                VStack(spacing: 12) {
                    Text("Next DayStart")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(nextTime, style: .time)
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(nextTime, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
    
    private var countdownView: some View {
        VStack(spacing: 20) {
            Text("Starting in")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            Text(viewModel.countdownText)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            if let nextTime = viewModel.nextDayStartTime {
                Text(nextTime, style: .time)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private var readyView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                
                Text("Ready to start your day?")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Button(action: { viewModel.startDayStart() }) {
                Text("DayStart")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(width: 200, height: 200)
                    .background(
                        Circle()
                            .fill(Color.yellow)
                            .shadow(color: .yellow.opacity(0.5), radius: 20)
                    )
            }
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
                .foregroundColor(.white)
            
            Text("Playing your DayStart")
                .font(.title2)
                .foregroundColor(.white)
        }
    }
    
    private var recentlyPlayedView: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("DayStart Complete!")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            if let dayStart = viewModel.currentDayStart {
                Button(action: { viewModel.replayDayStart(dayStart) }) {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
            }
            
            if let nextTime = viewModel.nextDayStartTime {
                VStack(spacing: 8) {
                    Text("Next DayStart")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(nextTime, style: .time)
                        .font(.title3)
                        .foregroundColor(.white)
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