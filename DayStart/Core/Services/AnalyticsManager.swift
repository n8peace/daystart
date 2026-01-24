import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

class AnalyticsManager {
    static let shared = AnalyticsManager()
    
    private let logger = DebugLogger.shared
    
    private init() {
        setupCrashlytics()
    }
    
    // MARK: - Setup
    
    private func setupCrashlytics() {
        // Enable crash reporting
        Crashlytics.crashlytics().setCustomValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown", forKey: "app_version")
        Crashlytics.crashlytics().setCustomValue("production", forKey: "user_type")
        
        logger.log("✅ Firebase Crashlytics initialized", level: .info)
    }
    
    // MARK: - Key Analytics Events
    
    func trackDayStartCreated() {
        Analytics.logEvent("daystart_created", parameters: nil)
    }
    
    func trackSubscriptionEvent(_ event: String) {
        Analytics.logEvent("subscription_\(event)", parameters: nil)
    }
    
    func trackError(_ error: Error, context: String) {
        Crashlytics.crashlytics().record(error: error)
        Crashlytics.crashlytics().setCustomValue(context, forKey: "context")
    }
}