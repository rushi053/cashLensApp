import SwiftUI

/// Bottom padding for the pinned CTA strip at the foot of a form sheet
/// (Add Expense, Budget, Subscription, Custom Category).
///
/// The strips used a flat 40pt. Above a keyboard that is right — the
/// safe area *is* the keyboard, and 40pt is the air between it and the
/// button. Without a keyboard the home-indicator inset already supplies
/// most of that, so the flat value stacked on top of it: 74pt on an
/// iPhone, and a ~110pt dead band on the iPhone Duo outer display
/// (≈70pt inset). This tops the inset up to `target` instead of adding
/// to it, and keeps the full 40pt whenever the inset looks like a
/// keyboard.
private struct StickyCTABottomPadding: ViewModifier {
    var target: CGFloat
    var aboveKeyboard: CGFloat
    var minimum: CGFloat

    @State private var bottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, padding)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { newValue in
                bottomInset = newValue
            }
    }

    private var padding: CGFloat {
        let keyboardLikelyUp = bottomInset > 120
        if keyboardLikelyUp { return aboveKeyboard }
        return max(minimum, target - bottomInset)
    }
}

extension View {
    /// See `StickyCTABottomPadding`.
    func stickyCTABottomPadding(
        target: CGFloat = 44,
        aboveKeyboard: CGFloat = 40,
        minimum: CGFloat = Theme.Spacing.lg
    ) -> some View {
        modifier(StickyCTABottomPadding(target: target, aboveKeyboard: aboveKeyboard, minimum: minimum))
    }
}
