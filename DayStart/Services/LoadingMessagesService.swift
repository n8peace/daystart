import Foundation
import SwiftUI
import Combine

class LoadingMessagesService: ObservableObject {
    static let shared = LoadingMessagesService()
    
    @Published var currentMessage = ""
    
    private var messageTimer: Timer?
    private var currentIndex = 0
    
    private let messages = [
        "Fetching the greatness...",
        "Ripening the bananas...",
        "Warming up the vocal cords...",
        "Brewing your morning magic...",
        "Polishing your daily dose...",
        "Summoning the day's wisdom...",
        "Loading premium content...",
        "Tuning the morning frequency...",
        "Gathering today's insights...",
        "Preparing your audio adventure...",
        "Stirring the inspiration pot...",
        "Charging the motivation cells...",
        "Calibrating the awesome meter...",
        "Harvesting fresh ideas...",
        "Assembling your day's soundtrack...",
        "Cooking up some brilliance...",
        "Crafting your perfect start...",
        "Mixing the perfect blend...",
        "Powering up the positivity...",
        "Brewing liquid motivation...",
        "Loading today's superpowers...",
        "Packaging pure excellence...",
        "Preparing your daily boost...",
        "Warming up the wisdom engine...",
        "Gathering morning miracles...",
        "Baking fresh perspectives...",
        "Distilling pure focus...",
        "Marinating the good vibes...",
        "Weaving threads of success...",
        "Cultivating your winning mood...",
        "Prepping the productivity juice...",
        "Loading your daily upgrade..."
    ]
    
    private init() {
        // Start with a random message
        currentIndex = Int.random(in: 0..<messages.count)
        currentMessage = messages[currentIndex]
    }
    
    func startRotatingMessages() {
        // Update message every 2.5 seconds
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.rotateToNextMessage()
        }
    }
    
    func stopRotatingMessages() {
        messageTimer?.invalidate()
        messageTimer = nil
    }
    
    private func rotateToNextMessage() {
        currentIndex = (currentIndex + 1) % messages.count
        withAnimation(.easeInOut(duration: 0.3)) {
            currentMessage = messages[currentIndex]
        }
    }
    
    func getRandomMessage() -> String {
        return messages.randomElement() ?? "Getting ready..."
    }
}