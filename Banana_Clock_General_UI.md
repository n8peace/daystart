## Banana Clock — General UI Design Spec

### Purpose
High-level UI spec for the Banana Clock app. Defines navigation, visual language, primary components (including the gradient background with a sun effect), and standard controls such as Edit/Done buttons. Optimized for SwiftUI implementation and easy sharing with design/engineering stakeholders.

### Platform & Baseline
- **Platform**: iOS (SwiftUI)
- **Design Units**: Points (pt)
- **Typography**: SF Pro Text / SF Pro Display
- **Iconography**: SF Symbols
- **Dark Mode**: Supported (with tuned gradient and contrast)
- **Accessibility**: Dynamic Type, VoiceOver labels, sufficient contrast

## Navigation

### Main Tab Bar
- **Tabs**:
  - **Wake**: Daily wake-up experience and summary.
  - **Alarms**: Create, view, and manage alarms.
  - **Timers**: Countdown timers.
  - **Stopwatch**: Start/stop/reset lap timer.
  - **World Clock**: Track time across cities.

- **Placement**: iOS standard bottom tab bar.
- **Behavior**:
  - Persist last-selected tab on app relaunch.
  - Badge counts are minimal; prefer in-tab indicators over tab badges.
  - Haptic tap feedback on selection (light).

### Navigation Bars
- **Title Style**: Large Title on primary screens; Inline Title on sub-screens.
- **Right Bar Button**: Contextual (e.g., Edit/Done, Add, Settings).
- **Left Bar Button**: Back or Close on sub-screens.

## Visual Language

### Color Tokens
- **bananaSunCore**: #FFD34E
- **bananaSunWarm**: #FFB36B
- **bananaSkyBlush**: #FF7AA2
- **bananaSkyDeep**: #6341FF
- **bananaCard**: System Background
- **bananaTextPrimary**: Label
- **bananaTextSecondary**: Secondary Label
- **bananaAccent**: #FFC857
- **bananaDestructive**: System Red

Provide semantic usage in code (e.g., `BananaTheme.Color.sun.core`).

### Typography Tokens
- **Display**: Large Title (34–40 pt)
- **Headline**: 17 pt, semibold
- **Body**: 15–17 pt, regular
- **Caption**: 13 pt

### Spacing
- **Base Unit**: 8 pt
- **Grid**: 8/16/24/32 pt stack; cards min 16 pt margins; inter-item spacing 8–12 pt

## Background Gradient with Sun Effect

### Overview
The background is a vertical gradient with a radial “sun” glow near the top center, evoking sunrise. It adapts to Dark Mode with adjusted contrast and deeper tones.

### Light Mode Gradient
- **Linear Gradient (backdrop)**: Top → Bottom
  - Stops: `bananaSunWarm` (0%), `bananaSkyBlush` (45%), `bananaSkyDeep` (100%)
- **Radial Sun (overlay)**:
  - Center: 50% x, 10% y
  - Inner color: `bananaSunCore` @ 1.0 alpha
  - Outer color: `bananaSunWarm` → transparent by ~65% radius
  - Blend: Add/SplusLighter or Normal with reduced alpha (0.35–0.55)
  - Radius: 320–480 pt on iPhone base; scale with device size

### Dark Mode Gradient
- **Linear Gradient**: `bananaSkyDeep` (top) → desaturated `bananaSkyBlush` (mid, -15% sat) → `#1A1446` (bottom)
- **Radial Sun**: `bananaSunCore` @ 0.35–0.45 alpha fading to transparent; slightly smaller radius for contrast control

### Motion (Optional, Low Power Friendly)
- Subtle vertical parallax (±8 pt) based on scroll offset.
- Breathing glow: 4–6s ease-in-out alpha oscillation (±0.05–0.1) respecting Reduce Motion.

### Layering Order
1. Linear gradient backdrop
2. Radial sun glow
3. Content layers (cards, lists, controls)
4. Optional foreground particles (disabled by default)

## Core Components

### Edit / Done Buttons
- **Placement**: Right side of navigation bar on list-based screens (e.g., Alarms).
- **States**:
  - Default: Shows **Edit** when not editing.
  - Editing: Shows **Done**; toggles list editing mode.
  - Disabled: Dimmed when list is empty or action not applicable.
