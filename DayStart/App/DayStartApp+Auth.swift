import SwiftUI

// Extension to add authentication flow to DayStartApp
// This file contains the authentication integration code that will be merged
// into DayStartApp.swift once the Supabase SDK is added

extension DayStartApp {
    
    // Properties are now added to DayStartApp.swift:
    // @StateObject private var authManager = AuthManager.shared ✅
    // @State private var showAuthentication = false ✅
    
    // Replace the ContentView() in body with this:
    func authenticatedContentView() -> some View {
        Group {
            switch purchaseManager.purchaseState {
            case .unknown:
                // Show splash or loading
                SplashScreenView(
                    isAppReady: .constant(false),
                    onComplete: {
                        // Purchase check will update the state
                    }
                )
                .onAppear {
                    Task {
                        await purchaseManager.checkPurchaseStatus()
                    }
                }
                
            case .notPurchased:
                // Show onboarding flow (includes paywall)
                OnboardingView {
                    UserPreferences.shared.hasCompletedOnboarding = true
                    showOnboarding = false
                }
                
            case .purchased:
                // Show main app for paid users
                if showOnboarding {
                    // First time setup after purchase
                    OnboardingView {
                        UserPreferences.shared.hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                } else {
                    // Regular app usage
                    ContentView()
                        .environmentObject(UserPreferences.shared)
                        .environmentObject(themeManager)
                        .preferredColorScheme(themeManager.effectiveColorScheme)
                        .accentColor(BananaTheme.ColorToken.primary)
                        .id("theme-\(themeManager.effectiveColorScheme.hashValue)")
                        .onReceive(themeManager.$effectiveColorScheme) { colorScheme in
                            updateNavigationAppearance(for: colorScheme)
                        }
                }
            }
        }
    }
    
}