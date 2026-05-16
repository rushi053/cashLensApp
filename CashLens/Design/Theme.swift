import SwiftUI

/// Canonical design tokens for CashLens.
///
/// Every view in the app should reach for these instead of hard-coded numbers so the
/// visual language stays coherent and easy to evolve.
enum Theme {

    // MARK: - Spacing

    /// Vertical and horizontal rhythm. Multiples of 4.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        /// Inset applied to scroll views so content clears the custom tab bar.
        static let tabBarInset: CGFloat = 120
    }

    // MARK: - Corner Radius

    /// One canonical radius family. Pick the role, not a number.
    enum Radius {
        /// Small chips, selection pickers with a slightly squared feel.
        static let chip: CGFloat = 12
        /// Settings rows, list items, inline inputs.
        static let row: CGFloat = 14
        /// Standard content cards (summary, expense, budget).
        static let card: CGFloat = 16
        /// Outer section containers, grouped panels.
        static let container: CGFloat = 18
        /// Hero / featured surfaces (paywall, onboarding callouts).
        static let hero: CGFloat = 22
    }

    // MARK: - Stroke

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
        static let medium: CGFloat = 1.5
    }

    // MARK: - Typography

    /// Semantic type tokens. Use these instead of `.title3`, `.subheadline` etc.
    enum Typography {
        /// Tab-level screen titles: "Statistics", "Subscriptions", the user's name on Home.
        static let pageTitle: Font = .system(size: 32, weight: .bold)
        /// In-page section headers: "Summary", "Categories", "Recent Expenses".
        static let sectionTitle: Font = .title3.bold()
        /// Subsection within a section (e.g. "Due Soon").
        static let subsectionTitle: Font = .headline
        /// Primary row title (card titles, list row titles).
        static let rowTitle: Font = .subheadline.weight(.semibold)
        /// Supporting metadata.
        static let caption: Font = .caption
        /// Numeric readouts (percentages, amounts).
        static let numeric: Font = .system(size: 20, weight: .bold, design: .rounded)
        /// Small numeric readouts (mini cards, inline stats).
        static let numericSmall: Font = .system(size: 14, weight: .semibold, design: .rounded)
    }

    // MARK: - Shadow

    enum Shadow {
        static let cardColor: Color = .black.opacity(0.04)
        static let cardRadius: CGFloat = 6
        static let cardY: CGFloat = 2

        static let elevatedColor: Color = .black.opacity(0.08)
        static let elevatedRadius: CGFloat = 10
        static let elevatedY: CGFloat = 4
    }

    // MARK: - Motion

    /// Standardized spring timings. Use one of these three everywhere.
    enum Motion {
        /// Quick snap for selection toggles, filter chips.
        static let snappy: Animation = .easeOut(duration: 0.18)
        /// Default for taps, reveals, state changes.
        static let tap: Animation = .spring(response: 0.4, dampingFraction: 0.8)
        /// Larger reveals (card appear, section expand).
        static let emphasized: Animation = .spring(response: 0.55, dampingFraction: 0.78)
    }

    // MARK: - Icon Sizes

    enum Icon {
        static let chip: CGFloat = 13
        static let row: CGFloat = 18
        static let heroRow: CGFloat = 22
        static let emptyState: CGFloat = 36
    }
}

// MARK: - Money animation key
//
// SwiftUI's `.contentTransition(.numericText())` caches the rendered
// glyphs of a `Text` and uses the value passed to `.animation(value:)`
// to decide when to swap them. If we key off the raw amount (`Double`),
// switching currency in Settings doesn't move the amount — so the old
// symbol stays on screen even though the body re-evaluates and the
// formatter would now produce a new string.
//
// `MoneyAnimationKey` bundles **both** the amount and the active currency
// code into one `Hashable`, so changing either triggers a content
// refresh. Use it via `.moneyAnimation(...)` below; it's a one-line
// replacement for the existing `.animation(value: amount)` calls.

struct MoneyAnimationKey: Hashable {
    let amount: Double
    let currencyCode: String
}

extension View {
    /// Animation modifier for any money-displaying `Text` paired with
    /// `.contentTransition(.numericText())`. Triggers a content swap
    /// whenever the **amount or the currency** changes.
    ///
    /// Replaces the older pattern:
    /// ```swift
    /// .animation(Theme.Motion.snappy, value: amount)
    /// ```
    /// with:
    /// ```swift
    /// .moneyAnimation(amount: amount, currency: viewModel.selectedCurrency)
    /// ```
    func moneyAnimation(
        _ animation: Animation = Theme.Motion.snappy,
        amount: Double,
        currency: Expense.Currency
    ) -> some View {
        self.animation(animation, value: MoneyAnimationKey(
            amount: amount,
            currencyCode: currency.rawValue
        ))
    }
}

// MARK: - Brand surface helpers
//
// These used to return real `LinearGradient` values, but the design
// language is now strictly **solid** — no gradients anywhere in the app.
// We keep the `LinearGradient` extension shape (rather than removing it
// outright) so that every existing call site keeps compiling without
// edits. Each helper returns a `LinearGradient` whose two colour stops
// are the same colour, which renders pixel-identically to a solid fill.
//
// New code should prefer `Color.appPrimary` directly. These helpers exist
// purely as a backwards-compatibility shim during the migration.

extension LinearGradient {
    /// Solid primary brand fill (CTAs, rings, brand surfaces).
    /// Computed (`static var`) so the dynamically-resolved `Color.appPrimary`
    /// — which reads `ThemeStore.activeTheme` — is freshly baked in on
    /// every render, keeping the user's chosen accent theme reactive.
    static var appPrimary: LinearGradient {
        LinearGradient(colors: [.appPrimary, .appPrimary], startPoint: .leading, endPoint: .trailing)
    }

    /// Solid primary brand fill (alias kept for legacy diagonal call sites).
    static var appPrimaryDiagonal: LinearGradient {
        LinearGradient(colors: [.appPrimary, .appPrimary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Subtle tinted background fill (pro teaser, badges) — solid mauve at
    /// low opacity. Renders identically to `Color.appPrimary.opacity(0.07)`.
    static var appPrimarySoft: LinearGradient {
        LinearGradient(
            colors: [Color.appPrimary.opacity(0.07), Color.appPrimary.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
