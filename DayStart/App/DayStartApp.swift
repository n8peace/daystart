import SwiftUI
import AVFoundation
import UserNotifications
import UIKit
import Combine
import BackgroundTasks
import MediaPlayer

/// Minimal DayStartApp with aggressive service deferral
/// Only loads 3 essential services on startup for Spotify-level performance
@main
struct DayStartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // TIER 1: Only essential services (no lazy loading needed)
    private var userPreferences: UserPreferences { UserPreferences.shared }
    @StateObject var themeManager = ThemeManager.shared  // Made internal for auth extension
    
    // Purchase state
    @StateObject var purchaseManager = PurchaseManager.shared
    
    // Logger for auth extension  
    internal let logger = DebugLogger.shared
    
    private static var audioConfigRetryCount = 0
    private static let maxAudioConfigRetries = 3
    
    init() {
        // MINIMAL: Only essential UI setup (no service initialization)
        configureBasicNavigationAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            authenticatedContentView()
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
                    Self.audioConfigRetryCount = 0
                    Task {
                        await reconfigureAudioSessionIfNeeded()
                    }
                }
                .onAppear {
                    // DEFERRED: All heavy initialization happens after UI appears
                    Task {
                        await deferredAppInitialization()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    themeManager.refreshColorScheme()
                    
                    // LAZY: Only pre-warm if audio system is already loaded
                    Task.detached {
                        await preWarmLoadedServicesOnForeground()
                    }
                    
                    // Trigger snapshot updates when app comes to foreground
                    Task.detached {
                        await triggerSnapshotUpdateOnForeground()
                    }
                }
        }
    }
    
    // MARK: - Minimal UI Setup (Instant)
    
    private func configureBasicNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        let labelColor = UIColor.label
        appearance.titleTextAttributes = [.foregroundColor: labelColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: labelColor]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(BananaTheme.ColorToken.accent)
    }
    
    func updateNavigationAppearance(for colorScheme: ColorScheme) {  // Made internal for auth extension
        // Dynamic appearance updates (lightweight)
        configureBasicNavigationAppearance()
    }
    
    // MARK: - Deferred Initialization (Background)
    
    private func deferredAppInitialization() async {
        // CRITICAL: Pre-warm only what prevents keyboard lag
        Task.detached(priority: .background) {
            await self.preWarmKeyboardLagFix()
        }
        
        // DEFERRED: Background cleanup (non-blocking)
        // Only run cleanup if user has completed onboarding
        if UserPreferences.shared.hasCompletedOnboarding {
            Task.detached(priority: .background) {
                await UserPreferences.shared.cleanupOldAudioFiles()
            }
        }
    }
    
    /// Pre-warm only what's essential to prevent keyboard lag
    private func preWarmKeyboardLagFix() async {
        do {
            // 1. Pre-warm MPRemoteCommandCenter (main keyboard lag cause)
            let _ = MPRemoteCommandCenter.shared()
            
            // 2. Configure basic audio session
            try await configureAudioSessionAsync()
            
            await DebugLogger.shared.log("✅ Keyboard lag prevention complete", level: .info)
            
        } catch {
            await DebugLogger.shared.logError(error, context: "Pre-warming keyboard lag fix")
        }
    }
    
    /// Basic audio session configuration (lightweight)
    private func configureAudioSessionAsync() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.setCategory(
            .playback,
            mode: .spokenAudio,
            options: []
        )
        
        try audioSession.setPreferredSampleRate(44100.0)
        try audioSession.setPreferredIOBufferDuration(0.005)
    }
    
    /// Only pre-warm services that are already loaded
    private func preWarmLoadedServicesOnForeground() async {
        await MainActor.run {
            let registry = ServiceRegistry.shared
            
            // Only check for upcoming DayStarts if AudioPrefetchManager is already loaded
            if registry.loadedServices.contains("AudioPrefetchManager") {
                Task {
                    await registry.audioPrefetchManager.checkForUpcomingDayStarts()
                }
            }
            
            // Only pre-warm location if LocationManager is already loaded
            if registry.loadedServices.contains("LocationManager"),
               let locationManager = registry.locationManager {
                Task {
                    _ = await locationManager.getCurrentLocation()
                }
            }
        }
    }
    
    /// Trigger snapshot updates when app enters foreground
    private func triggerSnapshotUpdateOnForeground() async {
        await MainActor.run {
            let registry = ServiceRegistry.shared
            
            // Only trigger if user has active schedule
            guard !UserPreferences.shared.schedule.repeatDays.isEmpty else {
                return
            }
            
            // Initialize SnapshotUpdateManager and trigger foreground update
            Task {
                await registry.snapshotUpdateManager.updateSnapshotsForUpcomingJobs(trigger: .appForeground)
            }
        }
    }
    
    /// Reconfigure audio session only if AudioPlayerManager is loaded
    private func reconfigureAudioSessionIfNeeded() async {
        let hasAudioPlayer = await MainActor.run {
            ServiceRegistry.shared.loadedServices.contains("AudioPlayerManager")
        }
        
        guard hasAudioPlayer else {
            await DebugLogger.shared.log("🔄 Media services reset - but AudioPlayerManager not loaded, skipping", level: .debug)
            return
        }
        
        // Only reconfigure if audio system is actually in use
        Self.audioConfigRetryCount = 0
        
        do {
            try await configureAudioSessionAsync()
            await DebugLogger.shared.log("✅ Audio session reconfigured after media services reset", level: .info)
        } catch {
            await DebugLogger.shared.logError(error, context: "Reconfiguring audio session after media services reset")
        }
    }
}

