import SwiftUI

struct AudioPlayerView: View {
    @StateObject private var audioPlayer = AudioPlayerManager.shared
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 20) {
            progressView
            controlsView
            playbackSpeedView
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(20)
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
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text(timeString(audioPlayer.duration))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 40) {
            Button(action: { audioPlayer.skip(by: -10) }) {
                VStack(spacing: 4) {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                    Text("10s")
                        .font(.caption2)
                }
            }
            .foregroundColor(.white)
            
            Button(action: { audioPlayer.togglePlayPause() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .foregroundColor(BananaTheme.ColorToken.accent)
            
            Button(action: { audioPlayer.skip(by: 10) }) {
                VStack(spacing: 4) {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                    Text("10s")
                        .font(.caption2)
                }
            }
            .foregroundColor(.white)
        }
    }
    
    private var playbackSpeedView: some View {
        HStack(spacing: 20) {
            Text("Speed")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            
            ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { speed in
                Button(action: { audioPlayer.setPlaybackRate(Float(speed)) }) {
                    Text("\(speed, specifier: "%.2g")x")
                        .font(.caption)
                        .fontWeight(audioPlayer.playbackRate == Float(speed) ? .bold : .regular)
                        .foregroundColor(audioPlayer.playbackRate == Float(speed) ? BananaTheme.ColorToken.accent : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            audioPlayer.playbackRate == Float(speed) ?
                            BananaTheme.ColorToken.accent.opacity(0.2) : Color.white.opacity(0.1)
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
}