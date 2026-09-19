import SwiftUI

// MARK: - Large-screen (regular width) layout support
//
// Everything in `Views/LargeScreen/` is only ever reached from an
// `if horizontalSizeClass == .regular` branch — iPad full screen or a
// wide Split View pane, and the iPhone Duo inner display. Compact width
// (every iPhone, the Duo outer display, Slide Over, 1/3 Split View)
// never instantiates these types, so the iPhone view trees are exactly
// what they were before this folder existed.
//
// Design notes live in `docs/LARGE_SCREEN_DESIGN.md`.

enum LargeScreenLayout {
    /// A "regular" window can still be narrow: the Duo inner display in
    /// portrait is ~626pt, an 11" iPad at 50/50 Split View ~597pt, a 13"
    /// at 50/50 ~683pt. Below this measured content width the dashboards
    /// stay in one column (with wider cards) instead of two columns
    /// narrower than an iPhone card. 700 keeps iPad mini portrait (744)
    /// and the Duo inner display in landscape (~830 usable) on two
    /// columns of ≥ 330pt.
    static let twoColumnMinimumWidth: CGFloat = 700

    /// Activity shows its filter rail (three regions) from this measured
    /// width up: iPad 13" portrait (1024) and every iPad landscape.
    /// Below it — Duo inner landscape (~830pt usable), 11" portrait —
    /// the two-pane layout keeps the horizontal chip row instead.
    static let threeRegionMinimumWidth: CGFloat = 1000

    static let filterRailWidth: CGFloat = 240

    /// Dashboards (Today, Insights, You) stop growing here so a 13" iPad
    /// in landscape doesn't stretch cards to 1300pt lines.
    static let dashboardMaxWidth: CGFloat = 1200

    /// Centred single-purpose content (first-run hero, onboarding page).
    static let formMaxWidth: CGFloat = 560

    /// The inline expense editor in Activity's detail column.
    static let editorMaxWidth: CGFloat = 640

    static let columnSpacing: CGFloat = Theme.Spacing.xl
    static let horizontalPadding: CGFloat = Theme.Spacing.xxxl
}

// MARK: - Two equal columns

/// Two equal-width columns when there is room, one column otherwise.
/// Collapses to a single column at accessibility Dynamic Type sizes
/// regardless of width — a 300pt column cannot hold AX5 text.
struct LargeScreenColumns<Leading: View, Trailing: View>: View {
    let twoColumns: Bool
    let spacing: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        twoColumns: Bool,
        spacing: CGFloat = LargeScreenLayout.columnSpacing,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.twoColumns = twoColumns
        self.spacing = spacing
        self.leading = leading
        self.trailing = trailing
    }

    private var showsTwoColumns: Bool {
        twoColumns && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        if showsTwoColumns {
            HStack(alignment: .top, spacing: spacing) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .top)
                trailing()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(spacing: spacing) {
                leading()
                trailing()
            }
        }
    }
}

// MARK: - Placed primary action

/// The regular-width replacement for the floating "+". The FAB is
/// hidden on regular width (it floated over content, and next to the
/// Duo vertical bar it read as chrome that missed its rail); each tab
/// places one of these in its own header instead.
struct LargeScreenAddButton: View {
    enum Style {
        /// 34pt filled disc with a "+" — for headers that already carry
        /// other icon buttons (Insights).
        case disc
        /// "+ Log expense" pill — for the Today header, where the label
        /// sells the action.
        case pill
    }

    var style: Style = .disc
    /// Disc diameter, so the button can match a neighbouring icon
    /// button (Insights' 40pt export disc) instead of sitting next to it
    /// at a slightly different size.
    var discDiameter: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.mediumTap()
            action()
        } label: {
            switch style {
            case .disc:
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: discDiameter, height: discDiameter)
                    .background(Circle().fill(Color.appPrimary))
            case .pill:
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Log expense")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, Theme.Spacing.lg - 2)
                .padding(.vertical, Theme.Spacing.sm + 1)
                .background(Capsule().fill(LinearGradient.appDuotone))
                .primaryGlow(strength: 0.22)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("Add expense")
    }
}

// MARK: - Presentation sizing

/// Form-sized card presentation on regular width; untouched otherwise.
/// `enabled` must come from the *presenter's* size class — a sheet's own
/// environment reports compact width on iPad, so reading it from inside
/// the presented view would never fire.
struct LargeScreenFormSheetModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        Group {
            if enabled {
                content.presentationSizing(.form)
            } else {
                content
            }
        }
    }
}

extension View {
    /// See `LargeScreenFormSheetModifier`. `presentationSizing` is an
    /// iOS 18 API; the deployment target is iOS 18, so no gate.
    func largeScreenFormSheet(enabled: Bool) -> some View {
        modifier(LargeScreenFormSheetModifier(enabled: enabled))
    }

    /// Publishes this view's laid-out width into `width`. Used by the
    /// dashboards to pick one or two columns from the real container
    /// width instead of the size class alone.
    func measureLayoutWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if width.wrappedValue != newWidth {
                width.wrappedValue = newWidth
            }
        }
    }
}

// MARK: - Rail pieces (Activity filter rail)

/// Uppercase eyebrow above a group of rail rows.
struct LargeScreenRailHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.secondary)
            .padding(.horizontal, Theme.Spacing.sm + 2)
    }
}

/// One selectable row in a vertical filter rail. Same states as
/// `PillChip` (tinted when selected) but laid out as a sidebar row so
/// twenty categories read as a list, not a chip scroller.
struct LargeScreenRailRow<Trailing: View>: View {
    let title: String
    var icon: String? = nil
    var iconTint: Color? = nil
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        icon: String? = nil,
        iconTint: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.iconTint = iconTint
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm + 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .appPrimary : (iconTint ?? .secondary))
                        .frame(width: 22)
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .appPrimary : .primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                trailing()
            }
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.appPrimary.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
