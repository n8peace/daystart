import SwiftUI

struct BananaTheme {
    enum ColorToken {
        // Primary colors with light/dark variants
        static let primary = Color.adaptive(light: Color(hex: 0xFFD23F), dark: Color(hex: 0xFFD23F))
        static let secondary = Color.adaptive(light: Color(hex: 0x8B4513), dark: Color(hex: 0xD2691E))
        
        // Background and text colors for light/dark mode
        static let background = Color.adaptive(light: .white, dark: .black)
        static let text = Color.adaptive(light: .black, dark: .white)
        static let card = Color.adaptive(light: Color(hex: 0xF5F5F5), dark: Color(hex: 0x1C1C1E))
        
        // Additional semantic colors
        static let accent = Color.adaptive(light: Color(hex: 0xFFC857), dark: Color(hex: 0xFFC857))
        static let destructive = Color.red
        static let warning = Color.orange
        static let success = Color.green
        
        // Gradient colors that adapt to theme
        static let gradientStart = Color.adaptive(light: Color(hex: 0xFFE59F), dark: Color(hex: 0xFFD23F))
        static let gradientEnd = Color.adaptive(light: Color(hex: 0xFFD23F), dark: Color(hex: 0xFFA500))
        
        // Shadow and border colors
        static let shadow = Color.adaptive(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.1))
        static let border = Color.adaptive(light: Color.gray.opacity(0.3), dark: Color.gray.opacity(0.5))
        
        // Content colors
        static let primaryText = text
        static let secondaryText = Color.adaptive(light: Color.gray, dark: Color.gray.opacity(0.8))
        static let tertiaryText = Color.adaptive(light: Color.gray.opacity(0.6), dark: Color.gray.opacity(0.6))
    }
    
    enum Typography {
        // Static fonts (non-adaptive)
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
        
        // Adaptive fonts that change weight based on light/dark mode
        static func largeTitle(colorScheme: ColorScheme) -> Font {
            Font.largeTitle.weight(colorScheme == .dark ? .heavy : .bold)
        }
        
        static func title(colorScheme: ColorScheme) -> Font {
            Font.title.weight(colorScheme == .dark ? .bold : .semibold)
        }
        
        static func title2(colorScheme: ColorScheme) -> Font {
            Font.title2.weight(colorScheme == .dark ? .semibold : .medium)
        }
        
        static func headline(colorScheme: ColorScheme) -> Font {
            Font.headline.weight(colorScheme == .dark ? .semibold : .medium)
        }
    }
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let round: CGFloat = 999
    }
    
    enum Shadow {
        static let sm = ShadowConfig(color: ColorToken.shadow, radius: 2, x: 0, y: 1)
        static let md = ShadowConfig(color: ColorToken.shadow, radius: 4, x: 0, y: 2)
        static let lg = ShadowConfig(color: ColorToken.shadow, radius: 8, x: 0, y: 4)
        static let xl = ShadowConfig(color: ColorToken.shadow, radius: 16, x: 0, y: 8)
    }
    
    struct ShadowConfig {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - Legacy Color Support (Hex-based)
extension BananaTheme {
    // These are the original hex colors, now used as fallbacks
    // or for specific use cases where hex is needed
    enum HexColors {
        static let bananaYellow: UInt32 = 0xFFD23F
        static let bananaBrown: UInt32 = 0x8B4513
        static let lightBackground: UInt32 = 0xFFFDF0
        static let darkBackground: UInt32 = 0x1A1A2E
        static let cardLight: UInt32 = 0xFFFFFF
        static let cardDark: UInt32 = 0x2D2D44
    }
}

// MARK: - Color Extensions
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    // Dynamic color that adapts to light/dark mode
    static func adaptive(light: Color, dark: Color) -> Color {
        return Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
    
    // Helper for creating colors from hex with light/dark variants
    static func adaptiveHex(light: UInt32, dark: UInt32, alpha: Double = 1.0) -> Color {
        return adaptive(
            light: Color(hex: light, alpha: alpha),
            dark: Color(hex: dark, alpha: alpha)
        )
    }
}

// MARK: - Gradient Definitions
extension BananaTheme {
    enum Gradients {
        static let sunrise = LinearGradient(
            colors: [
                ColorToken.gradientStart,
                ColorToken.gradientEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let sunriseReversed = LinearGradient(
            colors: [
                ColorToken.gradientEnd,
                ColorToken.gradientStart
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let card = LinearGradient(
            colors: [
                ColorToken.card,
                ColorToken.card.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - View Modifiers
extension View {
    func bananaCardStyle() -> some View {
        self
            .background(BananaTheme.ColorToken.card)
            .cornerRadius(BananaTheme.CornerRadius.md)
            .shadow(
                color: BananaTheme.ColorToken.shadow,
                radius: BananaTheme.Shadow.md.radius,
                x: BananaTheme.Shadow.md.x,
                y: BananaTheme.Shadow.md.y
            )
    }
    
    func bananaPrimaryButton() -> some View {
        self
            .foregroundColor(Color.adaptive(light: .white, dark: .black))
            .padding(.horizontal, BananaTheme.Spacing.lg)
            .padding(.vertical, BananaTheme.Spacing.md)
            .background(BananaTheme.ColorToken.primary)
            .cornerRadius(BananaTheme.CornerRadius.md)
            .shadow(
                color: BananaTheme.ColorToken.shadow,
                radius: BananaTheme.Shadow.sm.radius,
                x: BananaTheme.Shadow.sm.x,
                y: BananaTheme.Shadow.sm.y
            )
    }
    
    func bananaSecondaryButton() -> some View {
        self
            .foregroundColor(BananaTheme.ColorToken.primary)
            .padding(.horizontal, BananaTheme.Spacing.lg)
            .padding(.vertical, BananaTheme.Spacing.md)
            .background(BananaTheme.ColorToken.card)
            .cornerRadius(BananaTheme.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.md)
                    .stroke(BananaTheme.ColorToken.primary, lineWidth: 1)
            )
    }
    
    func bananaBackground() -> some View {
        self.background(BananaTheme.ColorToken.background)
    }
    
    func adaptiveFontWeight(light: Font.Weight = .regular, dark: Font.Weight = .medium) -> some View {
        self.modifier(AdaptiveFontWeightModifier(lightWeight: light, darkWeight: dark))
    }
    
    func adaptiveFont(_ fontProvider: @escaping (ColorScheme) -> Font) -> some View {
        self.modifier(AdaptiveFontModifier(fontProvider: fontProvider))
    }
}

// MARK: - Custom View Modifiers
struct AdaptiveFontWeightModifier: ViewModifier {
    let lightWeight: Font.Weight
    let darkWeight: Font.Weight
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content.fontWeight(colorScheme == .dark ? darkWeight : lightWeight)
    }
}

struct AdaptiveFontModifier: ViewModifier {
    let fontProvider: (ColorScheme) -> Font
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content.font(fontProvider(colorScheme))
    }
}

// MARK: - Theme-aware Components
struct BananaCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .bananaCardStyle()
    }
}

struct BananaPrimaryButton<Content: View>: View {
    let action: () -> Void
    let content: Content
    
    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }
    
    var body: some View {
        Button(action: action) {
            content
                .bananaPrimaryButton()
        }
    }
}