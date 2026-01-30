import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics
import FirebasePerformance

class AnalyticsManager {
    static let shared = AnalyticsManager()

    private let logger = DebugLogger.shared
    private var activeTraces: [String: Trace] = [:]

    private init() {
        setupFirebase()
    }

    // MARK: - Setup

    private func setupFirebase() {
        // Configure Crashlytics
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Crashlytics.crashlytics().setCustomValue(version, forKey: "app_version")
        Crashlytics.crashlytics().setCustomValue("production", forKey: "user_type")

        // Enable automatic screen tracking
        Analytics.setAnalyticsCollectionEnabled(true)

        logger.log("✅ Firebase Analytics & Crashlytics initialized", level: .info)
    }

    // MARK: - Analytics Events

    func trackDayStartCreated() {
        Analytics.logEvent("daystart_created", parameters: nil)
    }

    func trackSubscriptionEvent(_ event: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent("subscription_\(event)", parameters: parameters)
    }

    func trackError(_ error: Error, context: String) {
        Crashlytics.crashlytics().record(error: error)
        Crashlytics.crashlytics().setCustomValue(context, forKey: "context")
    }

    func trackScreen(_ screenName: String, screenClass: String? = nil) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenClass ?? screenName
        ])
    }

    func trackEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(eventName, parameters: parameters)
    }

    // MARK: - Performance Monitoring

    func startTrace(_ traceName: String) {
        guard let trace = Performance.startTrace(name: traceName) else {
            logger.log("⚠️ Failed to start trace: \(traceName)", level: .warning)
            return
        }
        activeTraces[traceName] = trace
        logger.log("📊 Started performance trace: \(traceName)", level: .debug)
    }

    func stopTrace(_ traceName: String, metrics: [String: Int64]? = nil) {
        guard let trace = activeTraces[traceName] else {
            logger.log("⚠️ No active trace found: \(traceName)", level: .warning)
            return
        }

        // Add custom metrics
        if let metrics = metrics {
            for (key, value) in metrics {
                trace.setValue(value, forMetric: key)
            }
        }

        trace.stop()
        activeTraces.removeValue(forKey: traceName)
        logger.log("📊 Stopped performance trace: \(traceName)", level: .debug)
    }

    func incrementMetric(_ traceName: String, metricName: String, by value: Int64 = 1) {
        guard let trace = activeTraces[traceName] else {
            logger.log("⚠️ No active trace found: \(traceName)", level: .warning)
            return
        }
        trace.incrementMetric(metricName, by: value)
    }

    // MARK: - User Properties

    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }
}