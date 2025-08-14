import Foundation
import AVFoundation
import CoreMedia
import SwiftUI
import Combine
import MediaPlayer

class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()
    private let logger = DebugLogger.shared
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentTrackId: UUID?
    @Published var didFinishPlaying = false
    
    private var audioPlayer: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var displayLink: Timer?
    private var previewPlayer: AVAudioPlayer?
    private var previewStopWorkItem: DispatchWorkItem?
    private var nowPlayingInfo: [String: Any] = [:]
    
    // KVO observers for AVPlayer
    private var statusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    
    // Player coordination state
    private var wasPlayingBeforePreview = false
    private var playbackPositionBeforePreview: TimeInterval = 0
    
    // Notification names for player coordination
    static let willStartPlayingNotification = Notification.Name("AudioPlayerManager.willStartPlaying")
    static let didStopPlayingNotification = Notification.Name("AudioPlayerManager.didStopPlaying")
    
    override private init() {
        super.init()
        // Defer heavy setup until first use
        logger.log("🎵 AudioPlayerManager initialized (lightweight)", level: .info)
    }
    
    private var isSetupComplete = false
    private func ensureSetup() {
        guard !isSetupComplete else { return }
        isSetupComplete = true
        setupAudioSessionObservers()
        setupRemoteCommands()
        logger.log("🎵 AudioPlayerManager setup complete", level: .info)
    }
    
    func loadAudio() {
        ensureSetup()
        // Get selected voice from preferences
        let selectedVoice = UserPreferences.shared.settings.selectedVoice
        let resourceName = "voice\(selectedVoice.rawValue + 1)_fallback"
        
        logger.log("[DEBUG] Loading fallback audio with voice: \(selectedVoice.name) (\(resourceName))", level: .debug)
        
        // Files are bundled to root instead of Audio/Fallbacks subdirectory
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            logger.logError(NSError(domain: "AudioPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find \(resourceName).mp3"]), context: "Loading bundled audio")
            // Fallback to voice1 if selected voice not found
            if let fallbackUrl = Bundle.main.url(forResource: "voice1_fallback", withExtension: "mp3") {
                logger.log("🔄 Falling back to voice1", level: .warning)
                loadAudio(from: fallbackUrl)
            }
            return
        }
        logger.logAudioEvent("Loading bundled audio file", details: ["voice": "voice\(selectedVoice.rawValue + 1)"])
        loadAudio(from: url)
    }

    func loadAudio(from url: URL, trackId: UUID? = nil) {
        loadAudio(from: url, trackId: trackId) { success, error in
            if let error = error {
                self.logger.logError(error, context: "Failed to load audio from \(url.lastPathComponent)")
            }
        }
    }
    
    func loadAudio(from url: URL, trackId: UUID? = nil, completion: @escaping (Bool, Error?) -> Void) {
        ensureSetup()
        logger.logAudioEvent("Loading audio from URL with completion", details: ["url": url.lastPathComponent, "trackId": trackId?.uuidString ?? "none"])
        
        // Clean up any existing player and observers
        cleanup()
        
        // Log more details about the URL for debugging
        logger.log("[DEBUG] Creating AVPlayer with URL: \(url.absoluteString)", level: .debug)
        
        // Create AVPlayerItem and AVPlayer
        playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        guard playerItem != nil, audioPlayer != nil else {
            completion(false, NSError(domain: "AudioLoadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVPlayer"]))
            return
        }
        
        currentTime = 0
        didFinishPlaying = false
        currentTrackId = trackId
        
        // Set up KVO observers
        setupObservers(completion: completion)
    }
    
    private func setupObservers(completion: @escaping (Bool, Error?) -> Void) {
        guard let playerItem = playerItem else {
            completion(false, NSError(domain: "AudioLoadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No player item"]))
            return
        }
        
        // Observe player item status
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.duration = item.duration.seconds
                    self?.logger.logAudioEvent("Audio loaded successfully with completion", details: ["duration": item.duration.seconds])
				self?.updateNowPlayingInfo(title: "DayStart")
                    completion(true, nil)
                case .failed:
                    let error = item.error ?? NSError(domain: "AudioLoadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player item failed"])
                    self?.logger.logError(error, context: "Failed to load audio from URL")
                    completion(false, error)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        
        // Observe time control status for play/pause state
        timeControlStatusObserver = audioPlayer?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = (player.timeControlStatus == .playing)
            }
        }
        
        // Listen for playback completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    private func cleanup() {
        // Remove observers
        statusObserver?.invalidate()
        timeControlStatusObserver?.invalidate()
        durationObserver?.invalidate()
        
        statusObserver = nil
        timeControlStatusObserver = nil
        durationObserver = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        // Stop and release player
        audioPlayer?.pause()
        audioPlayer = nil
        playerItem = nil
    }
    
    @objc private func playerDidFinishPlaying() {
        DispatchQueue.main.async { [weak self] in
            self?.didFinishPlaying = true
            self?.stopTimeObserver()
            self?.currentTime = 0
        }
    }

    func loadAudio(for dayStart: DayStartData) {
        guard let path = dayStart.audioFilePath else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        loadAudio(from: url, trackId: dayStart.id)
    }
    
    // PHASE 4: Try to load from preloaded items first, fallback to URL loading
    func loadAudioInstantly(for date: Date, trackId: UUID? = nil) -> Bool {
        ensureSetup()
        
        // Try preloaded player item first
        if let preloadedItem = AudioPrefetchManager.shared.getPreloadedPlayerItem(for: date) {
            logger.log("🚀 Using preloaded player item for instant start", level: .info)
            
            // Clean up any existing player and observers
            cleanup()
            
            // Set up the preloaded item
            playerItem = preloadedItem
            audioPlayer = AVPlayer(playerItem: preloadedItem)
            currentTrackId = trackId
            
            // Set duration if available
            if preloadedItem.duration.isValid && !preloadedItem.duration.isIndefinite {
                duration = preloadedItem.duration.seconds
            }
            
            // Set up observers for the preloaded item
            setupObserversForPreloadedItem(preloadedItem)
            
            return true
        }
        
        logger.log("🚀 No preloaded item available, will use regular loading", level: .debug)
        return false
    }
    
    // PHASE 4: Set up observers for preloaded items (simplified version of loadAudio observers)
    private func setupObserversForPreloadedItem(_ item: AVPlayerItem) {
        // Observe player item status
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.duration = item.duration.seconds
                    self?.logger.log("✅ Preloaded audio ready to play", level: .info)
                    self?.updateNowPlayingInfo(title: "DayStart")
                case .failed:
                    let error = item.error ?? NSError(domain: "AudioLoadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Preloaded item failed"])
                    self?.logger.logError(error, context: "Preloaded audio item failed")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        
        // Observe time control status for play/pause state
        timeControlStatusObserver = audioPlayer?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = (player.timeControlStatus == .playing)
            }
        }
        
        // Listen for playback completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }
    
    func play() {
        ensureSetup()
        guard let player = audioPlayer else {
            logger.log("⚠️ Attempted to play with no audio loaded", level: .warning)
            return
        }
        
        // Notify other players that main player is starting
        NotificationCenter.default.post(name: Self.willStartPlayingNotification, object: self)
        
        logger.logAudioEvent("Playing audio", details: ["rate": playbackRate])
        player.rate = playbackRate
        player.play()
        didFinishPlaying = false
        startTimeObserver()

		// Reflect play state on lock screen
		updateNowPlayingPlaybackState()
    }
    
    func pause() {
        ensureSetup()
        logger.logAudioEvent("Pausing audio")
        audioPlayer?.pause()
        stopTimeObserver()
        
        // Notify other players that main player stopped
        NotificationCenter.default.post(name: Self.didStopPlayingNotification, object: self)

		// Reflect pause state on lock screen
		updateNowPlayingPlaybackState()
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
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        audioPlayer?.seek(to: cmTime)
        currentTime = time
		updateNowPlayingElapsedTime()
    }
    
    func skip(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let currentSeconds = player.currentTime().seconds
        let newTime = max(0, min(currentSeconds + seconds, duration))
        seek(to: newTime)
    }
    
    func setPlaybackRate(_ rate: Float) {
        logger.logAudioEvent("Changing playback rate", details: ["rate": rate])
        audioPlayer?.rate = rate
        playbackRate = rate
		updateNowPlayingPlaybackState()
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
        if let player = audioPlayer {
            currentTime = player.currentTime().seconds
            updateNowPlayingElapsedTime()
        }
    }
    
    func reset() {
        logger.logAudioEvent("Resetting audio player")
        audioPlayer?.pause()
        audioPlayer?.seek(to: CMTime.zero)
        currentTime = 0
        didFinishPlaying = false
        currentTrackId = nil
        stopTimeObserver()
    }
    
    // MARK: - Helper Methods
    private func getVoicePreviewResourceName(for voice: VoiceOption) -> String {
        let fileName = "voice\(voice.rawValue + 1)_sample"
        return fileName
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
            // Keep lock-screen state consistent after reactivation
            updateNowPlayingPlaybackState()
        } catch {
            logger.logError(error, context: "Failed to reactivate audio session")
        }
    }
    
    deinit {
        cleanup()
        NotificationCenter.default.removeObserver(self)
        stopTimeObserver()
        previewPlayer?.stop()
        logger.log("🎵 AudioPlayerManager deinitialized", level: .info)
    }
    
    // MARK: - Voice Preview
    func previewVoice(_ voice: VoiceOption) {
        ensureSetup()
        let resourceName = getVoicePreviewResourceName(for: voice)
        
        // Files are bundled to root instead of Audio/Samples subdirectory
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
            // Ensure audio session is active
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            let newPreviewPlayer = try AVAudioPlayer(contentsOf: url)
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

    // MARK: - Now Playing / Remote Commands
    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            self?.play(); return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.pause(); return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        commands.skipForwardCommand.isEnabled = true
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(by: 15); return .success
        }
        commands.skipBackwardCommand.isEnabled = true
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(by: -15); return .success
        }
    }

    private func updateNowPlayingInfo(title: String, artist: String? = nil, artwork: UIImage? = nil) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist ?? "DayStart"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let image = artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingElapsedTime() {
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingPlaybackState() {
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

