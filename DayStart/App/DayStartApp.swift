import SwiftUI
import AVFoundation
import UserNotifications
import UIKit
import Combine

@main
struct DayStartApp: App {
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showOnboarding = false
    
    private let logger = DebugLogger.shared
    
    init() {
        logger.log("🚀 DayStart app initializing", level: .info)
        logger.logMemoryUsage()
        
        configureAudioSession()
        requestNotificationPermissions()
        
        logger.log("✅ App initialization complete", level: .info)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userPreferences)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.effectiveColorScheme)
                .accentColor(BananaTheme.ColorToken.primary)
                .onReceive(themeManager.$effectiveColorScheme) { colorScheme in
                    configureNavigationAppearance(for: colorScheme)
                }
                .onAppear {
                    logger.log("📱 App appeared - checking onboarding status", level: .info)
                    
                    let shouldShowOnboarding = !userPreferences.hasCompletedOnboarding
                    showOnboarding = shouldShowOnboarding
                    
                    logger.logUserAction("App launch", details: [
                        "hasCompletedOnboarding": userPreferences.hasCompletedOnboarding,
                        "showingOnboarding": shouldShowOnboarding,
                        "historyCount": userPreferences.history.count
                    ])
                    
                    // Clean up old audio files on app start
                    DispatchQueue.global(qos: .utility).async {
                        logger.log("🧹 Starting audio file cleanup", level: .debug)
                        userPreferences.cleanupOldAudioFiles()
                        logger.log("✅ Audio file cleanup complete", level: .debug)
                    }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView {
                        logger.logUserAction("Onboarding completed")
                        userPreferences.hasCompletedOnboarding = true
                        showOnboarding = false
                        logger.log("🎓 User completed onboarding - transitioning to main app", level: .info)
                    }
                }
        }
    }
    
    private func configureAudioSession() {
        logger.log("🔊 Configuring audio session", level: .debug)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            logger.log("✅ Audio session configured successfully", level: .info)
        } catch {
            logger.logError(error, context: "Failed to configure audio session")
        }
    }
    
    private func requestNotificationPermissions() {
        logger.log("🔔 Requesting notification permissions", level: .debug)
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
}

struct ContentView: View {
    @StateObject private var homeViewModel = HomeViewModel()
    private let logger = DebugLogger.shared
    
    var body: some View {
        HomeView(viewModel: homeViewModel)
            .onAppear {
                logger.log("🏠 Main content view appeared", level: .debug)
            }
    }
}