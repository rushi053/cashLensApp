import SwiftUI

struct FloatingAddButton: View {
    let action: () -> Void
    let isIPad: Bool
    
    init(action: @escaping () -> Void, isIPad: Bool = false) {
        self.action = action
        self.isIPad = isIPad
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(style: .medium)
            action()
        }) {
            ZStack {
                // Background circle with shadow. Duotone fill (the one
                // sanctioned gradient) so the theme's designed color pair
                // shows on the app's most prominent brand element.
                Circle()
                    .fill(LinearGradient.appDuotone)
                    .frame(width: isIPad ? 66 : 56, height: isIPad ? 66 : 56)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 2)
                
                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: isIPad ? 28 : 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        // Press feedback restored per the design review ("FAB has no
        // press feedback — the comment even notes the scale animation
        // was removed"). Scale-down + a 45° icon rotation on press so
        // the + feels mechanical, springing back on release. The
        // rotation lives in the style (driven by `isPressed`) so it
        // costs nothing while idle — unlike the old constant-keyed
        // animation this one only fires on actual presses.
        .buttonStyle(FABPressStyle())
        // Icon-only button on the app's single most important action —
        // VoiceOver must not read this as just "plus".
        .accessibilityLabel("Add expense")
    }
}

/// Press style for the floating + button: 0.9 scale with the plus
/// rotating to 45° (reads as "about to become ×/open"). No haptic here
/// — the action closure already fires the medium tap, and doubling it
/// was exactly the "buzzy, not crafted" pattern the review called out.
private struct FABPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .rotationEffect(.degrees(configuration.isPressed ? 45 : 0))
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct FloatingAddButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.1)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingAddButton(action: {})
                        .padding(.trailing, 20)
                        .padding(.bottom, 100)
                }
            }
        }
    }
} 