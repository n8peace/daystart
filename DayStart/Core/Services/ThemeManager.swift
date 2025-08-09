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
            // Properly update UserPreferences to trigger save
            var updatedSettings = UserPreferences.shared.settings
            updatedSettings.themePreference = themePreference
            UserPreferences.shared.settings = updatedSettings
            
            // Update effective color scheme
            updateEffectiveColorScheme()
        }
    }
    
    @Published private(set) var effectiveColorScheme: ColorScheme = .light
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load saved preference
        self.themePreference = UserPreferences.shared.settings.themePreference
        
        // Listen to system color scheme changes
        #if os(iOS)
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.updateEffectiveColorScheme()
            }
            .store(in: &cancellables)
        #endif
        
        // Also listen for trait collection changes if available
        NotificationCenter.default
            .publisher(for: NSNotification.Name("NSSystemColorsDidChangeNotification"))
            .sink { [weak self] _ in
                self?.updateEffectiveColorScheme()
            }
            .store(in: &cancellables)
        
        // Initial color scheme calculation
        updateEffectiveColorScheme()
    }
    
    private func updateEffectiveColorScheme() {
        let newColorScheme: ColorScheme
        
        switch themePreference {
        case .system:
            // Get system appearance - improved detection
            #if os(iOS)
            newColorScheme = UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
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
        
        if effectiveColorScheme != newColorScheme {
            effectiveColorScheme = newColorScheme
            DebugLogger.shared.logThemeChange(from: effectiveColorScheme == .dark ? "dark" : "light", to: newColorScheme == .dark ? "dark" : "light")
        }
    }
    
    func setTheme(_ preference: ThemePreference) {
        withAnimation(.easeInOut(duration: 0.3)) {
            themePreference = preference
        }
    }
}