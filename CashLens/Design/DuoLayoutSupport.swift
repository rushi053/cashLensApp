import SwiftUI

// MARK: - iPhone Duo layout support
//
// Requires the iOS 27.1 SDK (Xcode 27.1 or later) to build. The deployment
// target stays iOS 18, so every 27.1 call is behind `#available` and
// earlier systems get the plain layout.

enum DuoLayoutSupport {

    /// Heuristic for "the system has moved its bars to a vertical strip
    /// on the trailing edge" — the iPhone Duo outer display. Pure
    /// geometry:
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

    /// Width of an active vertical hinge division crossing `proxy`, or 0
    /// when there is none (every non-Duo device, a Duo that is fully open
    /// or closed, and a horizontal fold, which a column gutter can't
    /// clear). Clamped so a bad region can never exceed half the width.
    /// `EvenColumnGrid` adds this to its column spacing so the middle
    /// gutter clears the fold.
    static func divisionGutter(in proxy: GeometryProxy) -> CGFloat {
        guard #available(iOS 27.1, *) else { return 0 }
        guard let hinge = verticalHinge(in: proxy) else { return 0 }
        return min(hinge.frame.width, proxy.size.width / 2)
    }

    // MARK: Two-column split on the hinge

    /// Where a two-column layout should put its gutter. `equal` means
    /// "no hinge here, split the width evenly with the normal spacing".
    struct ColumnSplit: Equatable {
        /// Fixed leading column width, or nil for an equal split.
        var leadingWidth: CGFloat?
        /// Gutter width, or nil for the caller's normal spacing.
        var gutter: CGFloat?

        static let equal = ColumnSplit(leadingWidth: nil, gutter: nil)
    }

    /// Narrowest column worth keeping when aligning to the hinge. Below
    /// this the hinge is too far off-centre for two columns, so the
    /// layout falls back to an even split (the fold then crosses one
    /// column, which is still better than two unreadable ones).
    static let minimumHingeColumnWidth: CGFloat = 280

    /// Aligns a two-column gutter with an active vertical hinge crossing
    /// `proxy`. The gutter covers the hinge's frame (which already
    /// includes Apple's margins), is never narrower than `spacing`, and
    /// is centred on the hinge so both columns keep the same clearance.
    static func columnSplit(in proxy: GeometryProxy, spacing: CGFloat) -> ColumnSplit {
        guard #available(iOS 27.1, *) else { return .equal }
        let width = proxy.size.width
        guard let hinge = verticalHinge(in: proxy) else { return .equal }

        // `ReservedRegion.frame` already includes Apple's margins.
        let gutter = max(spacing, hinge.frame.width)
        let leadingWidth = hinge.frame.midX - gutter / 2
        let trailingWidth = width - leadingWidth - gutter
        guard leadingWidth >= minimumHingeColumnWidth, trailingWidth >= minimumHingeColumnWidth else {
            return .equal
        }
        return ColumnSplit(leadingWidth: leadingWidth, gutter: gutter)
    }

    /// Two-pane (list | detail) geometry on a partially folded Duo.
    struct PaneSplit: Equatable {
        /// Leading pane width so that it ends just before the hinge.
        var leadingWidth: CGFloat
        /// Leading inset for the trailing pane so its content starts
        /// just after the hinge (the pane itself begins at the divider).
        var trailingInset: CGFloat
    }

    /// Geometry for a leading pane (Activity's ledger) that ends at the
    /// hinge, with the pane after it starting on the other half. Nil
    /// without an active vertical hinge, or when the hinge would leave
    /// the leading pane outside `minimum...maximum`. `leadingOffset` is
    /// the width of anything laid out before the pane (the filter rail).
    static func paneSplit(
        in proxy: GeometryProxy,
        leadingOffset: CGFloat = 0,
        minimum: CGFloat,
        maximum: CGFloat,
        minimumTrailing: CGFloat
    ) -> PaneSplit? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let hinge = verticalHinge(in: proxy) else { return nil }
        // `ReservedRegion.frame` already includes Apple's margins.
        let leadingEnd = hinge.frame.minX
        let trailingStart = hinge.frame.maxX
        let width = leadingEnd - leadingOffset
        guard width >= minimum, width <= maximum,
              proxy.size.width - trailingStart >= minimumTrailing
        else { return nil }
        return PaneSplit(leadingWidth: width, trailingInset: max(0, trailingStart - leadingEnd))
    }

    // MARK: Official vertical-bar signal (iOS 27.1)

    /// Layout-neutral probe that reports Apple's own answer to "are the
    /// system bars vertical?" — `EnvironmentValues.toolbarVerticalEdge`
    /// (iOS 27.1). Non-nil on the Duo outer display and in inner-display
    /// Split View, where each app's bar sits on its *outer* edge — the
    /// left app's bar is on the leading edge, which the safe-area
    /// heuristic above deliberately ignores. Callers OR this with the
    /// heuristic so the FAB tucks into the corner in both cases.
    @available(iOS 27.1, *)
    struct VerticalToolbarProbe: View {
        @Environment(\.toolbarVerticalEdge) private var edge
        @Binding var isVertical: Bool

        var body: some View {
            Color.clear
                .onChange(of: edge != nil, initial: true) { _, vertical in
                    if vertical != isVertical { isVertical = vertical }
                }
        }
    }

    /// The active vertical hinge nearest the centre of `proxy`, if any.
    /// "Vertical" means taller than wide, or spanning the view's full
    /// height (in case the system clips the region to a short view).
    @available(iOS 27.1, *)
    private static func verticalHinge(in proxy: GeometryProxy) -> ReservedRegion? {
        let midX = proxy.size.width / 2
        return proxy.reservedRegions(kind: .division)
            .filter { region in
                region.isActive
                    && (region.frame.height > region.frame.width || region.frame.height >= proxy.size.height)
            }
            .min { abs($0.frame.midX - midX) < abs($1.frame.midX - midX) }
    }
}
