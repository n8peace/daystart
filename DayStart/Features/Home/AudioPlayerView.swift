import SwiftUI

struct AudioPlayerView: View {
    let dayStart: DayStartData?
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @State private var isDragging = false
    @AppStorage("playbackSpeed") private var savedPlaybackSpeed: Double = 1.0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    BananaTheme.ColorToken.background.opacity(0),
                    BananaTheme.ColorToken.background.opacity(0.95),
                    BananaTheme.ColorToken.background
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                if let dayStart = dayStart {
                    Text(formatDate(dayStart.date))
                        .font(.subheadline)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                
                progressView
                controlsView
                playbackSpeedView
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .onAppear {
            audioPlayer.setPlaybackRate(Float(savedPlaybackSpeed))
        }
    }
    
    private var progressView: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { newValue in
                        audioPlayer.seek(to: newValue)
                    }
                ),
                in: 0...max(audioPlayer.duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                }
            )
            .accentColor(BananaTheme.ColorToken.accent)
            
            HStack {
                Text(timeString(audioPlayer.currentTime))
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
                
                Spacer()
                
                Text(timeString(audioPlayer.duration))
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
            }
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 40) {
            Button(action: { audioPlayer.skip(by: -10) }) {
                Image(systemName: "gobackward.10")
                    .font(.title2)
            }
            .foregroundColor(BananaTheme.ColorToken.text)
            
            Button(action: { audioPlayer.togglePlayPause() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .foregroundColor(BananaTheme.ColorToken.accent)
            
            Button(action: { audioPlayer.skip(by: 10) }) {
                Image(systemName: "goforward.10")
                    .font(.title2)
            }
            .foregroundColor(BananaTheme.ColorToken.text)
        }
    }
    
    private var playbackSpeedView: some View {
        HStack(spacing: 12) {
            ForEach([0.8, 1.0, 1.3, 1.5], id: \.self) { speed in
                Button(action: { 
                    audioPlayer.setPlaybackRate(Float(speed))
                    savedPlaybackSpeed = speed
                }) {
                    Text("\(speed, specifier: "%.1f")x")
                        .font(.caption)
                        .fontWeight(audioPlayer.playbackRate == Float(speed) ? .bold : .regular)
                        .foregroundColor(audioPlayer.playbackRate == Float(speed) ? BananaTheme.ColorToken.accent : BananaTheme.ColorToken.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            audioPlayer.playbackRate == Float(speed) ?
                            BananaTheme.ColorToken.accent.opacity(0.2) : BananaTheme.ColorToken.text.opacity(0.1)
                        )
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy"
        return formatter.string(from: date)
    }
}