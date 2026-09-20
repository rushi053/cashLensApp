import SwiftUI

// MARK: - iPhone Duo (iOS 27.1) layout support
//
// iOS 27.1 / Xcode 27.1 add the Duo-specific layout APIs (per the
// "Design for iPhone Duo" tech talks): `ArrangementView`,
// `toolbarVerticalBehavior`, `toolbarCompressionBehavior`, and
// `GeometryProxy.reservedRegions(kind:)`. None of them are in the
// release Xcode 27 SDK that 2.2 ships with, and their exact spellings
// are not documented yet.
//
// Everything that names one of those APIs lives in this file behind
// `#if CASHLENS_DUO_27_1`. That compilation condition is **not defined
// anywhere**, so today every helper here compiles to a plain no-op and
// the rest of the app only ever sees one modifier call per site
// (`.duoHorizontalToolbar()`, `.duoTabBarCompression()`,
// `DuoArrangement { } secondary: { }`, `DuoLayoutSupport.divisionGutter`).
//
// To finish this for 2.2.1 on the 27.1 SDK:
//   1. Target → Build Settings → Swift Compiler – Custom Flags →
//      Active Compilation Conditions → add `CASHLENS_DUO_27_1`.
//   2. Fix every line marked `// Duo 27.1` against the real SDK names
//      (the worklog's "Duo 27.1 TODO" list enumerates them).
//   3. Build; remove the flag again if the SDK is not ready.
//
// Deployment target stays iOS 18: each real call is additionally
// wrapped in `if #available(iOS 27.1, *)`.

enum DuoLayoutSupport {

    /// Heuristic for "the system has moved its bars to a vertical strip
    /// on the trailing edge" — the iPhone Duo outer display (iOS 27
    /// SDK builds). Pure geometry, no SDK dependency:
    ///
    ///   • compact width and regular height (a portrait phone-class
    ///     window), and
    ///   • a trailing safe-area inset of at least `verticalBarMinimumInset`
    ///     that is clearly larger than the leading one.
    ///
    /// Every iPhone reports 0/0 horizontal insets in portrait and
    /// symmetric insets with *compact* height in landscape, so this is
    /// `false` on every iPhone. iPad is regular width and never gets
    /// here. Used only to move the floating "+" into the bottom corner
    /// when there is no bottom tab bar to clear.
    static let verticalBarMinimumInset: CGFloat = 44

    static func hasVerticalSystemBar(
        safeAreaInsets: EdgeInsets,
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        guard horizontalSizeClass == .compact, verticalSizeClass == .regular else { return false }
        return safeAreaInsets.trailing >= verticalBarMinimumInset
            && safeAreaInsets.trailing > safeAreaInsets.leading + Theme.Spacing.xxl
    }

    /// Width of the hinge's division region intersecting `proxy`, or 0
    /// when there is none (every non-Duo device, and a Duo that is
    /// fully open or closed). `EvenColumnGrid` adds this to its column
    /// spacing so the middle gutter clears the fold.
    static func divisionGutter(in proxy: GeometryProxy) -> CGFloat {
        #if CASHLENS_DUO_27_1
        if #available(iOS 27.1, *) {
            // Duo 27.1: best reading of the API — `reservedRegions(kind:)`
            // returns the regions of that kind intersecting the proxy, each
            // with a `frame` in the proxy's local space. If the SDK hands
            // back plain `CGRect`s instead, drop `.frame`.
            return proxy.reservedRegions(kind: .division)
                .map { $0.frame.width }
                .max() ?? 0
        }
        return 0
        #else
        _ = proxy
        return 0
        #endif
    }
}

extension View {

    /// Duo 27.1: on the outer display the system moves toolbars to a
    /// vertical bar on the right edge. A sheet whose only bar item is
    /// Close (paywall, add expense) reads better with a horizontal bar,
    /// so those sheets opt out. No-op today.
    func duoHorizontalToolbar() -> some View {
        #if CASHLENS_DUO_27_1
        return Group {
            if #available(iOS 27.1, *) {
                // Duo 27.1: verify modifier name and the "never
                // vertical" case name.
                self.toolbarVerticalBehavior(.never)
            } else {
                self
            }
        }
        #else
        return self
        #endif
    }

    /// Duo 27.1: when the outer display's vertical bar runs out of room,
    /// the tab bar should compress before the add-expense action does.
    /// Applied to the root `TabView`. No-op today.
    func duoTabBarCompression() -> some View {
        #if CASHLENS_DUO_27_1
        return Group {
            if #available(iOS 27.1, *) {
                // Duo 27.1: verify modifier name and the behavior case.
                self.toolbarCompressionBehavior(.tabBarFirst)
            } else {
                self
            }
        }
        #else
        return self
        #endif
    }
}

/// Duo 27.1: two related views that should sit on opposite halves of a
/// partially-folded inner display (`ArrangementView(.split)`), e.g. a
/// chart and its range picker in Insights. Everywhere else — and on
/// today's SDK — this is a plain `VStack`.
struct DuoArrangement<Primary: View, Secondary: View>: View {
    /// Our own spelling of the two arrangements so call sites compile
    /// with the flag off. Mapped to the SDK's cases inside the flag.
    enum Mode {
        /// Primary and secondary on opposite halves of the fold
        /// (chart | range picker).
        case split
        /// Secondary floats over the primary (e.g. controls over a
        /// full-bleed chart) when the fold is not active.
        case overlay
    }

    var mode: Mode = .split
    var spacing: CGFloat = Theme.Spacing.md
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    init(
        mode: Mode = .split,
        spacing: CGFloat = Theme.Spacing.md,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.mode = mode
        self.spacing = spacing
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        #if CASHLENS_DUO_27_1
        if #available(iOS 27.1, *) {
            // Duo 27.1: best reading — `ArrangementView` takes the
            // arrangement first and a two-view builder. The first view is
            // the primary (kept on the display half the user is looking
            // at in table pose); the second is displaced across the fold.
            switch mode {
            case .split:
                ArrangementView(.split) {
                    primary()
                    secondary()
                }
            case .overlay:
                ArrangementView(.overlay) {
                    primary()
                    secondary()
                }
            }
        } else {
            stacked
        }
        #else
        stacked
        #endif
    }

    private var stacked: some View {
        VStack(spacing: spacing) {
            primary()
            secondary()
        }
    }
}
