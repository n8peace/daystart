import SwiftUI

struct AudioPlayerView: View {
    let dayStart: DayStartData?
    @ObservedObject private var audioPlayer = AudioPlayerManager.shared
    @State private var isDragging = false
    @State private var isShareLoading = false
    @State private var showShareError = false
    // @AppStorage("playbackSpeed") private var savedPlaybackSpeed: Double = 1.0
    
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
                        if dayStart.jobId != nil {
                            Button(action: { 
                                shareDayStart(dayStart) 
                            }) {
                                if isShareLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title3)
                                        .foregroundColor(BananaTheme.ColorToken.primary)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle()
                                                .fill(BananaTheme.ColorToken.primary.opacity(0.15))
                                        )
                                }
                            }
                            .disabled(isShareLoading)
                            .accessibilityLabel("Share current DayStart")
                            .accessibilityHint("Tap to share this audio briefing")
                        }
                        
                        // X button to stop playback
                        Button(action: {
                            AudioPlayerManager.shared.pause()
                            AudioPlayerManager.shared.reset()
                            // Set state to idle via notification
                            NotificationCenter.default.post(name: NSNotification.Name("HomeViewModelStateChange"), object: nil, userInfo: ["state": "idle"])
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(BananaTheme.ColorToken.tertiaryText)
                        }
                        .accessibilityLabel("Stop playback")
                        .accessibilityHint("Stop the current DayStart audio")
                    }
                }
                
                progressView
                controlsView
                // playbackSpeedView
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .alert("Share Error", isPresented: $showShareError) {
            Button("OK") { }
        } message: {
            Text("Unable to share this DayStart. Please try again later.")
        }
        .onAppear {
            print("🔍 AudioPlayerView.onAppear - Called!")
            print("🔍 AudioPlayerView - DayStart parameter: \(dayStart == nil ? "nil" : "exists")")
            
            // Debug logging for share button visibility
            if let dayStart = dayStart {
                print("🔍 AudioPlayerView - DayStart exists: id=\(dayStart.id)")
                print("🔍 AudioPlayerView - JobId: \(dayStart.jobId ?? "nil")")
                print("🔍 AudioPlayerView - Share button will show: \(dayStart.jobId != nil)")
            } else {
                print("🔍 AudioPlayerView - DayStart is nil - no share button will show")
            }
            
            // Listen for share trigger from prompt
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("TriggerShareFromPrompt"),
                object: nil,
                queue: .main
            ) { [dayStart] notification in
                if let shareDayStart = notification.object as? DayStartData,
                   let currentDayStart = dayStart,
                   shareDayStart.id == currentDayStart.id {
                    self.shareDayStart(currentDayStart)
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self)
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
    
    /*
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
    */
    
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
        guard let jobId = dayStart.jobId else {
            DebugLogger.shared.log("❌ Cannot share DayStart: missing jobId", level: .error)
            return
        }
        
        // Check if audioStoragePath is available, if not try to fetch it
        if let audioStoragePath = dayStart.audioStoragePath, !audioStoragePath.isEmpty {
            // AudioStoragePath is available, proceed with share
            createShareWithPath(dayStart, audioStoragePath: audioStoragePath)
        } else {
            // AudioStoragePath is missing, attempt to fetch from API
            DebugLogger.shared.log("⚠️ AudioStoragePath missing for jobId: \(jobId), attempting to fetch from API", level: .warning)
            fetchMissingAudioStoragePath(for: dayStart)
        }
    }
    
    private func fetchMissingAudioStoragePath(for dayStart: DayStartData) {
        Task {
            do {
                // Show loading indicator
                await MainActor.run {
                    isShareLoading = true
                }
                
                DebugLogger.shared.log("🔍 Fetching audio status for missing audioStoragePath", level: .info)
                
                // Fetch audio status to get audioStoragePath
                let audioStatus = try await SupabaseClient.shared.getAudioStatus(for: dayStart.date)
                
                guard audioStatus.success && audioStatus.status == "ready" else {
                    throw NSError(domain: "ShareError", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Audio not ready for sharing"
                    ])
                }
                
                guard let audioStoragePath = audioStatus.audioFilePath, !audioStoragePath.isEmpty else {
                    throw NSError(domain: "ShareError", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not retrieve audio storage path"
                    ])
                }
                
                DebugLogger.shared.log("✅ Fetched audioStoragePath: \(audioStoragePath)", level: .info)
                
                // Update the DayStart in user history with the fetched audioStoragePath
                await MainActor.run {
                    UserPreferences.shared.updateHistory(
                        with: dayStart.id,
                        audioStoragePath: audioStoragePath
                    )
                }
                
                // Now proceed with share using the fetched audioStoragePath
                var updatedDayStart = dayStart
                updatedDayStart.audioStoragePath = audioStoragePath
                createShareWithPath(updatedDayStart, audioStoragePath: audioStoragePath)
                
            } catch {
                // Handle error gracefully
                await MainActor.run {
                    isShareLoading = false
                }
                
                DebugLogger.shared.log("❌ Failed to fetch audioStoragePath: \(error)", level: .error)
                
                // Show user-friendly error message
                await MainActor.run {
                    let alert = UIAlertController(
                        title: "Share Unavailable",
                        message: "This DayStart cannot be shared at the moment. Please try sharing a newer DayStart.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    private func createShareWithPath(_ dayStart: DayStartData, audioStoragePath: String) {
        guard let jobId = dayStart.jobId else {
            DebugLogger.shared.log("❌ Cannot share DayStart: missing jobId", level: .error)
            return
        }
        
        Task {
            do {
                // Show loading indicator
                await MainActor.run {
                    isShareLoading = true
                }
                
                // 1. Create share via API
                let shareResponse = try await SupabaseClient.shared.createShare(
                    jobId: jobId,
                    dayStartData: dayStart,
                    source: "audio_player"
                )
                
                // 2. Create share message
                let shareText = """
Had a great DayStart this morning. It's a short daily briefing that helps me get ahead of the day.
Sharing mine: 🎧 \(shareResponse.shareUrl)
"""
                
                // 3. Present share sheet
                await MainActor.run {
                    let activityVC = UIActivityViewController(
                        activityItems: [shareText],
                        applicationActivities: nil
                    )
                    
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
                    
                    isShareLoading = false
                }
                
                DebugLogger.shared.log("✅ Share created successfully: \(shareResponse.shareUrl)", level: .info)
                
            } catch {
                // Handle error gracefully
                await MainActor.run {
                    isShareLoading = false
                    showShareError = true
                }
                DebugLogger.shared.log("❌ Failed to create share: \(error)", level: .error)
            }
        }
    }
}