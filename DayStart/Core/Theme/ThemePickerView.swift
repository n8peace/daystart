import SwiftUI

struct ThemePickerView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var systemColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: BananaTheme.Spacing.md) {
            HStack {
                Text("Appearance")
                    .adaptiveFont(BananaTheme.Typography.headline)
                    .foregroundColor(BananaTheme.ColorToken.primaryText)
                
                Spacer()
            }
            
            VStack(spacing: BananaTheme.Spacing.sm) {
                ForEach(ThemePreference.allCases, id: \.self) { preference in
                    ThemeOptionRow(
                        preference: preference,
                        isSelected: themeManager.themePreference == preference
                    ) {
                        themeManager.setTheme(preference)
                        DebugLogger.shared.logThemeChange(
                            from: themeManager.themePreference.displayName,
                            to: preference.displayName
                        )
                    }
                }
            }
        }
        .padding(BananaTheme.Spacing.md)
        .bananaCardStyle()
    }
}

struct ThemeOptionRow: View {
    let preference: ThemePreference
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: BananaTheme.Spacing.md) {
                // Theme preview icon
                ThemePreviewIcon(preference: preference)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preference.displayName)
                        .font(BananaTheme.Typography.body)
                        .foregroundColor(BananaTheme.ColorToken.primaryText)
                    
                    Text(themeDescription(for: preference))
                        .font(BananaTheme.Typography.caption)
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(BananaTheme.ColorToken.primary)
                        .font(.title2)
                }
            }
            .padding(.vertical, BananaTheme.Spacing.sm)
            .padding(.horizontal, BananaTheme.Spacing.md)
            .background(
                isSelected ? BananaTheme.ColorToken.primary.opacity(0.1) : Color.clear
            )
            .cornerRadius(BananaTheme.CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.sm)
                    .stroke(
                        isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func themeDescription(for preference: ThemePreference) -> String {
        switch preference {
        case .system:
            return "Matches your device settings"
        case .light:
            return "Always use light appearance"
        case .dark:
            return "Always use dark appearance"
        }
    }
}

struct ThemePreviewIcon: View {
    let preference: ThemePreference
    @Environment(\.colorScheme) var systemColorScheme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(previewBackgroundColor)
                .frame(width: 32, height: 32)
            
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(previewContentColor)
                    .frame(width: 16, height: 2)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(previewContentColor.opacity(0.7))
                    .frame(width: 12, height: 2)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(previewContentColor.opacity(0.5))
                    .frame(width: 14, height: 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var previewBackgroundColor: Color {
        switch preference {
        case .system:
            return systemColorScheme == .dark ? .black : .white
        case .light:
            return .white
        case .dark:
            return .black
        }
    }
    
    private var previewContentColor: Color {
        switch preference {
        case .system:
            return systemColorScheme == .dark ? Color.white : Color.black
        case .light:
            return Color.black
        case .dark:
            return Color.white
        }
    }
}

// MARK: - Compact Theme Picker
struct CompactThemePickerView: View {
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        HStack(spacing: BananaTheme.Spacing.sm) {
            ForEach(ThemePreference.allCases, id: \.self) { preference in
                Button(action: {
                    themeManager.setTheme(preference)
                }) {
                    VStack(spacing: 4) {
                        ThemePreviewIcon(preference: preference)
                        
                        Text(compactLabel(for: preference))
                            .font(.caption2)
                            .foregroundColor(
                                themeManager.themePreference == preference 
                                    ? BananaTheme.ColorToken.primary 
                                    : BananaTheme.ColorToken.secondaryText
                            )
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func compactLabel(for preference: ThemePreference) -> String {
        switch preference {
        case .system:
            return "Auto"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

// MARK: - Theme Toggle Button
struct ThemeToggleButton: View {
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: toggleTheme) {
            Image(systemName: themeIcon)
                .font(.title3)
                .foregroundColor(BananaTheme.ColorToken.text)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var themeIcon: String {
        switch themeManager.effectiveColorScheme {
        case .light:
            return "moon.fill"
        case .dark:
            return "sun.max.fill"
        @unknown default:
            return "circle.lefthalf.filled"
        }
    }
    
    private func toggleTheme() {
        switch themeManager.themePreference {
        case .system:
            themeManager.setTheme(colorScheme == .dark ? .light : .dark)
        case .light:
            themeManager.setTheme(.dark)
        case .dark:
            themeManager.setTheme(.light)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct ThemePickerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack {
                ThemePickerView()
                Spacer()
                CompactThemePickerView()
                Spacer()
                ThemeToggleButton()
            }
            .padding()
            .bananaBackground()
            .previewDisplayName("Light Mode")
            .preferredColorScheme(.light)
            
            VStack {
                ThemePickerView()
                Spacer()
                CompactThemePickerView()
                Spacer()
                ThemeToggleButton()
            }
            .padding()
            .bananaBackground()
            .previewDisplayName("Dark Mode")
            .preferredColorScheme(.dark)
        }
    }
}
#endif