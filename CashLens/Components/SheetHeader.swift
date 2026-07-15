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
    var onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        showsCloseButton: Bool = true,
        showsDivider: Bool = true,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { SheetHeaderSpacer() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.showsCloseButton = showsCloseButton
        self.showsDivider = showsDivider
        self.onClose = onClose
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
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
            // Keep the title clear of the side controls even on
            // narrow devices / large Dynamic Type.
            .padding(.horizontal, 44)

            HStack {
                if showsCloseButton {
                    SheetCloseButton(action: onClose)
                } else {
                    SheetHeaderSpacer()
                }
                Spacer()
                trailing()
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
