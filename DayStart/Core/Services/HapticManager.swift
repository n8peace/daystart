import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    private var lastHapticTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 0.1 // 100ms throttle
    private let logger = DebugLogger.shared
    
    private lazy var impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private lazy var selectionFeedback = UISelectionFeedbackGenerator()
    private lazy var notificationFeedback = UINotificationFeedbackGenerator()
    
    private var isHapticCapable: Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }
    
    private init() {
        // Prepare generators only if device supports haptics
        if isHapticCapable {
            impactFeedback.prepare()
            selectionFeedback.prepare()
            notificationFeedback.prepare()
        }
    }
    
    private func shouldAllowHaptic() -> Bool {
        let now = Date()
        let timeSinceLastHaptic = now.timeIntervalSince(lastHapticTime)
        
        guard timeSinceLastHaptic >= throttleInterval else {
            return false
        }
        
        guard isHapticCapable else {
            return false
        }
        
        lastHapticTime = now
        return true
    }
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard shouldAllowHaptic() else { return }
        
        do {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        } catch {
            logger.logError(error, context: "Haptic impact feedback failed")
        }
    }
    
    func selection() {
        guard shouldAllowHaptic() else { return }
        
        do {
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
        } catch {
            logger.logError(error, context: "Haptic selection feedback failed")
        }
    }
    
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard shouldAllowHaptic() else { return }
        
        do {
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(type)
        } catch {
            logger.logError(error, context: "Haptic notification feedback failed")
        }
    }
}