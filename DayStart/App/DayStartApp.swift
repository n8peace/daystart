import SwiftUI
import AVFoundation
import UserNotifications
import UIKit
import Combine
import BackgroundTasks

@main
struct DayStartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Delay StateObject creation to avoid heavy initialization
    private var userPreferences: UserPreferences { UserPreferences.shared }
    private var themeManager: ThemeManager { ThemeManager.shared }
    @State private var showOnboarding = false
    @State private var showSplashScreen = true
    @State private var isAppReady = false
    @State private var hasCheckedOnboarding = false
    
    private let logger = DebugLogger.shared
    private static var audioConfigRetryCount = 0
    private static let maxAudioConfigRetries = 3
    
    init() {
        logger.log("🚀 DayStart app initializing", level: .info)
        logger.logMemoryUsage()
        
        // Defer heavy initialization - only set up minimal UI
        // Audio and permissions will be initialized during onboarding countdown
        
        logger.log("✅ App initialization complete", level: .info)
    }
    
    var body: some Scene {
        WindowGroup {
            if showSplashScreen {
                SplashScreenView(isAppReady: $isAppReady) {
                    showSplashScreen = false
                }
                .onAppear {
                    // Start initialization immediately when splash appears
                    Task {
                        await initializeApp()
                    }
                }
            } else {
                ContentView()
                .environmentObject(UserPreferences.shared)
                .environmentObject(ThemeManager.shared)
                .preferredColorScheme(themeManager.effectiveColorScheme)
                .accentColor(BananaTheme.ColorToken.primary)
                .onReceive(themeManager.$effectiveColorScheme) { colorScheme in
                    configureNavigationAppearance(for: colorScheme)
                }
				.onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
					logger.log("🔄 Media services reset - reconfiguring audio session", level: .info)
					Self.audioConfigRetryCount = 0 // Reset retry counter on media services reset
					configureAudioSession()
				}
                .onAppear {
                    logger.log("📱 Main content appeared", level: .info)
                    
                    // Show onboarding if needed (already determined during splash)
                    if hasCheckedOnboarding {
                        showOnboarding = !UserPreferences.shared.hasCompletedOnboarding
                    }
                    
                    // Clean up old audio files in background
                    Task.detached(priority: .background) {
                        await UserPreferences.shared.cleanupOldAudioFiles()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Refresh theme when app enters foreground
                    themeManager.refreshColorScheme()
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView {
                        logger.logUserAction("Onboarding completed")
                        UserPreferences.shared.hasCompletedOnboarding = true
                        showOnboarding = false
                        logger.log("🎓 User completed onboarding - transitioning to main app", level: .info)
                    }
                }
            }
        }
    }
    
    private func configureAudioSession() {
        // Check retry limit to prevent infinite loops
        guard Self.audioConfigRetryCount < Self.maxAudioConfigRetries else {
            logger.log("⚠️ Audio session configuration retry limit reached (\(Self.maxAudioConfigRetries)). Skipping further attempts.", level: .warning)
            return
        }
        
        Self.audioConfigRetryCount += 1
        logger.log("🔧 Configuring audio session (attempt \(Self.audioConfigRetryCount)/\(Self.maxAudioConfigRetries))", level: .debug)
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
			// Configure category and mode with fallback options
			try audioSession.setCategory(
				.playback,
				mode: .spokenAudio,
				options: []
			)
            
            // Set preferred sample rate and buffer duration for stable playback
            try audioSession.setPreferredSampleRate(44100.0)
            // Use larger buffer (256 samples ≈ 5.8ms at 44.1kHz) to prevent dropouts
            try audioSession.setPreferredIOBufferDuration(256.0 / 44100.0)
            
            // Activate session with error handling for system resource conflicts
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            logger.log("✅ Audio session configured successfully", level: .info)
            // Reset retry counter on success
            Self.audioConfigRetryCount = 0
            
        } catch let error as NSError {
            // Handle specific audio session errors gracefully
            logger.log("⚠️ Audio session configuration failed: \(error.localizedDescription)", level: .warning)
            
            // Check for specific error codes we can handle
            if error.code == AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue {
                logger.log("⚠️ Cannot interrupt other audio apps", level: .warning)
			} else if error.domain == NSOSStatusErrorDomain {
				// Handle media services issues with OSStatus errors
				logger.log("🔄 Media services issue detected; will reconfigure on media services reset", level: .warning)
			} else {
                logger.logError(error, context: "Failed to configure audio session")
            }
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.shared.logError(error, context: "Notification permission request failed")
                } else {
                    DebugLogger.shared.logUserAction("Notification permissions", details: ["granted": granted])
                    if granted {
                        DebugLogger.shared.log("✅ Notification permissions granted", level: .info)
                    } else {
                        DebugLogger.shared.log("⚠️ Notification permissions denied", level: .warning)
                    }
                }
            }
        }
    }
    
    private func configureNavigationAppearance(for colorScheme: ColorScheme? = nil) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        // Use dynamic system label color so it adapts automatically
        let labelColor = UIColor.label
        appearance.titleTextAttributes = [.foregroundColor: labelColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: labelColor]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(BananaTheme.ColorToken.accent)
    }
    
    private func initializeApp() async {
        logger.log("🚀 Starting app initialization during splash", level: .info)
        
        // Phase 1: Check onboarding status only (fast)
        let needsOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        await MainActor.run {
            hasCheckedOnboarding = true
        }
        logger.log("🔍 Onboarding check: \(needsOnboarding ? "needed" : "completed")", level: .info)
        
        // Phase 2: Initialize critical services based on user type
        if needsOnboarding {
            // New user: Initialize audio for voice preview in onboarding
            logger.log("🎵 Initializing audio for onboarding", level: .info)
            await MainActor.run {
                _ = AudioPlayerManager.shared
                configureAudioSession()
            }
        } else {
            // Existing user: Load minimal data needed for home screen
            logger.log("📦 Loading user data for existing user", level: .info)
            // UserPreferences will lazy load when accessed
        }
        
        // Phase 3: Mark app as ready
        await MainActor.run {
            isAppReady = true
            logger.log("✅ App initialization complete, dismissing splash", level: .info)
        }
        
        // Phase 4: Background tasks (non-blocking)
        if !needsOnboarding {
            Task.detached(priority: .background) {
                // Trigger lazy loading of heavy data in background for existing users
                // This will load settings and history when first accessed
                await DebugLogger.shared.log("📦 Background ready for lazy loading", level: .debug)
            }
        }
    }
}

struct ContentView: View {
    // Lazy initialization to prevent AudioPlayerManager from loading at startup
    @StateObject private var homeViewModel = HomeViewModel(lazyInit: true)
    private let logger = DebugLogger.shared
    
    var body: some View {
        HomeView(viewModel: homeViewModel)
            .onAppear {
            }
    }
}

// MARK: - App Delegate for Background Tasks

class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = DebugLogger.shared
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Defer background task registration - will be done after onboarding
        // This prevents AudioPrefetchManager from initializing at startup
        logger.log("📱 App launched - deferring background task registration", level: .info)
        
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.log("📱 App entering foreground - checking for upcoming DayStarts", level: .info)
        
        Task { @MainActor in
            await AudioPrefetchManager.shared.checkForUpcomingDayStarts()
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.log("🌙 App entered background", level: .debug)
        
        // Clean up old cache when app goes to background
        Task {
            AudioCache.shared.clearOldCache()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.log("❌ App terminating - cancelling downloads", level: .info)
        
        Task { @MainActor in
            AudioDownloader.shared.cancelAllDownloads()
            AudioPrefetchManager.shared.cancelAllBackgroundTasks()
        }
    }
}