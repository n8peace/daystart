# Banana Clock — Background Gradient Reference

## Overview
Complete reference for the gradient background system used throughout Banana Clock. This includes the sunrise gradient effect, radial sun glow, breathing animations, and interactive golden glow effects.

## Design Specifications

### Color Palette
- **Banana Yellow**: `Color(red: 1.0, green: 0.9, blue: 0.3)` - Core sun color
- **Tangerine Orange**: `Color(red: 1.0, green: 0.6, blue: 0.1)` - Warm transition
- **Coral Red**: `Color(red: 1.0, green: 0.4, blue: 0.3)` - Mid-gradient warmth
- **Soft Lavender**: `Color(red: 0.8, green: 0.4, blue: 0.8)` - Depth and contrast
- **Base**: `Color.black` - Foundation layer

### Layout Structure
1. **Foundation Layer**: Black background (`Color.black.ignoresSafeArea()`)
2. **Linear Gradient**: Diagonal sunrise effect (top-leading to mid-center)
3. **Radial Sun**: Circular glow overlay positioned at top-center
4. **Content Layer**: UI elements on top of gradients

### Animation Specifications
- **Breathing Cycle**: 4-second ease-in-out opacity animation (70% ↔ 100%)
- **Golden Glow**: 0.8s fade-in, 1.2s pulse (2 cycles), 0.8s fade-out
- **Parallax**: Optional scroll-based offset (±8pt vertical displacement)

## Implementation Code

### 1. Basic Gradient Background

```swift
struct BananaGradientBackground: View {
    @State private var glowAnimation = false
    
    var body: some View {
        ZStack {
            // Base black background (foundation layer)
            Color.black.ignoresSafeArea()
            
            // Enhanced Sunrise Glow - Linear Gradient
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.60),   // Soft banana yellow
                    Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.50),   // Tangerine orange
                    Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.40),   // Warm coral red
                    Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.30),   // Soft lavender for depth
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.5, y: 0.3)
            )
            .blur(radius: 40)
            .ignoresSafeArea()
            .blendMode(.screen)
            .opacity(glowAnimation ? 1.0 : 0.70)
            .animation(.easeInOut(duration: 4), value: glowAnimation)
            
            // Radial sun gradient overlay
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.35),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 200
            )
            .frame(height: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .blur(radius: 20)
            .blendMode(.screen)
        }
        .onAppear {
            // Start the breathing animation
            glowAnimation = true
        }
    }
}
```

### 2. Golden Glow Modifier (Interactive Elements)

```swift
struct GoldenGlowModifier: ViewModifier {
    let isActive: Bool
    @State private var glowOpacity: Double = 0.0
    
    func body(content: Content) -> some View {
        content
            .background {
                if isActive {
                    goldenGlowBackground
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    startGlowAnimation()
                } else {
                    stopGlowAnimation()
                }
            }
    }
    
    private var goldenGlowBackground: some View {
        RoundedRectangle(cornerRadius: BananaTheme.Layout.cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.yellow.opacity(0.3),
                        Color.orange.opacity(0.2),
                        Color.yellow.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(glowOpacity)
            .blur(radius: 2)
    }
    
    private func startGlowAnimation() {
        // Reset to ensure clean start
        glowOpacity = 0.0
        
        // Animate in with gentle pulse
        withAnimation(.easeInOut(duration: 0.8)) {
            glowOpacity = 1.0
        }
        
        // Start pulsing animation
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatCount(2, autoreverses: true)
        ) {
            glowOpacity = 0.6
        }
        
        // Fade out after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.8)) {
                glowOpacity = 0.0
            }
        }
    }
    
    private func stopGlowAnimation() {
        withAnimation(.easeOut(duration: 0.5)) {
            glowOpacity = 0.0
        }
    }
}

// Usage extension
extension View {
    func goldenGlow(isActive: Bool) -> some View {
        modifier(GoldenGlowModifier(isActive: isActive))
    }
}
```

### 3. Parallax-Enhanced Background (Optional)

