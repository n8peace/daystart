import SwiftUI

struct AudioPlayerView: View {
    let dayStart: DayStartData?
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
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
                    HStack {
                        Text(formatDate(dayStart.date))
                            .font(.subheadline)
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                        
                        Spacer()
                        
                        // Share button in audio player
                        Button(action: { 
                            shareDayStart(dayStart) 
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(BananaTheme.ColorToken.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(BananaTheme.ColorToken.primary.opacity(0.15))
                                )
                        }
                        .accessibilityLabel("Share current DayStart")
                        .accessibilityHint("Tap to share this audio briefing")
                    }
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
            // Enhanced progress slider with larger touch target
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
            .frame(height: 44) // Enhanced touch target
            .background(
                // Subtle glow when active
                RoundedRectangle(cornerRadius: 22)
                    .fill(BananaTheme.ColorToken.accent.opacity(isDragging ? 0.1 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
            )
            
            HStack {
                Text(timeString(audioPlayer.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
                
                Spacer()
                
                // Progress percentage when dragging
                if isDragging && audioPlayer.duration > 0 {
                    Text("\(Int((audioPlayer.currentTime / audioPlayer.duration) * 100))%")
                        .font(.caption.bold())
                        .foregroundColor(BananaTheme.ColorToken.accent)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(timeString(audioPlayer.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
            }
            .animation(.easeInOut(duration: 0.2), value: isDragging)
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 30) {
            // Skip backward - enhanced touch target
            Button(action: { audioPlayer.skip(by: -10) }) {
                Image(systemName: "gobackward.10")
                    .font(.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(BananaTheme.ColorToken.text.opacity(0.1))
                    )
            }
            .scaleEffect(1.0)
            .animation(.easeInOut(duration: 0.1), value: audioPlayer.isPlaying)
            
            // Main play/pause - already large enough
            Button(action: { audioPlayer.togglePlayPause() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(BananaTheme.ColorToken.accent)
                    .shadow(color: BananaTheme.ColorToken.accent.opacity(0.3), radius: 8)
            }
            .scaleEffect(audioPlayer.isPlaying ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: audioPlayer.isPlaying)
            
            // Skip forward - enhanced touch target
            Button(action: { audioPlayer.skip(by: 10) }) {
                Image(systemName: "goforward.10")
                    .font(.title2)
                    .foregroundColor(BananaTheme.ColorToken.text)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(BananaTheme.ColorToken.text.opacity(0.1))
                    )
            }
            .scaleEffect(1.0)
            .animation(.easeInOut(duration: 0.1), value: audioPlayer.isPlaying)
        }
    }
    
    private var playbackSpeedView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.caption)
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.8))
                
                Spacer()
                
                Text("\(savedPlaybackSpeed, specifier: "%.1f")x")
                    .font(.caption.bold())
                    .foregroundColor(BananaTheme.ColorToken.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BananaTheme.ColorToken.accent.opacity(0.2))
                    )
            }
            
            HStack(spacing: 12) {
                Text("0.5×")
                    .font(.caption2)
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.6))
                
                Slider(
                    value: Binding(
                        get: { savedPlaybackSpeed },
                        set: { newSpeed in
                            savedPlaybackSpeed = newSpeed
                            audioPlayer.setPlaybackRate(Float(newSpeed))
                        }
                    ),
                    in: 0.5...2.0,
                    step: 0.1
                )
                .accentColor(BananaTheme.ColorToken.accent)
                .frame(height: 44) // Enhanced touch target
                
                Text("2.0×")
                    .font(.caption2)
                    .foregroundColor(BananaTheme.ColorToken.text.opacity(0.6))
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        return FormatterCache.shared.fullDateFormatter.string(from: date)
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
}