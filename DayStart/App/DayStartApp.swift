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
    
    init() {
        configureAudioSession()
        requestNotificationPermissions()
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
    
    private func configureNavigationAppearance(for colorScheme: ColorScheme? = nil) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        // Use adaptive colors based on current color scheme
        let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
        appearance.titleTextAttributes = [.foregroundColor: textColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
        
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