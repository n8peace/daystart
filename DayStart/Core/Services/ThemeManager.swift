import SwiftUI
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var themePreference: ThemePreference = .system {
        didSet {
            // Defer UserPreferences update to avoid publishing during view updates
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var updatedSettings = UserPreferences.shared.settings
                updatedSettings.themePreference = self.themePreference
                UserPreferences.shared.settings = updatedSettings
            }
            
            // Update effective color scheme
            updateEffectiveColorScheme()
        }
    }
    
    @Published private(set) var effectiveColorScheme: ColorScheme = .light
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load saved preference directly from UserDefaults to avoid triggering UserPreferences lazy loading
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let settings = try? JSONDecoder().decode(UserSettings.self, from: data) {
            self.themePreference = settings.themePreference
        } else {
            self.themePreference = .system // Default
        }
        
        // Set up real-time system appearance monitoring
        #if os(iOS)
        setupSystemAppearanceMonitoring()
        #endif
        
        // Initial color scheme calculation
        updateEffectiveColorScheme()
    }
    
    private func updateEffectiveColorScheme() {
        let newColorScheme: ColorScheme
        
        switch themePreference {
        case .system:
            // Get system appearance - use UIScreen.main for accurate system theme
            #if os(iOS)
            let systemStyle = UIScreen.main.traitCollection.userInterfaceStyle
            newColorScheme = systemStyle == .dark ? .dark : .light
            print("🎨 ThemeManager: System theme detection - UIScreen.main.traitCollection.userInterfaceStyle = \(systemStyle.rawValue) (\(systemStyle == .dark ? "dark" : "light"))")
            
            // Also log UITraitCollection.current for comparison
            let currentStyle = UITraitCollection.current.userInterfaceStyle
            if currentStyle != systemStyle {
                print("🎨 ThemeManager: Note - UITraitCollection.current (\(currentStyle.rawValue)) differs from UIScreen.main (\(systemStyle.rawValue))")
            }
            #elseif os(macOS)
            let appearance = NSApp.effectiveAppearance.name
            newColorScheme = (appearance == .darkAqua || appearance == .vibrantDark) ? .dark : .light
            #else
            newColorScheme = .light
            #endif
        case .light:
            newColorScheme = .light
        case .dark:
            newColorScheme = .dark
        }
        
        print("🎨 ThemeManager: updateEffectiveColorScheme() - preference: \(themePreference.displayName), newColorScheme: \(newColorScheme == .dark ? "dark" : "light"), currentEffectiveColorScheme: \(effectiveColorScheme == .dark ? "dark" : "light")")
        
        if effectiveColorScheme != newColorScheme {
            let oldColorScheme = effectiveColorScheme
            effectiveColorScheme = newColorScheme
            print("🎨 ThemeManager: Color scheme changed from \(oldColorScheme == .dark ? "dark" : "light") to \(newColorScheme == .dark ? "dark" : "light")")
            DebugLogger.shared.logThemeChange(from: oldColorScheme == .dark ? "dark" : "light", to: newColorScheme == .dark ? "dark" : "light")
        }
    }
    
    func setTheme(_ preference: ThemePreference) {
        print("🎨 ThemeManager: setTheme() called with preference: \(preference.displayName)")
        withAnimation(.easeInOut(duration: 0.3)) {
            themePreference = preference
        }
    }
    
    /// Force refresh the color scheme - useful when app returns from background
    func refreshColorScheme() {
        print("🎨 ThemeManager: Force refreshing color scheme")
        updateEffectiveColorScheme()
    }
    
    /// Get the current system color scheme
    var systemColorScheme: ColorScheme {
        #if os(iOS)
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        #else
        return .light
        #endif
    }
    
    #if os(iOS)
    private func setupSystemAppearanceMonitoring() {
        // Method 1: Monitor app lifecycle changes (existing fallback)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                print("🎨 ThemeManager: App became active, checking for appearance changes")
                self?.updateEffectiveColorScheme()
            }
            .store(in: &cancellables)
        
        // Method 2: Monitor scene-level trait collection changes
        NotificationCenter.default
            .publisher(for: UIScene.willEnterForegroundNotification)
            .sink { [weak self] _ in
                print("🎨 ThemeManager: Scene entering foreground, updating appearance")
                self?.updateEffectiveColorScheme()
            }
            .store(in: &cancellables)
        
        // Method 3: Use timer-based monitoring for real-time changes
        // This catches Control Center theme toggles while app is active
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .map { _ in UIScreen.main.traitCollection.userInterfaceStyle }
            .removeDuplicates()
            .sink { [weak self] userInterfaceStyle in
                guard let self = self else { return }
                // Only update if we're in system mode and the system appearance actually changed
                if self.themePreference == .system {
                    let newSystemScheme: ColorScheme = userInterfaceStyle == .dark ? .dark : .light
                    if self.effectiveColorScheme != newSystemScheme {
                        print("🎨 ThemeManager: Real-time system appearance change detected: \(userInterfaceStyle == .dark ? "dark" : "light")")
                        self.updateEffectiveColorScheme()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Method 4: Monitor specific system appearance notifications
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                // Force a check when returning from Control Center
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.updateEffectiveColorScheme()
                }
            }
            .store(in: &cancellables)
        
        print("🎨 ThemeManager: System appearance monitoring initialized")
    }
    #endif
}