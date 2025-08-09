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
    
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: Timer?
    private var previewPlayer: AVAudioPlayer?
    private var previewStopWorkItem: DispatchWorkItem?
    
    override private init() {
        super.init()
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
            currentTrackId = trackId
            logger.logAudioEvent("Audio loaded successfully", details: ["duration": duration])
        } catch {
            logger.logError(error, context: "Failed to load audio from \(url.lastPathComponent)")
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
        
        logger.logAudioEvent("Playing audio", details: ["rate": playbackRate])
        player.play()
        isPlaying = true
        startTimeObserver()
    }
    
    func pause() {
        logger.logAudioEvent("Pausing audio")
        audioPlayer?.pause()
        isPlaying = false
        stopTimeObserver()
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
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
        currentTrackId = nil
        stopTimeObserver()
    }
    
    // MARK: - Voice Preview
    func previewVoice(_ voice: VoiceOption) {
        let voiceIndex = voice.rawValue + 1
        let resourceName = "ai_wakeup_generic_voice\(voiceIndex)"
        
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            logger.logError(NSError(domain: "AudioPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find \(resourceName).mp3"]), context: "Previewing voice")
            return
        }
        
        logger.logUserAction("Preview voice", details: ["voice": voice.name])
        
        // Stop any existing preview immediately
        stopVoicePreview()
        
        do {
            let newPreviewPlayer = try AVAudioPlayer(contentsOf: url)
            newPreviewPlayer.prepareToPlay()
            self.previewPlayer = newPreviewPlayer
            newPreviewPlayer.play()
            
            // Schedule auto-stop after 3 seconds
            let workItem = DispatchWorkItem { [weak self] in
                self?.previewPlayer?.stop()
                self?.previewPlayer = nil
                self?.previewStopWorkItem = nil
            }
            self.previewStopWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        } catch {
            logger.logError(error, context: "Failed to preview voice \(voice.name)")
        }
    }

    func stopVoicePreview() {
        // Cancel any scheduled auto-stop
        previewStopWorkItem?.cancel()
        previewStopWorkItem = nil
        
        // Stop and release preview player
        previewPlayer?.stop()
        previewPlayer = nil
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logger.logAudioEvent("Audio playback finished", details: ["successful": flag])
        isPlaying = false
        stopTimeObserver()
        currentTime = 0
    }
}