/// Minimal ContentView with lazy service loading
struct ContentView: View {
    // DEFERRED: HomeViewModel loads services only when needed
    @StateObject private var homeViewModel = HomeViewModel()
    
    var body: some View {
        HomeView(viewModel: homeViewModel)
            .onAppear {
                // Load core UI services only when view appears
                homeViewModel.onViewAppear()
            }
            .onDisappear {
                homeViewModel.onViewDisappear()
            }
    }
}

// MARK: - Minimal App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // REQUIRED: Register all background task handlers before app finishes launching
        registerBackgroundTasks()
        return true
    }
    
    /// Register background task handlers (required in didFinishLaunchingWithOptions)
    private func registerBackgroundTasks() {
        // Audio prefetch background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.bananaintelligence.DayStart.audio-prefetch", using: nil) { task in
            // Handler will be set up when AudioPrefetchManager is loaded
            if ServiceRegistry.shared.loadedServices.contains("AudioPrefetchManager") {
                ServiceRegistry.shared.audioPrefetchManager.handleBackgroundTask(task: task as! BGProcessingTask)
            } else {
                // Service not loaded yet, fail the task
                task.setTaskCompleted(success: false)
            }
        }
        
        // Snapshot update background task  
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.bananaintelligence.DayStart.snapshot-update", using: nil) { task in
            // Handler will be set up when SnapshotUpdateManager is loaded
            if ServiceRegistry.shared.loadedServices.contains("SnapshotUpdateManager") {
                ServiceRegistry.shared.snapshotUpdateManager.handleBackgroundTask(task: task as! BGProcessingTask)
            } else {
                // Service not loaded yet, fail the task
                task.setTaskCompleted(success: false)
            }
        }
        
        DebugLogger.shared.log("✅ Background task handlers registered in AppDelegate", level: .info)
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // LAZY: Only check if services are already loaded
        Task.detached {
            await MainActor.run {
                let registry = ServiceRegistry.shared
                if registry.loadedServices.contains("AudioPrefetchManager") {
                    Task {
                        await registry.audioPrefetchManager.checkForUpcomingDayStarts()
                    }
                }
            }
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // LAZY: Only clean cache if AudioCache is loaded
        Task {
            await MainActor.run {
                let registry = ServiceRegistry.shared
                if registry.loadedServices.contains("AudioCache") {
                    registry.audioCache.clearOldCache()
                }
            }
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // LAZY: Only cancel if services are loaded
        Task { @MainActor in
            let registry = ServiceRegistry.shared
            
            if registry.loadedServices.contains("AudioDownloader") {
                registry.audioDownloader.cancelAllDownloads()
            }
            
            if registry.loadedServices.contains("AudioPrefetchManager") {
                registry.audioPrefetchManager.cancelAllBackgroundTasks()
            }
        }
    }
}