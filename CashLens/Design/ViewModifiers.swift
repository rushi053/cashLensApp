import SwiftUI

// MARK: - Elevated Card Surface (default)
//
// Premium "elevated white card" look — the same trick Apple uses in Wallet,
// Apple Health, and the Stocks app: pure white cards floating off the page
// via a soft, multi-layer shadow rather than a coloured background fill.
//
//   • Light mode: card is pure `systemBackground` (#FFFFFF). The page
//     background is also white, so the card is defined entirely by its
//     shadow + hairline border. Reads as a real piece of paper / plastic
//     floating above the page.
//   • Dark mode: card is `secondarySystemGroupedBackground` (#1C1C1E)
//     against the near-black page bg, so the contrast comes from the
//     fill itself; the shadow stays for depth.
//   • Shadow is two-layer: a tight 1pt drop for the crisp under-edge +
//     a soft 18pt halo for the lift. Single-layer shadows look flat;
//     two layers look like real elevation.
//   • Hairline border (~0.5pt) gives the card a clean edge on retina
//     displays without competing with the shadow.
//
// Text inside cards keeps using `.foregroundColor(.primary)` so contrast
// stays AAA in both colour schemes.
struct GlassSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let strokeColor: Color?
    let strokeWidth: CGFloat

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        strokeColor ?? defaultBorder,
                        lineWidth: strokeColor == nil ? 0.5 : strokeWidth
                    )
            )
            // Crisp under-edge shadow — gives the card a defined "lip"
            // where it meets the page (the way a real card casts a hard
            // shadow right under itself).
            .shadow(color: shadowCrisp, radius: 1, x: 0, y: 1)
            // Soft lift shadow — the diffuse halo that makes the card
            // feel like it's hovering. Single-layer shadows look flat;
            // crisp + soft together feels like real elevation.
            .shadow(color: shadowSoft, radius: 18, x: 0, y: 8)
    }

    /// Pure white in light (vs the white page bg, the shadow defines
    /// the card edge). Slightly elevated dark grey in dark mode so the
    /// card reads against the near-black page.
    private var cardFill: Color {
        scheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color(uiColor: .systemBackground)
    }

    private var defaultBorder: Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }

    private var shadowCrisp: Color {
        scheme == .dark
            ? Color.black.opacity(0.40)
            : Color.black.opacity(0.04)
    }

    private var shadowSoft: Color {
        scheme == .dark
            ? Color.black.opacity(0.50)
            : Color.black.opacity(0.08)
    }
}

// MARK: - Flat Card Surface (legacy / explicit fill)

/// Used only when a caller passes an explicit `fill:` to `cardSurface`.
/// Gives a flat coloured rectangle — used for tinted selection states
/// (`color.opacity(0.10)`), paywall feature cards, contact link chips,
/// etc. — where the glass material would dilute the intended colour.
struct CardSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let fill: AnyShapeStyle
    let strokeColor: Color?
    let strokeWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                Group {
                    if let strokeColor {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(strokeColor, lineWidth: strokeWidth)
                    }
                }
            )
    }
}

extension View {
    /// Default "liquid glass" card surface used everywhere in the app
    /// (Home hero, Statistics cards, Pro Insights, Forecast, Subscriptions,
    /// Profile rows, etc.). Translucent material + faint brand wash + a
    /// hairline glass edge.
    ///
    /// - Parameters:
    ///   - radius: One of `Theme.Radius.*`. Defaults to `.card`.
    ///   - stroke: Optional stroke colour. Pass non-nil to override the
    ///     default glass-edge hairline (e.g. tinted brand stroke on the
    ///     hero card).
    ///   - strokeWidth: Stroke width, defaults to `Theme.Stroke.thin`.
    func cardSurface(
        radius: CGFloat = Theme.Radius.card,
        stroke: Color? = nil,
        strokeWidth: CGFloat = Theme.Stroke.thin
    ) -> some View {
        modifier(GlassSurfaceModifier(
            radius: radius,
            strokeColor: stroke,
            strokeWidth: strokeWidth
        ))
    }

    /// Flat-fill card surface — opt-out from the glass default. Use when
    /// the background must be a solid colour: tinted selection states,
    /// paywall feature cards, contact-link chips, info banners, etc.
    func cardSurface(
        radius: CGFloat = Theme.Radius.card,
        fill: some ShapeStyle,
        stroke: Color? = nil,
        strokeWidth: CGFloat = Theme.Stroke.thin
    ) -> some View {
        modifier(CardSurfaceModifier(
            radius: radius,
            fill: AnyShapeStyle(fill),
            strokeColor: stroke,
            strokeWidth: strokeWidth
        ))
    }

