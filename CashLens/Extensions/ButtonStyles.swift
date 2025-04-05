import SwiftUI

/// A button style that scales the button down when pressed and provides haptic feedback
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    // Use medium tap instead of light tap for more prominent feedback
                    HapticManager.shared.mediumTap()
                }
            }
    }
}

/// A button style that adds a subtle opacity change when pressed
struct OpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    // Add haptic feedback to this style as well
                    HapticManager.shared.lightTap()
                }
            }
    }
}

/// A custom button style specifically for the Add Expense button with stronger haptic feedback
struct CustomAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    // Provide a stronger haptic sequence for the add expense button
                    HapticManager.shared.heavyTap()
                }
            }
    }
} 