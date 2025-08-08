import SwiftUI
import AVFoundation
import UserNotifications
import UIKit

@main
struct DayStartApp: App {
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showOnboarding = false
    
    init() {
        configureAudioSession()
        requestNotificationPermissions()
        configureNavigationAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userPreferences)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.effectiveColorScheme)
                .onAppear {
                    showOnboarding = !userPreferences.hasCompletedOnboarding
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView {
                        userPreferences.hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                }
        }
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permissions granted")
            }
        }
    }
    
    private func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(BananaTheme.ColorToken.accent)
    }
}

struct ContentView: View {
    @StateObject private var homeViewModel = HomeViewModel()
    
    var body: some View {
        HomeView(viewModel: homeViewModel)
    }
}