    /// Outer container for grouped sections (Profile blocks, iPad Home
    /// blocks). Stays on a soft flat tint rather than glass so nested
    /// glass cards read above it without doubling up the material.
    func sectionContainer(padding: CGFloat = Theme.Spacing.lg) -> some View {
        self
            .padding(padding)
            .cardSurface(
                radius: Theme.Radius.container,
                fill: Color.secondarySystemBackground.opacity(0.5)
            )
    }
}

// MARK: - Elevated Circle Surface
//
// Companion to `GlassSurfaceModifier` for circular icon buttons (search,
// profile, PDF export). Same elevated-card visual language — pure white
// in light, slightly elevated dark in dark, with the matching crisp +
// soft shadow combo so the button reads as a tiny floating chip rather
// than a flat grey circle.
struct ElevatedCircleSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                Circle().fill(cardFill)
            )
            .overlay(
                Circle().stroke(borderColor, lineWidth: 0.5)
            )
            .shadow(color: shadowCrisp, radius: 1, x: 0, y: 1)
            .shadow(color: shadowSoft, radius: 10, x: 0, y: 4)
    }

    private var cardFill: Color {
        scheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color(uiColor: .systemBackground)
    }

    private var borderColor: Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }

    private var shadowCrisp: Color {
        scheme == .dark
            ? Color.black.opacity(0.40)
            : Color.black.opacity(0.04)
    }

    private var shadowSoft: Color {
        scheme == .dark
            ? Color.black.opacity(0.50)
            : Color.black.opacity(0.07)
    }
}

// MARK: - Field Card

/// Input-specific surface used on "add" screens (Add Expense, New Budget, etc.).
///
/// Looks like a card, but always carries a hairline border so the field edge is
/// visible against white/near-white surfaces, and gains a tinted `appPrimary`
/// ring + soft glow while focused — the same affordance iOS uses for its own
/// material inputs.
struct FieldCardModifier: ViewModifier {
    let radius: CGFloat
    let isFocused: Bool

    func body(content: Content) -> some View {
        let borderColor = isFocused ? Color.appPrimary.opacity(0.55) : Color.primary.opacity(0.07)
        let borderWidth: CGFloat = isFocused ? 1.5 : 1
        let shadowColor = isFocused ? Color.appPrimary.opacity(0.18) : Theme.Shadow.cardColor
        let shadowRadius: CGFloat = isFocused ? 10 : Theme.Shadow.cardRadius
        let shadowY: CGFloat = isFocused ? 4 : Theme.Shadow.cardY

        return content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            .animation(Theme.Motion.snappy, value: isFocused)
    }
}

extension View {
    /// Canonical text-field surface for "add" / "edit" screens.
    ///
    /// - Parameters:
    ///   - radius: One of `Theme.Radius.*`. Defaults to `.card`.
    ///   - isFocused: Pass the `FocusState` binding comparison for this field.
    func fieldCard(radius: CGFloat = Theme.Radius.card, isFocused: Bool = false) -> some View {
        modifier(FieldCardModifier(radius: radius, isFocused: isFocused))
    }
}

// MARK: - Soft shadow

/// Subtle elevation used on cards that need to sit above the scroll background.
/// Most cards in the app should NOT use this — rely on `cardSurface` alone.
struct SoftShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(
            color: Theme.Shadow.cardColor,
            radius: Theme.Shadow.cardRadius,
            x: 0,
            y: Theme.Shadow.cardY
        )
    }
}

extension View {
    func softShadow() -> some View { modifier(SoftShadowModifier()) }
}

// MARK: - Primary action shadow

/// The mauve-tinted glow used under primary CTAs.
struct PrimaryGlowModifier: ViewModifier {
    var strength: CGFloat = 0.3

    func body(content: Content) -> some View {
        content.shadow(
            color: Color.appPrimary.opacity(strength),
            radius: 10,
            x: 0,
            y: 5
        )
    }
}

extension View {
    func primaryGlow(strength: CGFloat = 0.3) -> some View {
        modifier(PrimaryGlowModifier(strength: strength))
    }
}
