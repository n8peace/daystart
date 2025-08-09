# 🍌 Banana Intelligence Theme

## Overview

The Banana Intelligence Theme is DayStart's signature design system that combines warmth, optimism, and intelligence. Inspired by the golden hues of sunrise and the friendly appeal of bananas, this theme creates an inviting morning experience that feels both sophisticated and approachable.

## Design Philosophy

### Core Principles
- **Warm & Inviting**: Colors that energize without overwhelming
- **Intelligent Adaptation**: Seamless light/dark mode transitions
- **Morning-Optimized**: High contrast for sleepy eyes
- **Accessibility First**: WCAG AA compliant color combinations

## Color System

### Primary Palette

#### Banana Yellow (#FFD23F)
- **Usage**: Primary actions, highlights, brand identity
- **Personality**: Energetic, optimistic, intelligent
- **Light/Dark**: Remains consistent across themes

#### Banana Brown (#8B4513 / #D2691E)
- **Usage**: Secondary elements, grounding accents
- **Light Mode**: Deep brown (#8B4513)
- **Dark Mode**: Lighter chocolate (#D2691E)
- **Personality**: Stable, trustworthy, natural

### Semantic Colors

```swift
// Success States
success: Color.green

// Warning States  
warning: Color.orange
accent: #FFC857 (golden banana)

// Destructive Actions
destructive: Color.red

// Shadows & Borders
shadow: 10% opacity (adapts to theme)
border: 30-50% gray (adapts to theme)
```

### Background & Surface Colors

#### Light Mode
- **Background**: Pure white (#FFFFFF)
- **Card Surface**: Light gray (#F5F5F5)
- **Text Primary**: Black (#000000)
- **Text Secondary**: Gray (100%)
- **Text Tertiary**: Gray (60%)

#### Dark Mode
- **Background**: Pure black (#000000)
- **Card Surface**: Dark gray (#1C1C1E)
- **Text Primary**: White (#FFFFFF)
- **Text Secondary**: Gray (80%)
- **Text Tertiary**: Gray (60%)

### Gradient System

#### Sunrise Gradient
- **Start**: #FFE59F (light) / #FFD23F (dark)
- **End**: #FFD23F (light) / #FFA500 (dark)
- **Direction**: Top-leading to bottom-trailing
- **Usage**: Backgrounds, hero sections

## Typography

### Adaptive Font System
Fonts automatically adjust weight based on theme to maintain readability:

```swift
// Title Fonts (Adaptive Weight)
largeTitle: bold (light) → heavy (dark)
title: semibold (light) → bold (dark)
title2: medium (light) → semibold (dark)
headline: medium (light) → semibold (dark)

// Body Fonts (Static)
body: Font.body
callout: Font.callout
subheadline: Font.subheadline
footnote: Font.footnote
caption: Font.caption
caption2: Font.caption2
```

### Usage Guidelines
- **Headers**: Use adaptive fonts for better contrast
- **Body Text**: Static weights for consistent reading
- **Buttons**: Headline or body with medium weight
- **Captions**: Use secondary/tertiary text colors

## Spacing System

```swift
xs: 4pt   // Tight groupings
sm: 8pt   // Related elements
md: 16pt  // Standard spacing
lg: 24pt  // Section breaks
xl: 32pt  // Major divisions
xxl: 48pt // Hero spacing
```

## Component Patterns

### Cards
```swift
.bananaCardStyle()
- Background: ColorToken.card
- Corner Radius: 12pt
- Shadow: medium (4pt blur)
```

### Buttons

#### Primary Button
```swift
.bananaPrimaryButton()
- Background: Banana Yellow
- Text: White (light) / Black (dark)
- Padding: 24pt horizontal, 16pt vertical
- Corner Radius: 12pt
```

#### Secondary Button
```swift
.bananaSecondaryButton()
- Background: Card color
- Border: 1pt Banana Yellow
- Text: Banana Yellow
```

### Form Elements
- **Text Fields**: Rounded border style
- **Toggles**: Banana Yellow tint
- **Pickers**: Banana Yellow accent

## Interaction States

### Touch Feedback
- **Buttons**: Scale 0.95 on press
- **Cards**: Subtle shadow increase
- **List Items**: Background highlight

### Loading States
- **Progress**: Banana Yellow
- **Skeleton**: Card color with shimmer

### Validation
- **Success**: Green checkmark
- **Error**: Red with description
- **Loading**: Progress indicator

## Implementation Examples

### Basic Theme Usage
```swift
Text("Good Morning")
    .foregroundColor(BananaTheme.ColorToken.text)
    .adaptiveFont(BananaTheme.Typography.title)
```

### Card Component
```swift
BananaCard {
    VStack {
        Text("Your Day Starts Now")
        // Card content
    }
}
```

### Gradient Background
```swift
DayStartGradientBackground()
    .opacity(0.15) // Subtle morning glow
```

## Accessibility

### Color Contrast
- Primary text on background: 21:1 ratio
- Yellow on white: 4.5:1 ratio (AA compliant)
- All interactive elements: Minimum 44pt touch targets

### Dynamic Type
- All text respects user size preferences
- Layouts adapt to larger text sizes
- Icons scale proportionally

### VoiceOver
- All interactive elements labeled
- Grouped content for efficient navigation
- State changes announced

## Animation Guidelines

### Timing
- **Micro-animations**: 0.2s ease-in-out
- **Transitions**: 0.3s ease-in-out
- **Complex animations**: 0.5s spring

### Motion Principles
- Subtle and purposeful
- Respect reduced motion settings
- Guide user attention
- Celebrate achievements

## Best Practices

### Do's
✅ Use semantic colors for their intended purpose
✅ Maintain consistent spacing
✅ Test in both light and dark modes
✅ Ensure touch targets are 44pt minimum
✅ Use adaptive fonts for headers

### Don'ts
❌ Override theme colors with hardcoded values
❌ Mix spacing units arbitrarily
❌ Use pure black/white without theme tokens
❌ Ignore accessibility guidelines
❌ Create custom shadows without using theme

## Future Enhancements

### Planned Features
- High contrast mode support
- Additional gradient presets
- Seasonal theme variations
- Custom font support
- Motion design tokens

### Theme Extensions
- Widget-specific styles
- Watch app adaptations
- Notification styling
- App icon variations

---

*The Banana Intelligence Theme embodies the spirit of DayStart: intelligent, warm, and ready to make every morning brighter.* 🌅