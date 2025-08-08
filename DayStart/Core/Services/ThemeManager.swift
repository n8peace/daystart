import SwiftUI
import Combine

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var themePreference: ThemePreference = .system {
        didSet {
            UserPreferences.shared.settings.themePreference = themePreference
        }
    }
    
    @Published private(set) var effectiveColorScheme: ColorScheme = .light
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load saved preference
        self.themePreference = UserPreferences.shared.settings.themePreference
        
        // Listen to system color scheme changes
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
        switch themePreference {
        case .system:
            // Get system appearance
            #if os(iOS)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                effectiveColorScheme = window.traitCollection.userInterfaceStyle == .dark ? .dark : .light
            } else {
                effectiveColorScheme = .light
            }
            #elseif os(macOS)
            let appearance = NSApp.effectiveAppearance.name
            effectiveColorScheme = (appearance == .darkAqua || appearance == .vibrantDark) ? .dark : .light
            #endif
        case .light:
            effectiveColorScheme = .light
        case .dark:
            effectiveColorScheme = .dark
        }
    }
    
    func setTheme(_ preference: ThemePreference) {
        withAnimation(.easeInOut(duration: 0.3)) {
            themePreference = preference
            updateEffectiveColorScheme()
        }
    }
}