import SwiftUI

/// Canonical header for custom-chrome sheets (Add Expense, Add
/// Subscription, Budget Setup, Currency, Quick Search, Custom
/// Category…).
///
/// One header language, derived from the Add Expense strip — the
/// app's most polished sheet header — instead of the five per-screen
/// variants that grew during the v2 wave:
///
///   • Centered title stack: optional uppercased eyebrow (10pt,
///     tracked) over a 17pt bold title, with an optional caption
///     subtitle underneath. The stack is pinned to the ZStack centre
///     so side controls can never push it off-axis.
///   • Leading 36pt circular close button (`SheetCloseButton`) —
///     ultra-thin material, hairline stroke. Screens that must not
///     be escapable (initial currency setup) can hide it; the slot
///     keeps its width so the title stays optically centered.
///   • Trailing slot for one contextual action (trash, Done pill,
///     Save-preset chip). Defaults to an invisible 36pt spacer.
    ///   • Spacing: `xl` horizontal, `xxl` top — clear air below the
    ///     sheet grab-handle zone (the old `lg` top read as "squeezed"
    ///     under the sheet's rounded corners) — `lg` bottom, and a
    ///     bottom hairline so the strip reads as fixed chrome above the
    ///     scrolling content.
struct SheetHeader<Trailing: View>: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var showsCloseButton: Bool = true
    var showsDivider: Bool = true
    /// Whether Esc triggers `onClose`. A sheet that has presented
    /// another sheet (category picker, field editor…) passes `false`
    /// so only the topmost layer answers Esc — SwiftUI does not define
    /// which of several live `.cancelAction` shortcuts wins.
    var escapeClosesSheet: Bool = true
    var onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    /// Collision handling between the centred title stack and a wide
    /// trailing control. The stack used to reserve a fixed 44pt per side,
    /// which assumes both side controls are the 36pt disc/spacer. A
    /// "Continue" / "Done" pill is ~90pt, so the subtitle of the first-run
    /// currency picker already ran under the pill on iPhones, and on the
    /// iPhone Duo outer display (content ≈ 340pt beside the vertical
    /// system bar) the title itself did.
    ///
    /// Rule: measure the trailing control and the title stack's natural
    /// width. If the stack fits centred with clearance on both sides,
    /// keep the old symmetric 44pt geometry (rendering identical to
    /// before). Only when it would collide does the title yield: it
    /// keeps 44pt on the leading side and moves clear of the trailing
    /// control, centring itself in what is left. Headers with the 36pt
    /// trailing slot never change.
    @State private var trailingWidth: CGFloat = 36
    @State private var naturalTitleWidth: CGFloat = 0
    @State private var headerContentWidth: CGFloat = 0

    private var trailingClearance: CGFloat {
        max(44, trailingWidth + Theme.Spacing.sm)
    }

    /// True when the centred stack would run under the trailing control.
    private var titleCollides: Bool {
        guard trailingClearance > 44, headerContentWidth > 0, naturalTitleWidth > 0 else { return false }
        return naturalTitleWidth > headerContentWidth - 2 * trailingClearance
    }

    private var titleLeadingPadding: CGFloat { 44 }

    private var titleTrailingPadding: CGFloat {
        titleCollides ? trailingClearance : 44
    }

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        showsCloseButton: Bool = true,
        showsDivider: Bool = true,
        escapeClosesSheet: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { SheetHeaderSpacer() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.showsCloseButton = showsCloseButton
        self.showsDivider = showsDivider
        self.escapeClosesSheet = escapeClosesSheet
        self.onClose = onClose
        self.trailing = trailing
    }

    /// Eyebrow / title / subtitle stack, shared by the visible header and
    /// the invisible natural-width probe.
    private var titleStack: some View {
        VStack(spacing: 2) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.4)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    var body: some View {
        ZStack {
            titleStack
                // Keep the title clear of the side controls even on
                // narrow devices / large Dynamic Type. 44pt both sides
                // unless the stack would collide with a wide trailing
                // control (see `titleCollides`).
                .padding(.leading, titleLeadingPadding)
                .padding(.trailing, titleTrailingPadding)
                // Natural (unconstrained) width of the same stack, laid
                // out invisibly so the collision test has a real number.
                // `fixedSize` keeps it from being squeezed; `hidden`
                // keeps it out of accessibility and hit testing.
                .background(
                    titleStack
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if newWidth != naturalTitleWidth {
                                naturalTitleWidth = newWidth
                            }
                        }
                )

            HStack {
                if showsCloseButton {
                    SheetCloseButton(action: onClose, respondsToEscape: escapeClosesSheet)
                } else {
                    SheetHeaderSpacer()
                }
                Spacer()
                trailing()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if newWidth != trailingWidth {
                            trailingWidth = newWidth
                        }
                    }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if newWidth != headerContentWidth {
                headerContentWidth = newWidth
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        // `xxl` clears the grab-handle zone (~16pt) with real air —
        // the old `lg` put the eyebrow right under the handle.
        .padding(.top, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: Theme.Stroke.hairline)
            }
        }
    }
}

/// Canonical circular close button for sheets — 36pt material disc
/// with a hairline edge. Shared by `SheetHeader` and by hero-style
/// sheets (Paywall) that place the X alone without a title strip.
struct SheetCloseButton: View {
    var action: () -> Void
    /// See `SheetHeader.escapeClosesSheet`. Default on: a lone close
    /// button (paywall) is always the topmost layer.
    var respondsToEscape: Bool = true
    /// Set by an ancestor that currently has a presentation above this
    /// button (the tab shell while any app-level sheet is up; Activity's
    /// detail-column editor while one of its sheets is up). Sheets don't
    /// inherit it because the ancestors set it *inside* their `.sheet`
    /// modifiers, so only the layer underneath a presentation drops Esc.
    @Environment(\.escapeOwnedByPresentation) private var escapeOwnedByPresentation

    private var escapeIsLive: Bool {
        respondsToEscape && !escapeOwnedByPresentation
    }

    var body: some View {
        Button {
            HapticManager.shared.lightTap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        // Esc on a hardware keyboard closes the sheet through the same
        // action as the tap — so screens with custom dismiss handling
        // (`AddExpenseView.onDismissRequest`) behave identically.
        // Passing `nil` removes the shortcut while a layer above owns
        // Esc.
        .keyboardShortcut(escapeIsLive ? KeyboardShortcut.cancelAction : nil)
        .accessibilityLabel("Close")
    }
}

/// Invisible 36pt slot used to balance the header when a side has no
/// control, keeping the centered title optically centered.
struct SheetHeaderSpacer: View {
    var body: some View {
        Color.clear.frame(width: 36, height: 36)
    }
}

// MARK: - Esc ownership environment key
//
// SwiftUI does not define which of several live `.cancelAction`
// shortcuts wins. Presenters that can have a sheet above content that
// itself carries a `SheetCloseButton` publish "Esc is owned above" into
// that content's environment; the button then drops its shortcut.
// Default `false` — every close button answers Esc unless told otherwise.
private struct EscapeOwnedByPresentationKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var escapeOwnedByPresentation: Bool {
        get { self[EscapeOwnedByPresentationKey.self] }
        set { self[EscapeOwnedByPresentationKey.self] = newValue }
    }
}
