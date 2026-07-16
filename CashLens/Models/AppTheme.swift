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

    /// One-line personality descriptor shown in the Appearance studio
    /// ("Calm fintech blue"). Keeps the picker from being a mute color grid.
    let tagline: String

    /// Brand primary — used by tab bar tint, selected pills, FAB, Save buttons,
    /// chart strokes, info badges, etc.
    let primaryLightHex: String
    let primaryDarkHex: String

    /// Brand secondary — the theme's companion color. Blended into the
    /// primary for the sanctioned duotone on hero CTAs (FAB, Save buttons)
    /// so every theme reads as a *pair*, not a single flat accent.
    let secondaryLightHex: String
    let secondaryDarkHex: String

    /// Id of the `AppIconOption` that visually matches this theme, if one
    /// exists in the icon catalog. Drives the "Complete the look" pairing
    /// in the Appearance studio. `nil` for themes with no icon counterpart.
    let matchingIconId: String?

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

    /// Primary nudged 45% toward the secondary — the end stop of the
    /// sanctioned hero duotone. Blending (rather than using the raw
    /// secondary) keeps the gradient a *shift in temperature* instead of a
    /// two-color rainbow, so white text stays legible across the full run.
    var blendedColor: Color {
        Color(UIColor { trait in
            let dark = trait.userInterfaceStyle == .dark
            let p = UIColor(hex: dark ? primaryDarkHex : primaryLightHex)
                ?? UIColor(hex: AppTheme.mauve.primaryLightHex)!
            let s = UIColor(hex: dark ? secondaryDarkHex : secondaryLightHex)
                ?? UIColor(hex: AppTheme.mauve.secondaryLightHex)!
            return p.mixed(with: s, amount: 0.45)
        })
    }

    /// The one sanctioned gradient in the app: primary → blended primary,
    /// top-leading to bottom-trailing. Reserved for hero brand moments
    /// (FAB, primary CTAs) — everything else stays solid.
    var heroGradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor, blendedColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Catalog

    /// CashLens classic — original mauve & jordy blue. Default for all users.
    /// `primaryLightHex` matches the handcrafted primary AppIcon swatch
    /// (`#B1A1ED`) so the Appearance studio chip and Home Screen icon read
    /// as the same colour.
    static let mauve = AppTheme(
        id: "mauve",
        displayName: "Mauve",
        tagline: "The CashLens classic",
        primaryLightHex: "#B1A1ED",
        primaryDarkHex: "#A894E6",
        secondaryLightHex: "#6E96FF",
        secondaryDarkHex: "#7896EB",
        matchingIconId: "primary"
    )

    /// Clean fintech blue — trustworthy, calm. Retuned (v2.4 color pass)
    /// toward the confident "signal blue" family users love in Things
    /// (#2576EB) and Copilot Money (#1C6CFF): a touch deeper than the old
    /// #3D8BF5 so white text pops harder on filled surfaces, without
    /// tipping into corporate navy.
    static let ocean = AppTheme(
        id: "ocean",
        displayName: "Ocean",
        tagline: "Calm, trustworthy blue",
        primaryLightHex: "#2E7CF6",
        primaryDarkHex: "#5C9CF5",
        secondaryLightHex: "#2EBFD8",
        secondaryDarkHex: "#5AD3E6",
        matchingIconId: "ocean"
    )

    /// Money-forward green — calm, growth. Retuned (v2.4 color pass): a
    /// richer emerald primary, and the secondary swapped from lime
    /// (#7DBE3A — the one clashing pair in the catalog; the duotone
    /// blended toward murky yellow-green) to jade, so the pair reads as
    /// the emerald→mint money-green language of modern finance apps.
    static let forest = AppTheme(
        id: "forest",
        displayName: "Forest",
        tagline: "Green means growth",
        primaryLightHex: "#23A55E",
        primaryDarkHex: "#4EC583",
        secondaryLightHex: "#2FB98A",
        secondaryDarkHex: "#5ACFA5",
        matchingIconId: "forest"
    )

    /// Warm sunset orange — energetic, bold. Retuned (v2.4 color pass)
    /// toward the marigold family (Headspace's #FF6B35) with a golden
    /// amber secondary, so the duotone runs orange → amber instead of
    /// orange → dusty tan.
    static let sunset = AppTheme(
        id: "sunset",
        displayName: "Sunset",
        tagline: "Warm and energetic",
        primaryLightHex: "#F4693B",
        primaryDarkHex: "#FF8A5C",
        secondaryLightHex: "#F5A93F",
        secondaryDarkHex: "#FFC078",
        matchingIconId: "sunset"
    )

    /// Vibrant berry pink — bold, playful.
    static let berry = AppTheme(
        id: "berry",
        displayName: "Berry",
        tagline: "Bold and playful",
        primaryLightHex: "#D8417A",
        primaryDarkHex: "#EC6094",
        secondaryLightHex: "#A04AB5",
        secondaryDarkHex: "#BC75CC",
        matchingIconId: "berry"
    )

    /// True-dark minimalist — near-black accent for the monochrome lover
    /// (was "Graphite", a middling slate; v2.4 color pass committed it to
    /// real ink). Light mode is a cool near-black (#2C3038 — never pure
    /// #000, per the same warmth rule Things/Todoist follow) so filled
    /// CTAs read as the classic premium black-button look. Dark mode
    /// CANNOT be near-black (invisible against the near-black canvas) or
    /// near-white (every CTA draws white text on the primary), so it's a
    /// deep steel — which also fixes old Graphite's worst flaw: white
    /// text on its #A6ACB8 dark primary was ~2.3:1 contrast; #7E8694 is
    /// ~3.7:1. The persisted id stays "graphite" so existing users'
    /// saved theme keeps resolving.
    static let graphite = AppTheme(
        id: "graphite",
        displayName: "Ink",
        tagline: "True black minimalism",
        primaryLightHex: "#2C3038",
        primaryDarkHex: "#7E8694",
        secondaryLightHex: "#5A6170",
        secondaryDarkHex: "#A6ACB8",
        matchingIconId: "graphite"
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
        tagline: "Soft and dreamy",
        primaryLightHex: "#9580E5",
        primaryDarkHex: "#AC9AF0",
        secondaryLightHex: "#B59BE0",
        secondaryDarkHex: "#C8B4ED",
        matchingIconId: nil
    )

    /// Fresh teal-mint — crisp and vibrant without being loud.
    static let mint = AppTheme(
        id: "mint",
        displayName: "Mint",
        tagline: "Crisp and fresh",
        primaryLightHex: "#3DC0A0",
        primaryDarkHex: "#5BD0B5",
        secondaryLightHex: "#6BD0BB",
        secondaryDarkHex: "#82DCC8",
        matchingIconId: nil
    )

    /// Warm pastel peach — cozy, summery.
    static let peach = AppTheme(
        id: "peach",
        displayName: "Peach",
        tagline: "Cozy summer warmth",
        primaryLightHex: "#F58A60",
        primaryDarkHex: "#FFA383",
        secondaryLightHex: "#FFAA90",
        secondaryDarkHex: "#FFBFA8",
        matchingIconId: nil
    )

    /// Soft sky blue — airy and bright.
    static let sky = AppTheme(
        id: "sky",
        displayName: "Sky",
        tagline: "Airy and bright",
        primaryLightHex: "#5AAEE0",
        primaryDarkHex: "#78C0E8",
        secondaryLightHex: "#88C5E5",
        secondaryDarkHex: "#A2D2EE",
        matchingIconId: nil
    )

    /// Dusty rose — warm and romantic.
    static let rose = AppTheme(
        id: "rose",
        displayName: "Rose",
        tagline: "Warm dusty pink",
        primaryLightHex: "#E3819A",
        primaryDarkHex: "#ED9DB0",
        secondaryLightHex: "#EBA5B8",
        secondaryDarkHex: "#F0BBC8",
        matchingIconId: nil
    )

    /// Muted sage green — earthy, grounded, easy on the eyes.
    static let sage = AppTheme(
        id: "sage",
        displayName: "Sage",
        tagline: "Earthy and grounded",
        primaryLightHex: "#75A282",
        primaryDarkHex: "#8DB596",
        secondaryLightHex: "#95B59E",
        secondaryDarkHex: "#ABC4B0",
        matchingIconId: nil
    )

    /// The historical CashLens palette — saturated, confident accents.
    static let classics: [AppTheme] = [
        .mauve, .ocean, .forest, .sunset, .berry, .graphite
    ]

    /// Softer, friendlier palettes. Ordered so each pastel sits roughly
    /// under its classic counterpart in a 3-column grid (Mauve↔Lavender,
    /// Ocean↔Sky, etc.).
    static let pastels: [AppTheme] = [
        .lavender, .sky, .mint, .peach, .rose, .sage
    ]

    /// Ordered catalog: classics first, then pastels.
    static let all: [AppTheme] = classics + pastels

    /// Fallback if the persisted id can't be resolved.
    static let `default`: AppTheme = .mauve

    /// Lookup by id (used when restoring from `UserDefaults`).
    static func resolve(id: String?) -> AppTheme {
        guard let id else { return .default }
        return all.first { $0.id == id } ?? .default
    }
}
