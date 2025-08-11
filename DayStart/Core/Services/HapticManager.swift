import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    private var lastHapticTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 0.1 // 100ms throttle
    private let logger = DebugLogger.shared
    
    private lazy var impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private lazy var selectionFeedback = UISelectionFeedbackGenerator()
    private lazy var notificationFeedback = UINotificationFeedbackGenerator()
    
    // Track if we've already logged haptic unavailability to avoid spam
    private var hasLoggedUnavailability = false
    
    private var isHapticCapable: Bool {
        // Check device type
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return false
        }
        
        // Check if we're in simulator
        #if targetEnvironment(simulator)
        return false
        #else
        // Check if the device actually supports haptics
        // iPhone 6s and later support haptics
        let device = UIDevice.current
        if let modelCode = deviceModelCode(), 
           modelCode.contains("iPhone") {
            // Extract major version number from model codes like "iPhone8,1"
            let components = modelCode.replacingOccurrences(of: "iPhone", with: "").components(separatedBy: ",")
            if let majorVersion = components.first, let version = Int(majorVersion) {
                return version >= 8 // iPhone 6s is iPhone8,x
            }
        }
        
        return true // Default to true for newer devices
        #endif
    }
    
    private func deviceModelCode() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value))!)
        }
        return identifier.isEmpty ? nil : identifier
    }
    
    private init() {
        // Prepare generators only if device supports haptics
        if isHapticCapable {
            do {
                impactFeedback.prepare()
                selectionFeedback.prepare() 
                notificationFeedback.prepare()
                logger.log("🔊 Haptic feedback initialized successfully", level: .debug)
            } catch {
                logger.log("⚠️ Failed to initialize haptic feedback: \(error)", level: .warning)
            }
        } else {
            if !hasLoggedUnavailability {
                #if targetEnvironment(simulator)
                logger.log("🔊 Haptics disabled (simulator environment)", level: .debug)
                #else
                logger.log("🔊 Haptics not available on this device", level: .debug)
                #endif
                hasLoggedUnavailability = true
            }
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
        
        performHapticSafely {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
    
    func selection() {
        guard shouldAllowHaptic() else { return }
        
        performHapticSafely {
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
        }
    }
    
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard shouldAllowHaptic() else { return }
        
        performHapticSafely {
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(type)
        }
    }
    
    private func performHapticSafely(_ hapticAction: () -> Void) {
        do {
            hapticAction()
        } catch {
            // Silently handle haptic errors to avoid log spam
            // Only log if we haven't already logged unavailability
            if !hasLoggedUnavailability {
                logger.log("⚠️ Haptic feedback failed: \(error.localizedDescription)", level: .debug)
            }
        }
    }
}