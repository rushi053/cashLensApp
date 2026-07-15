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
        /// Trimmed from 120 → 100 in the v2 polish pass: both tab bar paths
        /// (native Liquid Glass on iOS 26, material bar on 18–25) now let
        /// content read through them, so the old opaque-bar safety margin
        /// was just dead space at the bottom of every scroll view.
        static let tabBarInset: CGFloat = 100
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
    ///
    /// **Dynamic Type.** Every token scales with the user's content size
    /// setting. Tokens whose point size matches a semantic text style at
    /// the default (Large) category use `Font.system(_:design:weight:)`
    /// directly (free live-scaling). Tokens with non-standard sizes
    /// (`pageTitle` 32pt, `numericSmall` 14pt) are computed properties
    /// that run the base size through `UIFontMetrics` against the
    /// closest style — computed (not stored) so the value is re-resolved
    /// on every render and picks up size-category changes, since SwiftUI
    /// re-evaluates view bodies when Dynamic Type changes. All tokens
    /// are pixel-identical to the previous fixed sizes at the default
    /// (Large) setting.
    enum Typography {
        /// Tab-level screen titles: "Statistics", "Subscriptions", the user's name on Home.
        /// 32pt base (deliberately 2pt under `.largeTitle`'s 34pt), scaled against `.largeTitle`.
        static var pageTitle: Font {
            .system(size: UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 32), weight: .bold)
        }
        /// In-page section headers: "Summary", "Categories", "Recent Expenses".
        static let sectionTitle: Font = .title3.bold()
        /// Subsection within a section (e.g. "Due Soon").
        static let subsectionTitle: Font = .headline
        /// Primary row title (card titles, list row titles).
        static let rowTitle: Font = .subheadline.weight(.semibold)
        /// Supporting metadata.
        static let caption: Font = .caption
        /// Numeric readouts (percentages, amounts).
        /// `.title3` is exactly 20pt at the default category — a clean
        /// semantic match for the previous fixed 20pt.
        static let numeric: Font = .system(.title3, design: .rounded, weight: .bold)
        /// Small numeric readouts (mini cards, inline stats).
        /// 14pt base sits between `.footnote` (13) and `.subheadline` (15);
        /// scaled against `.subheadline` as the closest role match.
        static var numericSmall: Font {
            .system(size: UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 14), weight: .semibold, design: .rounded)
        }
        /// Hero money numerals (Today verdict "SPENT", Insights "TOTAL
        /// SPENT"). One token so every hero number in the app is the same
        /// size — the design review flagged Today's 46pt vs Insights' 40pt
        /// as the one numeric inconsistency. Scaled against `.largeTitle`
        /// but capped (~1.4×) so an AX5 user gets a bigger-but-sane hero;
        /// call sites keep their `minimumScaleFactor` for long amounts.
        static var heroNumeric: Font {
            let scaled = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 46)
            return .system(size: min(scaled, 64), weight: .bold, design: .rounded)
        }
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
// The design language is solid-first: cards, chips, tints, and strokes
// never use gradients. The ONE sanctioned exception is `appDuotone` —
// a restrained primary → blended-primary run reserved for hero brand
// moments (the FAB, primary CTAs). It exists so the user's chosen theme
// reads as the designed *pair* it is (every `AppTheme` ships a secondary
// color), not a single flat accent. The far stop is the primary mixed
// 45% toward the secondary, so the run reads as a shift in temperature
// rather than a two-color rainbow — white text stays legible across it.
//
// Everything else should keep using `Color.appPrimary` directly.

extension LinearGradient {
    /// The sanctioned hero duotone (FAB, primary CTAs). Computed
    /// (`static var`) so the dynamically-resolved theme colors — which
    /// read `ThemeStore.activeTheme` — are freshly baked in on every
    /// render, keeping the user's chosen accent theme reactive.
    static var appDuotone: LinearGradient {
        ThemeStore.activeTheme.heroGradient
    }
}