```swift
struct ParallaxGradientBackground: View {
    let scrollOffset: CGFloat
    @State private var glowAnimation = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Linear gradient with parallax
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.60),
                    Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.50),
                    Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.40),
                    Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.30),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.5, y: 0.3)
            )
            .blur(radius: 40)
            .ignoresSafeArea()
            .blendMode(.screen)
            .offset(y: scrollOffset * 0.3) // Parallax effect
            .opacity(glowAnimation ? 1.0 : 0.70)
            .animation(.easeInOut(duration: 4), value: glowAnimation)
            
            // Radial sun with stronger parallax
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.35),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 200
            )
            .frame(height: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .blur(radius: 20)
            .blendMode(.screen)
            .offset(y: scrollOffset * 0.5) // Stronger parallax for sun
        }
        .onAppear {
            glowAnimation = true
        }
    }
}
```

### 4. Accessibility-Aware Implementation

```swift
struct AccessibleGradientBackground: View {
    @State private var glowAnimation = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.60),
                    Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.50),
                    Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.40),
                    Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.30),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.5, y: 0.3)
            )
            .blur(radius: 40)
            .ignoresSafeArea()
            .blendMode(.screen)
            .opacity(reduceMotion ? 0.85 : (glowAnimation ? 1.0 : 0.70))
            .animation(reduceMotion ? .none : .easeInOut(duration: 4), value: glowAnimation)
            
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.35),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 200
            )
            .frame(height: 300)
            .frame(maxHeight: .infinity, alignment: .top)
            .blur(radius: 20)
            .blendMode(.screen)
        }
        .onAppear {
            if !reduceMotion {
                glowAnimation = true
            }
        }
    }
}
```

## Usage Examples

### Basic Implementation in a View

```swift
struct MyView: View {
    var body: some View {
        ZStack {
            BananaGradientBackground()
            
            // Your content here
            VStack {
                Text("Hello World")
                    .foregroundColor(.white)
            }
        }
    }
}
```

### With Golden Glow Effect

```swift
struct InteractiveView: View {
    @State private var showGlow = false
    
    var body: some View {
        ZStack {
            BananaGradientBackground()
            
            Button("Tap me") {
                showGlow = true
            }
            .goldenGlow(isActive: showGlow)
        }
    }
}
```

### With Parallax in ScrollView

```swift
struct ScrollableView: View {
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            ParallaxGradientBackground(scrollOffset: scrollOffset)
            
            ScrollView {
                // Content with scroll tracking
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                }
                .frame(height: 0)
                
                // Your scrollable content here
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

## Technical Details

### Performance Considerations
- Uses hardware-accelerated blur effects
- Blend modes leverage GPU compositing
- Animation state is minimal (@State with Bool/Double)
- Parallax calculations are lightweight (simple multiplication)

### Blend Mode Explanation
- `.screen`: Inverts colors, multiplies, then inverts again - creates additive light effect
- Result: Bright areas become brighter, dark areas stay dark
- Perfect for sunrise/glow effects

### Animation Timing
- **Breathing**: 4-second cycle for calm, meditative feel
- **Golden Glow**: Quick feedback (0.8s) with attention-grabbing pulse
- **Parallax**: Real-time response to scroll (no delay)

### Memory Usage
- Gradients are rendered once and cached by SwiftUI
- Animation only changes opacity/offset values
- No retained timers or complex state

## Dark Mode Adaptations

### Adjusted Color Values for Dark Mode
```swift
// Dark mode variant with reduced intensity
private var darkModeColors: [Color] {
    [
        Color(red: 1.0, green: 0.9, blue: 0.3).opacity(0.35),   // Reduced banana yellow
        Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.25),   // Reduced tangerine
        Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.20),   // Reduced coral
        Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.15),   // Reduced lavender
        Color.clear
    ]
}
```

## Current Implementation Status
This gradient system is currently implemented across all main views:
- `main-tab-view.swift` (TabView container)
- `alarms-view.swift` (Alarms screen)
- `timers-view.swift` (Timers screen)
- `stopwatch-view.swift` (Stopwatch screen)
- `world-clock-view.swift` (World Clock screen)
- `WakeUpView.swift` (Wake Up screen)

Each view uses identical gradient code for consistency, with the breathing animation controlled by a local `@State private var glowAnimation = false` that toggles to `true` on `.onAppear`.

---

**Last Updated**: 2025-01-08  
**Version**: 1.0  
**Owner**: Banana Clock Team
