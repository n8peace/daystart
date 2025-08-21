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
            switch authManager.authState {
            case .unknown:
                // Show splash or loading
                SplashScreenView(
                    isAppReady: .constant(false),
                    onComplete: {
                        // Auth check will update the state
                    }
                )
                .onAppear {
                    Task {
                        await authManager.checkAuthStatus()
                    }
                }
                
            case .unauthenticated:
                // Check if onboarding is completed first
                if showOnboarding {
                    // Show onboarding (which includes auth at the end)
                    OnboardingView {
                        UserPreferences.shared.hasCompletedOnboarding = true
                        showOnboarding = false
                    }
                } else {
                    // Show main app - user can use locally without auth
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
                
            case .authenticated:
                // Show main app
                ContentView()
                    .environmentObject(UserPreferences.shared)
                    .environmentObject(themeManager)
                    .preferredColorScheme(themeManager.effectiveColorScheme)
                    .accentColor(BananaTheme.ColorToken.primary)
                    .id("theme-\(themeManager.effectiveColorScheme.hashValue)")
                    .onReceive(themeManager.$effectiveColorScheme) { colorScheme in
                        updateNavigationAppearance(for: colorScheme)
                    }
                    .fullScreenCover(isPresented: $showOnboarding) {
                        OnboardingView {
                            UserPreferences.shared.hasCompletedOnboarding = true
                            showOnboarding = false
                        }
                    }
            }
        }
    }
    
    // Update the SupabaseClient to use authenticated requests
    func updateSupabaseClientAuth() {
        // This will be called when auth state changes
        // Update all API calls to include JWT token
    }
}

// MARK: - Updated API Request Headers

extension SupabaseClient {
    
    // Replace the current createRequest method with this authenticated version:
    func createAuthenticatedRequest(for url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DayStart-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        // Get JWT token from AuthManager
        if let userId = AuthManager.shared.currentUserId {
            // TODO: Get actual JWT token from Supabase session
            // For now, still use anon key but prepare for JWT
            if let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String {
                request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            }
            
            // Add user ID to request headers (temporary until JWT is implemented)
            request.setValue(userId, forHTTPHeaderField: "x-user-id")
        } else {
            // Unauthenticated request - use anon key
            if let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String {
                request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        // Remove device ID header - no longer needed
        // x-client-info will be removed in favor of JWT user claims
        
        DebugLogger.shared.log("🔑 Auth headers set for \(method) request", level: DebugLogger.LogLevel.info)
        
        return request
    }
}