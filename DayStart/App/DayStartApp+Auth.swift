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
                    logger.log("🔄 Auth: Showing splash, checking purchase status", level: .info)
                    Task {
                        await purchaseManager.checkPurchaseStatus()
                    }
                }
                
            case .notPurchased:
                // Show onboarding flow (includes paywall)
                OnboardingView {
                    logger.log("🎓 Auth: Onboarding completion callback - setting hasCompletedOnboarding = true", level: .info)
                    userPreferences.hasCompletedOnboarding = true
                }
                .onAppear {
                    logger.log("🆓 Auth: No purchase found, showing onboarding", level: .info)
                }
                
            case .purchased:
                // Show main app for paid users or onboarding if needed
                if !userPreferences.hasCompletedOnboarding {
                    // First time setup after purchase
                    OnboardingView {
                        logger.log("🎓 Auth: Post-purchase onboarding completion - setting hasCompletedOnboarding = true", level: .info)
                        userPreferences.hasCompletedOnboarding = true
                    }
                    .onAppear {
                        logger.log("💰 Auth: Purchase found, onboarding incomplete - showing onboarding", level: .info)
                    }
                } else {
                    // Regular app usage
                    ContentView()
                        .environmentObject(userPreferences)
                        .environmentObject(themeManager)
                        .preferredColorScheme(themeManager.effectiveColorScheme)
                        .accentColor(BananaTheme.ColorToken.primary)
                        .id("theme-\(themeManager.effectiveColorScheme.hashValue)")
                        .onReceive(themeManager.$effectiveColorScheme) { colorScheme in
                            updateNavigationAppearance(for: colorScheme)
                        }
                        .onAppear {
                            logger.log("✅ Auth: Purchase found, onboarding complete - showing main app (hasCompletedOnboarding: \(userPreferences.hasCompletedOnboarding))", level: .info)
                        }
                }
            }
        }
        .onReceive(userPreferences.$hasCompletedOnboarding) { hasCompleted in
            logger.log("🔄 Auth: Received hasCompletedOnboarding change: \(hasCompleted), purchaseState: \(purchaseManager.purchaseState)", level: .info)
        }
        .onReceive(purchaseManager.$purchaseState) { purchaseState in
            logger.log("🔄 Auth: Received purchaseState change: \(purchaseState), hasCompletedOnboarding: \(userPreferences.hasCompletedOnboarding)", level: .info)
        }
    }
    
}