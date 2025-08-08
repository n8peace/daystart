import AVFoundation
import SwiftUI
import Combine

@MainActor
class HistoryAudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    deinit {
        timer?.invalidate()
        timer = nil
        audioPlayer?.stop()
    }
    
    func loadAudio(from path: String) {
        isLoading = true
        errorMessage = nil
        
        let url = URL(fileURLWithPath: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            isLoading = false
            
            DebugLogger.shared.logAudioEvent("History audio loaded", details: [
                "path": path,
                "duration": duration
            ])
        } catch {
            isLoading = false
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
            DebugLogger.shared.logError(error, context: "Loading history audio from \(path)")
        }
    }
    
    func togglePlayback() {
        guard let player = audioPlayer else {
            errorMessage = "No audio file loaded"
            return
        }
        
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    private func play() {
        guard let player = audioPlayer else { return }
        
        if player.play() {
            isPlaying = true
            startTimer()
            DebugLogger.shared.logAudioEvent("History audio started")
        } else {
            errorMessage = "Failed to start playback"
        }
    }
    
    private func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
        DebugLogger.shared.logAudioEvent("History audio paused")
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
        DebugLogger.shared.logAudioEvent("History audio stopped")
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let seekTime = max(0, min(time, player.duration))
        player.currentTime = seekTime
        currentTime = seekTime
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTime()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTime() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
    }
    
    // MARK: - Computed Properties
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioPlayerDelegate
extension HistoryAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
            if flag {
                self.currentTime = 0
                DebugLogger.shared.logAudioEvent("History audio finished", details: [
                    "successfully": flag
                ])
            }
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
            self.errorMessage = "Audio decode error: \(error?.localizedDescription ?? "Unknown error")"
            DebugLogger.shared.logError(
                error ?? NSError(domain: "AudioDecodeError", code: -1),
                context: "History audio playback"
            )
        }
    }
}

// MARK: - Simplified History Audio Player View
struct SimpleHistoryAudioPlayer: View {
    @StateObject private var audioPlayer = HistoryAudioPlayer()
    let audioPath: String?
    
    var body: some View {
        HStack(spacing: BananaTheme.Spacing.sm) {
            Button(action: {
                audioPlayer.togglePlayback()
            }) {
                Image(systemName: playButtonIcon)
                    .font(.title2)
                    .foregroundColor(BananaTheme.ColorToken.primary)
            }
            .disabled(audioPath == nil || audioPlayer.isLoading)
            
            if audioPlayer.duration > 0 {
                VStack(spacing: 2) {
                    ProgressView(value: audioPlayer.progress)
                        .tint(BananaTheme.ColorToken.primary)
                        .scaleEffect(y: 0.5)
                    
                    HStack {
                        Text(audioPlayer.formattedCurrentTime)
                        Spacer()
                        Text(audioPlayer.formattedDuration)
                    }
                    .font(.caption2)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
            } else if audioPlayer.isLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
            } else if audioPath != nil {
                Text("Tap to play")
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            } else {
                Text("No audio")
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
            }
            
            Spacer()
        }
        .onAppear {
            if let path = audioPath {
                audioPlayer.loadAudio(from: path)
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }
    
    private var playButtonIcon: String {
        if audioPlayer.isLoading {
            return "hourglass"
        } else if audioPlayer.isPlaying {
            return "pause.circle.fill"
        } else {
            return "play.circle.fill"
        }
    }
}

// MARK: - Preview
#if DEBUG
struct HistoryAudioPlayer_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            SimpleHistoryAudioPlayer(audioPath: nil)
                .padding()
            
            SimpleHistoryAudioPlayer(audioPath: "/mock/path/audio.mp3")
                .padding()
        }
        .bananaBackground()
        .previewDisplayName("Audio Player States")
    }
}
#endif