- **Hit Target**: ≥ 44x44 pt
- **Typography**: 17 pt semibold
- **Behavior**:
  - Toggle a view model boolean `isEditing`.
  - While editing, list rows expose reordering and delete affordances.
  - Accessibility labels: "Edit list" / "Done editing"; traits update on toggle.

### Primary Button
- **Style**: Filled, rounded 12 pt corner radius
- **Height**: 48 pt
- **Color**: `bananaAccent` background; Label text color
- **Pressed**: Darken bg by ~7%; scale 0.98; light haptic
- **Disabled**: 35% alpha; no shadow

### Secondary Button
- **Style**: Outlined; 1 pt stroke using `bananaAccent` @ 60% alpha
- **Height**: 44 pt
- **Pressed**: Stroke strengthens to 100% alpha

### Destructive Button
- **Color**: System Red; label white/label depending on contrast
- **Usage**: Irreversible actions (delete alarm)

### Cards
- **Use**: Alarm rows, summary tiles
- **Layout**: 16 pt outer padding; 12 pt inner padding
- **Corner Radius**: 16 pt
- **Shadow**: y: 2 pt, blur: 8 pt, alpha: 0.08 (light mode only)
- **Content**: Title (semibold), subtitle, trailing toggles or time labels

### Lists
- **Style**: Inset grouped for settings; plain for alarms
- **Row Height**: 56–72 pt depending on density
- **Separators**: Hidden; use spacing and card backgrounds

### Toggles
- **Use**: Enable/disable alarm
- **States**: On/Off with haptic feedback
- **Accessibility**: Label describes alarm time and repeat pattern

### Audio Visualization (Optional)
- **Bars**: 8–16 minimalist bars reacting to amplitude
- **Color**: Derive from `bananaSunCore` → `bananaSkyBlush`
- **Performance**: Pause in background; respect Reduce Motion

## Screens

### Wake (Home)
- Hero greeting and next alarm time
- Gradient background with sun effect visible
- Primary CTA: Start/Preview Wake Sequence (if applicable)

### Alarms
- List of alarms as cards
- Edit/Done to reorder and delete
- Add button to create alarm

### Timers
- Large numeric control
- Presets (e.g., 1m, 5m, 10m)
- Start/Pause/Reset

### Stopwatch
- Elapsed time, Lap list
- Start/Stop, Lap, Reset

### World Clock
- City list with local times
- Add city flow

## States & Themes

### Empty States
- Encouraging illustration or sun glow without content
- Primary CTA to create first item (e.g., "Add Alarm")

### Loading
- Skeletons with 12 pt corner radius
- Progress indicators should not obstruct the sun glow

### Error
- Inline banner within lists
- Retry button with secondary emphasis

## Dark Mode & Accessibility
- Adjust gradient saturation and sun alpha for contrast
- Text adheres to system label colors
- Dynamic Type: Components expand vertically and reflow
- VoiceOver: Ensure labeled controls, ordered reading
- Reduce Motion: Disable glow breathing and parallax

## Interaction & Haptics
- Selection: light
- Success/Completion: medium
- Destructive: warning haptic

## Asset & Naming Conventions
- Colors: `BananaTheme.Color.*` (e.g., `sun.core`, `sky.blush`, `accent`)
- Icons: SF Symbols; custom assets prefixed `banana_`
- Images: PDF vector where possible; 1x universal

## Implementation Notes (SwiftUI)
- Background view composes the linear gradient + radial sun layer as a reusable `View` or `ViewModifier`.
- Use a `@State` or `@ObservedObject` for editing on list screens; toggle via Edit/Done.
- Avoid side effects in `View.body`; delegate to ViewModels for logic.
- Respect system theming and accessibility without manual overrides when possible.

## Example Measurements
- Navigation Bar Buttons: 44x44 pt min tap area
- Card: 16 pt outer margin, 16 pt corner radius
- Primary Button: 48 pt height, 16–20 pt horizontal padding
- Sun Radius: 360 pt baseline (scale with device)

## Deliverables & Hand-Off
- This document serves as the canonical UI reference.
- Engineers implement tokens and components; Designers review visual fidelity.
- Future changes: Update tokens and relevant sections; version changes in doc header.

---

Last updated: 2025-08-08
Owner: Banana Clock Team


