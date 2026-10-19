import SwiftUI

/// Soft fade under the status bar for scroll views that have no
/// navigation bar of their own (the Today / Insights / You tab roots
/// draw custom headers inside the scroll content).
///
/// Without a bar there is nothing for the system scroll-edge effect
/// to attach to, so scrolled content ran straight under the clock and
/// battery glyphs. This paints a short gradient from the page
/// background to clear across the top safe area plus a few points,
/// which is invisible while the page sits at its natural top and
/// only shows once content scrolls beneath the status bar.
///
/// Applied at every width: the iPhone Duo inner display is regular
/// width but puts the system tab bar on the trailing edge, so its top
/// edge is as bare as an iPhone's. On iPad the floating top tab bar
/// has its own edge effect; the gradient fades into the same
/// background there and does not read as a second bar.
private struct StatusBarScrim: ViewModifier {
    var enabled: Bool
    var background: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if enabled {
                LinearGradient(
                    stops: [
                        .init(color: background, location: 0),
                        .init(color: background.opacity(0.92), location: 0.55),
                        .init(color: background.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // The 14pt is the visible part below the safe area; the
                // gradient stretches up through the status bar.
                .frame(height: 14)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// See `StatusBarScrim`.
    func statusBarScrim(enabled: Bool = true, background: Color = .systemBackground) -> some View {
        modifier(StatusBarScrim(enabled: enabled, background: background))
    }
}
