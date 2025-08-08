import SwiftUI

struct DayStartGradientBackground: View {
    @State private var glowAnimation = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        ZStack {
            // Base background (white for light mode, black for dark mode)
            BananaTheme.ColorToken.background
                .ignoresSafeArea()
            
            // Enhanced Sunrise Glow - Linear Gradient
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.5, y: 0.3)
            )
            .blur(radius: 30)
            .ignoresSafeArea()
            .opacity(reduceMotion ? 0.9 : (glowAnimation ? 1.0 : 0.8))
            .animation(reduceMotion ? .none : .easeInOut(duration: 4).repeatForever(autoreverses: true), value: glowAnimation)
            
            // Radial sun gradient overlay
            RadialGradient(
                colors: sunColors,
                center: .top,
                startRadius: 20,
                endRadius: 200
            )
            .frame(height: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .blur(radius: 15)
        }
        .onAppear {
            if !reduceMotion {
                glowAnimation = true
            }
        }
    }
    
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            // Dark mode variant with reduced intensity
            return [
                Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.35),   // Reduced banana yellow
                Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.25),   // Reduced tangerine
                Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.20),   // Reduced coral
                Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.15),   // Reduced lavender
                Color.clear
            ]
        } else {
            // Light mode gradient
            return [
                Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.60),   // Soft banana yellow
                Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.50),   // Tangerine orange
                Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.40),   // Warm coral red
                Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.30),   // Soft lavender for depth
                Color.clear
            ]
        }
    }
    
    private var sunColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.20),
                Color.clear
            ]
        } else {
            return [
                Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.35),
                Color.clear
            ]
        }
    }
}

// MARK: - Preview
#if DEBUG
struct DayStartGradientBackground_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DayStartGradientBackground()
                .previewDisplayName("Light Mode")
                .preferredColorScheme(.light)
            
            DayStartGradientBackground()
                .previewDisplayName("Dark Mode")
                .preferredColorScheme(.dark)
        }
    }
}
#endif