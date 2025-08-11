import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()
    private let logger = DebugLogger.shared
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentTrackId: UUID?
    @Published var didFinishPlaying = false
    
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: Timer?
    private var previewPlayer: AVAudioPlayer?
    private var previewStopWorkItem: DispatchWorkItem?
    
    // Player coordination state
    private var wasPlayingBeforePreview = false
    private var playbackPositionBeforePreview: TimeInterval = 0
    
    // Notification names for player coordination
    static let willStartPlayingNotification = Notification.Name("AudioPlayerManager.willStartPlaying")
    static let didStopPlayingNotification = Notification.Name("AudioPlayerManager.didStopPlaying")
    
    override private init() {
        super.init()
        setupAudioSessionObservers()
        logger.log("🎵 AudioPlayerManager initialized", level: .info)
    }
    
    func loadAudio() {
        // Get selected voice from preferences
        let voiceIndex = UserPreferences.shared.settings.selectedVoice.rawValue + 1
        let resourceName = "ai_wakeup_generic_voice\(voiceIndex)"
        
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            logger.logError(NSError(domain: "AudioPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find \(resourceName).mp3"]), context: "Loading bundled audio")
            // Fallback to voice1 if selected voice not found
            if let fallbackUrl = Bundle.main.url(forResource: "ai_wakeup_generic_voice1", withExtension: "mp3") {
                logger.log("🔄 Falling back to voice1", level: .warning)
                loadAudio(from: fallbackUrl)
            }
            return
        }
        logger.logAudioEvent("Loading bundled audio file", details: ["voice": "voice\(voiceIndex)"])
        loadAudio(from: url)
    }

    func loadAudio(from url: URL, trackId: UUID? = nil) {
        logger.logAudioEvent("Loading audio from URL", details: ["url": url.lastPathComponent, "trackId": trackId?.uuidString ?? "none"])
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            didFinishPlaying = false
            currentTrackId = trackId
            logger.logAudioEvent("Audio loaded successfully", details: ["duration": duration])
        } catch {
            logger.logError(error, context: "Failed to load audio from \(url.lastPathComponent)")
        }
    }
    
    func loadAudio(from url: URL, trackId: UUID? = nil, completion: @escaping (Bool, Error?) -> Void) {
        logger.logAudioEvent("Loading audio from URL with completion", details: ["url": url.lastPathComponent, "trackId": trackId?.uuidString ?? "none"])
        
        Task.detached { [weak self] in
            do {
                // Test the URL first to check for network issues
                let (_, response) = try await URLSession.shared.data(from: url)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 403 {
                        await MainActor.run {
                            completion(false, NSError(domain: "AudioLoadError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Audio URL expired"]))
                        }
                        return
                    } else if httpResponse.statusCode != 200 {
                        await MainActor.run {
                            completion(false, NSError(domain: "AudioLoadError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"]))
                        }
                        return
                    }
                }
                
                // URL is valid, now load into audio player on main thread
                await MainActor.run { [weak self] in
                    guard let self = self else {
                        completion(false, NSError(domain: "AudioLoadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "AudioPlayerManager deallocated"]))
                        return
                    }
                    
                    do {
                        self.audioPlayer = try AVAudioPlayer(contentsOf: url)
                        self.audioPlayer?.delegate = self
                        self.audioPlayer?.enableRate = true
                        self.audioPlayer?.prepareToPlay()
                        self.duration = self.audioPlayer?.duration ?? 0
                        self.currentTime = 0
                        self.didFinishPlaying = false
                        self.currentTrackId = trackId
                        self.logger.logAudioEvent("Audio loaded successfully with completion", details: ["duration": self.duration])
                        completion(true, nil)
                    } catch {
                        self.logger.logError(error, context: "Failed to load audio from \(url.lastPathComponent)")
                        completion(false, error)
                    }
                }
                
            } catch {
                await MainActor.run {
                    self?.logger.logError(error, context: "Failed to validate audio URL \(url.lastPathComponent)")
                    completion(false, error)
                }
            }
        }
    }

    func loadAudio(for dayStart: DayStartData) {
        guard let path = dayStart.audioFilePath else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        loadAudio(from: url, trackId: dayStart.id)
    }
    
    func play() {
        guard let player = audioPlayer else {
            logger.log("⚠️ Attempted to play with no audio loaded", level: .warning)
            return
        }
        
        // Notify other players that main player is starting
        NotificationCenter.default.post(name: Self.willStartPlayingNotification, object: self)
        
        logger.logAudioEvent("Playing audio", details: ["rate": playbackRate])
        player.rate = playbackRate
        player.play()
        isPlaying = true
        didFinishPlaying = false
        startTimeObserver()
    }
    
    func pause() {
        logger.logAudioEvent("Pausing audio")
        audioPlayer?.pause()
        isPlaying = false
        stopTimeObserver()
        
        // Notify other players that main player stopped
        NotificationCenter.default.post(name: Self.didStopPlayingNotification, object: self)
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        logger.logAudioEvent("Seeking audio", details: ["time": String(format: "%.1f", time)])
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func skip(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = max(0, min(player.currentTime + seconds, duration))
        seek(to: newTime)
    }
    
    func setPlaybackRate(_ rate: Float) {
        logger.logAudioEvent("Changing playback rate", details: ["rate": rate])
        audioPlayer?.rate = rate
        playbackRate = rate
    }
    
    private func startTimeObserver() {
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }
    
    private func stopTimeObserver() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    private func updateTime() {
        currentTime = audioPlayer?.currentTime ?? 0
    }
    
    func reset() {
        logger.logAudioEvent("Resetting audio player")
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        didFinishPlaying = false
        currentTrackId = nil
        stopTimeObserver()
    }
    
    // MARK: - Helper Methods
    private func getVoicePreviewResourceName(for voice: VoiceOption) -> String {
        switch voice {
        case .voice1:
            return "briefing_sample_grace_voice1"
        case .voice2:
            return "briefing_sample_rachel_voice2"
        case .voice3:
            return "briefing_sample_matthew_voice3"
        }
    }
    
    // MARK: - Audio Session Management
    private func setupAudioSessionObservers() {
        // Interruption handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // Route change handling (headphones, Bluetooth, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        logger.log("🔊 Audio session observers configured", level: .info)
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption began - pause playback
            logger.logAudioEvent("Audio interruption began - pausing playback")
            if isPlaying {
                pause()
            }
            // Also pause any preview that might be playing
            stopVoicePreview()
            
        case .ended:
            // Interruption ended - check if we should resume
            logger.logAudioEvent("Audio interruption ended")
            
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // System says we should resume - but let user decide
                    logger.logAudioEvent("System suggests resuming audio")
                    reactivateAudioSession()
                }
            }
            
        @unknown default:
            logger.log("⚠️ Unknown audio interruption type: \(typeValue)", level: .warning)
        }
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged or Bluetooth disconnected - pause playback
            logger.logAudioEvent("Audio device disconnected - pausing playback")
            if isPlaying {
                pause()
            }
            stopVoicePreview()
            
        case .newDeviceAvailable:
            // New device connected - just log it
            logger.logAudioEvent("New audio device connected")
            
        case .categoryChange, .override:
            // Audio category changed - reactivate session
            logger.logAudioEvent("Audio category changed - reactivating session")
            reactivateAudioSession()
            
        default:
            logger.logAudioEvent("Audio route changed", details: ["reason": reason.rawValue])
        }
    }
    
    private func reactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            logger.logAudioEvent("Audio session reactivated successfully")
        } catch {
            logger.logError(error, context: "Failed to reactivate audio session")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTimeObserver()
        audioPlayer?.stop()
        previewPlayer?.stop()
        logger.log("🎵 AudioPlayerManager deinitialized", level: .info)
    }
    
    // MARK: - Voice Preview
    func previewVoice(_ voice: VoiceOption) {
        let resourceName = getVoicePreviewResourceName(for: voice)
        
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            logger.logError(NSError(domain: "AudioPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find \(resourceName).mp3"]), context: "Previewing voice")
            return
        }
        
        logger.logUserAction("Preview voice", details: ["voice": voice.name])
        
        // Stop any existing preview immediately
        stopVoicePreview()
        
        // Coordinate with main player - pause if playing and save state
        if isPlaying {
            wasPlayingBeforePreview = true
            playbackPositionBeforePreview = currentTime
            logger.logAudioEvent("Pausing main player for voice preview", details: [
                "currentTime": playbackPositionBeforePreview
            ])
            pause()
        } else {
            wasPlayingBeforePreview = false
            playbackPositionBeforePreview = 0
        }
        
        do {
            let newPreviewPlayer = try AVAudioPlayer(contentsOf: url)
            newPreviewPlayer.delegate = self
            newPreviewPlayer.prepareToPlay()
            self.previewPlayer = newPreviewPlayer
            
            if newPreviewPlayer.play() {
                logger.logAudioEvent("Voice preview started successfully")
                
                // Auto-stop preview after the audio finishes naturally or after 10 seconds max
                let previewDuration = min(newPreviewPlayer.duration, 10.0)
                previewStopWorkItem = DispatchWorkItem { [weak self] in
                    self?.stopVoicePreview()
                }
                
                if let workItem = previewStopWorkItem {
                    DispatchQueue.main.asyncAfter(deadline: .now() + previewDuration + 0.5, execute: workItem)
                }
            } else {
                logger.logAudioEvent("Failed to start voice preview")
                restoreMainPlayerAfterPreview()
            }
        } catch {
            logger.logError(error, context: "Failed to preview voice \(voice.name)")
            restoreMainPlayerAfterPreview()
        }
    }

    func stopVoicePreview() {
        // Cancel any scheduled auto-stop
        previewStopWorkItem?.cancel()
        previewStopWorkItem = nil
        
        // Stop and release preview player
        previewPlayer?.stop()
        previewPlayer = nil
        
        // Restore main player if it was playing before preview
        restoreMainPlayerAfterPreview()
    }
    
    private func restoreMainPlayerAfterPreview() {
        if wasPlayingBeforePreview && audioPlayer != nil {
            logger.logAudioEvent("Restoring main player after voice preview", details: [
                "resumePosition": playbackPositionBeforePreview
            ])
            
            // Restore position if it was saved
            if playbackPositionBeforePreview > 0 {
                seek(to: playbackPositionBeforePreview)
            }
            
            // Resume playback
            play()
        }
        
        // Reset coordination state
        wasPlayingBeforePreview = false
        playbackPositionBeforePreview = 0
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Check if this is the main player or preview player
        if player === audioPlayer {
            // Main player finished
            logger.logAudioEvent("Main audio playback finished", details: ["successful": flag])
            isPlaying = false
            didFinishPlaying = true
            stopTimeObserver()
            currentTime = 0
        } else if player === previewPlayer {
            // Preview player finished - restore main player if needed
            logger.logAudioEvent("Voice preview finished", details: ["successful": flag])
            stopVoicePreview() // This will call restoreMainPlayerAfterPreview()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let errorDesc = error?.localizedDescription ?? "Unknown decode error"
        
        if player === audioPlayer {
            logger.logError(error ?? NSError(domain: "AudioDecodeError", code: -1), 
                          context: "Main audio player decode error")
            isPlaying = false
            stopTimeObserver()
        } else if player === previewPlayer {
            logger.logError(error ?? NSError(domain: "AudioDecodeError", code: -1), 
                          context: "Preview audio player decode error")
            stopVoicePreview()
        }
    }
}