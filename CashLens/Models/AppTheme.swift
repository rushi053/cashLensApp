import SwiftUI

/// User-selectable accent theme.
///
/// Each theme bundles a primary and secondary color with hand-tuned
/// light / dark hex pairs so contrast stays safe on both backgrounds.
/// The default (`mauve`) preserves the historical CashLens brand color so
/// existing users see no visual change unless they explicitly opt into a
/// different theme via the Personalization picker.
///
/// Pro feature — free users can browse + preview but tapping a non-default
/// theme opens the paywall.
struct AppTheme: Identifiable, Hashable, Sendable {

    let id: String
    let displayName: String

    /// Brand primary — used by tab bar tint, selected pills, FAB, Save buttons,
    /// chart strokes, info badges, etc.
    let primaryLightHex: String
    let primaryDarkHex: String

    /// Brand secondary — used by gradient pairs, chart accent series, etc.
    let secondaryLightHex: String
    let secondaryDarkHex: String

    /// Dynamic primary that resolves against the current `UITraitCollection`.
    /// The closure runs on every render, so a UITrait change (light/dark
    /// toggle) re-resolves transparently.
    var primaryColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: primaryDarkHex) ?? UIColor(hex: AppTheme.mauve.primaryDarkHex)!
                : UIColor(hex: primaryLightHex) ?? UIColor(hex: AppTheme.mauve.primaryLightHex)!
        })
    }

    /// Dynamic secondary that resolves against the current `UITraitCollection`.
    var secondaryColor: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: secondaryDarkHex) ?? UIColor(hex: AppTheme.mauve.secondaryDarkHex)!
                : UIColor(hex: secondaryLightHex) ?? UIColor(hex: AppTheme.mauve.secondaryLightHex)!
        })
    }

    // MARK: - Catalog

    /// CashLens classic — original mauve & jordy blue. Default for all users.
    static let mauve = AppTheme(
        id: "mauve",
        displayName: "Mauve",
        primaryLightHex: "#B48CF0",
        primaryDarkHex: "#AA7DDC",
        secondaryLightHex: "#6E96FF",
        secondaryDarkHex: "#7896EB"
    )

    /// Clean fintech blue — trustworthy, calm.
    static let ocean = AppTheme(
        id: "ocean",
        displayName: "Ocean",
        primaryLightHex: "#3D8BF5",
        primaryDarkHex: "#5DA0FA",
        secondaryLightHex: "#2EBFD8",
        secondaryDarkHex: "#5AD3E6"
    )

    /// Money-forward green — calm, growth.
    static let forest = AppTheme(
        id: "forest",
        displayName: "Forest",
        primaryLightHex: "#2FA060",
        primaryDarkHex: "#56C589",
        secondaryLightHex: "#7DBE3A",
        secondaryDarkHex: "#A8D560"
    )

    /// Warm sunset orange — energetic, bold.
    static let sunset = AppTheme(
        id: "sunset",
        displayName: "Sunset",
        primaryLightHex: "#EE6B2D",
        primaryDarkHex: "#FF8B55",
        secondaryLightHex: "#E89740",
        secondaryDarkHex: "#F5B373"
    )

    /// Vibrant berry pink — bold, playful.
    static let berry = AppTheme(
        id: "berry",
        displayName: "Berry",
        primaryLightHex: "#D8417A",
        primaryDarkHex: "#EC6094",
        secondaryLightHex: "#A04AB5",
        secondaryDarkHex: "#BC75CC"
    )

    /// Minimalist neutral — for the monochrome lover.
    static let graphite = AppTheme(
        id: "graphite",
        displayName: "Graphite",
        primaryLightHex: "#4D5563",
        primaryDarkHex: "#A6ACB8",
        secondaryLightHex: "#7B828F",
        secondaryDarkHex: "#C2C8D2"
    )

    // MARK: - Pastel collection
    //
    // Softer, friendlier palettes alongside the classics. Each pastel is
    // tuned slightly more saturated than a "true pastel" so white text
    // remains legible on top of the primary (used for selected pills, the
    // FAB, and Save buttons). Dark-mode hexes are lifted so the colour
    // doesn't disappear on the near-black background — same trick the
    // classic catalog uses.

    /// Soft cool violet — calm and dreamy.
    static let lavender = AppTheme(
        id: "lavender",
        displayName: "Lavender",
        primaryLightHex: "#9580E5",
        primaryDarkHex: "#AC9AF0",
        secondaryLightHex: "#B59BE0",
        secondaryDarkHex: "#C8B4ED"
    )

    /// Fresh teal-mint — crisp and vibrant without being loud.
    static let mint = AppTheme(
        id: "mint",
        displayName: "Mint",
        primaryLightHex: "#3DC0A0",
        primaryDarkHex: "#5BD0B5",
        secondaryLightHex: "#6BD0BB",
        secondaryDarkHex: "#82DCC8"
    )

    /// Warm pastel peach — cozy, summery.
    static let peach = AppTheme(
        id: "peach",
        displayName: "Peach",
        primaryLightHex: "#F58A60",
        primaryDarkHex: "#FFA383",
        secondaryLightHex: "#FFAA90",
        secondaryDarkHex: "#FFBFA8"
    )

    /// Soft sky blue — airy and bright.
    static let sky = AppTheme(
        id: "sky",
        displayName: "Sky",
        primaryLightHex: "#5AAEE0",
        primaryDarkHex: "#78C0E8",
        secondaryLightHex: "#88C5E5",
        secondaryDarkHex: "#A2D2EE"
    )

    /// Dusty rose — warm and romantic.
    static let rose = AppTheme(
        id: "rose",
        displayName: "Rose",
        primaryLightHex: "#E3819A",
        primaryDarkHex: "#ED9DB0",
        secondaryLightHex: "#EBA5B8",
        secondaryDarkHex: "#F0BBC8"
    )

    /// Muted sage green — earthy, grounded, easy on the eyes.
    static let sage = AppTheme(
        id: "sage",
        displayName: "Sage",
        primaryLightHex: "#75A282",
        primaryDarkHex: "#8DB596",
        secondaryLightHex: "#95B59E",
        secondaryDarkHex: "#ABC4B0"
    )

    /// Ordered catalog. Used by the Theme picker. Classics first (the
    /// historical CashLens palette), then pastels — each pastel sits
    /// roughly under its classic counterpart in the 3-column grid so the
    /// two rows visually mirror each other (Mauve↔Lavender, Ocean↔Sky,
    /// etc.).
    static let all: [AppTheme] = [
        .mauve, .ocean, .forest, .sunset, .berry, .graphite,
        .lavender, .sky, .mint, .peach, .rose, .sage
    ]

    /// Fallback if the persisted id can't be resolved.
    static let `default`: AppTheme = .mauve

    /// Lookup by id (used when restoring from `UserDefaults`).
    static func resolve(id: String?) -> AppTheme {
        guard let id else { return .default }
        return all.first { $0.id == id } ?? .default
    }
}
