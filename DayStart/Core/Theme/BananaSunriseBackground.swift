import SwiftUI

struct BananaSunriseBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base background
                baseBackground
                
                // Animated gradient overlay
                AnimatedGradientView()
                    .opacity(0.8)
                
                // Subtle noise texture overlay
                NoiseTextureView()
                    .opacity(0.05)
                    .blendMode(.overlay)
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: themeManager.effectiveColorScheme)
        }
    }
    
    @ViewBuilder
    private var baseBackground: some View {
        switch themeManager.effectiveColorScheme {
        case .light:
            lightModeBackground
        case .dark:
            darkModeBackground
        @unknown default:
            lightModeBackground
        }
    }
    
    private var lightModeBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: 0xFFE5B4), // Soft peach
                Color(hex: 0xFFF4E6), // Warm white
                Color(hex: 0xFFFDF0)  // Ivory
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var darkModeBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: 0x1A1A2E), // Deep navy
                Color(hex: 0x16213E), // Darker blue
                Color(hex: 0x0F0F1E)  // Almost black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AnimatedGradientView: View {
    @State private var animateGradient = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: animateGradient ? .topLeading : .bottomTrailing,
            endPoint: animateGradient ? .bottomTrailing : .topLeading
        )
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 3.0)
                    .repeatForever(autoreverses: true)
            ) {
                animateGradient.toggle()
            }
        }
    }
    
    private var gradientColors: [Color] {
        switch colorScheme {
        case .light:
            return [
                Color(hex: 0xFFD23F, alpha: 0.3), // Banana yellow
                Color(hex: 0xFFA500, alpha: 0.2), // Orange
                Color.clear
            ]
        case .dark:
            return [
                Color(hex: 0x4A5568, alpha: 0.4), // Muted blue-gray
                Color(hex: 0x2D3748, alpha: 0.3), // Darker blue-gray
                Color.clear
            ]
        @unknown default:
            return [
                Color(hex: 0xFFD23F, alpha: 0.3),
                Color(hex: 0xFFA500, alpha: 0.2),
                Color.clear
            ]
        }
    }
}

struct NoiseTextureView: View {
    var body: some View {
        Canvas { context, size in
            var random = Random(seed: 42)
            
            for _ in 0..<1000 {
                let x = random.nextDouble() * size.width
                let y = random.nextDouble() * size.height
                let opacity = random.nextDouble() * 0.1
                
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }
}

// Simple random number generator for consistent noise
struct Random {
    private var seed: UInt64
    
    init(seed: UInt64) {
        self.seed = seed
    }
    
    mutating func nextDouble() -> Double {
        seed = seed &* 1103515245 &+ 12345
        return Double(seed % 1000000) / 1000000.0
    }
}

// MARK: - Gradient Background Variants
struct HomeGradientBackground: View {
    var body: some View {
        BananaSunriseBackground()
    }
}

struct OnboardingGradientBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base color
            (colorScheme == .dark ? Color(hex: 0x1A1A2E) : Color(hex: 0xFFFDF0))
            
            // Overlay gradient
            LinearGradient(
                colors: [
                    colorScheme == .dark 
                        ? Color(hex: 0x2D3748, alpha: 0.6)
                        : Color(hex: 0xFFD23F, alpha: 0.1),
                    Color.clear,
                    colorScheme == .dark
                        ? Color(hex: 0x4A5568, alpha: 0.4)
                        : Color(hex: 0xFFA500, alpha: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: colorScheme)
    }
}

// MARK: - Preview Helpers
#if DEBUG
struct BananaSunriseBackground_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BananaSunriseBackground()
                .previewDisplayName("Light Mode")
                .preferredColorScheme(.light)
            
            BananaSunriseBackground()
                .previewDisplayName("Dark Mode")
                .preferredColorScheme(.dark)
        }
    }
}

struct HomeGradientBackground_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HomeGradientBackground()
                .previewDisplayName("Home - Light")
                .preferredColorScheme(.light)
            
            HomeGradientBackground()
                .previewDisplayName("Home - Dark")
                .preferredColorScheme(.dark)
        }
    }
}
#endif