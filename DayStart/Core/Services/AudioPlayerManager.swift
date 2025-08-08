import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentTrackId: UUID?
    
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: Timer?
    
    override private init() {
        super.init()
    }
    
    func loadAudio() {
        // Legacy bundled audio fallback
        guard let url = Bundle.main.url(forResource: "ai_wakeup_generic_voice1", withExtension: "mp3") else {
            print("Could not find ai_wakeup_generic_voice1.mp3")
            return
        }
        loadAudio(from: url)
    }

    func loadAudio(from url: URL, trackId: UUID? = nil) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            currentTrackId = trackId
        } catch {
            print("Error loading audio: \(error)")
        }
    }

    func loadAudio(for dayStart: DayStartData) {
        if let path = dayStart.audioFilePath {
            let url = URL(fileURLWithPath: path)
            loadAudio(from: url, trackId: dayStart.id)
        } else {
            // Fallback to bundled sample if specific recording not available
            currentTrackId = dayStart.id
            loadAudio()
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        
        player.play()
        isPlaying = true
        startTimeObserver()
    }
    
    func pause() {
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
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    func skip(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = max(0, min(player.currentTime + seconds, duration))
        seek(to: newTime)
    }
    
    func setPlaybackRate(_ rate: Float) {
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
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        currentTrackId = nil
        stopTimeObserver()
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        stopTimeObserver()
        currentTime = 0
    }
}