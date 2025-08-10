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
                    Task {
                        await userPreferences.cleanupOldAudioFiles()
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
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Configure category and mode with fallback options
            try audioSession.setCategory(.playback, 
                                       mode: .spokenAudio, 
                                       options: [.allowBluetooth, .allowBluetoothA2DP])
            
            // Set preferred sample rate and buffer duration to prevent system lookups
            try audioSession.setPreferredSampleRate(44100.0)
            try audioSession.setPreferredIOBufferDuration(0.02)
            
            // Activate session with error handling for system resource conflicts
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            logger.log("✅ Audio session configured successfully", level: .info)
            
        } catch let error as NSError {
            // Handle specific audio session errors gracefully
            logger.log("⚠️ Audio session configuration failed: \(error.localizedDescription)", level: .warning)
            
            // Check for specific error codes we can handle
            if error.code == AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue {
                logger.log("⚠️ Cannot interrupt other audio apps", level: .warning)
            } else if error.domain == NSOSStatusErrorDomain {
                // Handle media services issues with OSStatus errors
                logger.log("🔄 Media services issue detected, attempting reconfiguration", level: .warning)
                // Retry configuration after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.configureAudioSession()
                }
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
}

struct ContentView: View {
    @StateObject private var homeViewModel = HomeViewModel()
    private let logger = DebugLogger.shared
    
    var body: some View {
        HomeView(viewModel: homeViewModel)
            .onAppear {
            }
    }
}