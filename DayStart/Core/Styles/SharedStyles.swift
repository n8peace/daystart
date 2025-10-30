import SwiftUI

// MARK: - Shared Button Styles

struct InstantResponseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(BananaTheme.ColorToken.primary)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                    .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            )
    }
}