//
//  WidgetTheme.swift
//  CashLensWidgets
//
//  Pure theme resolver for the widget extension.
//
//  The widget process can't link the main app's `ThemeStore` (it lives
//  inside the main bundle and depends on `@MainActor` Combine state
//  the widget process doesn't have). Instead we duplicate the canonical
//  light/dark hex pairs here — the catalog is small and stable.
//
//  If the in-app theme catalog ever grows or rebrands, update both
//  this file and `CashLens/Models/AppTheme.swift` together (the
//  comments in each cross-reference the other).
//

import SwiftUI

/// One renderable accent theme inside the widget extension.
struct WidgetTheme: Sendable {
    let id: String
    let primaryLightHex: String
    let primaryDarkHex: String
    let secondaryLightHex: String
    let secondaryDarkHex: String

    /// Dynamic primary that adapts to the widget's `colorScheme` env.
    func primary(for scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? primaryDarkHex : primaryLightHex)
            ?? Color(hex: WidgetTheme.mauve.primaryLightHex)
            ?? .purple
    }

    /// Dynamic secondary that adapts to the widget's `colorScheme` env.
    func secondary(for scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? secondaryDarkHex : secondaryLightHex)
            ?? Color(hex: WidgetTheme.mauve.secondaryLightHex)
            ?? .blue
    }

    // MARK: - Catalog (kept in sync with AppTheme)

    static let mauve = WidgetTheme(
        id: "mauve",
        primaryLightHex: "#B48CF0",
        primaryDarkHex: "#AA7DDC",
        secondaryLightHex: "#6E96FF",
        secondaryDarkHex: "#7896EB"
    )

    static let ocean = WidgetTheme(
        id: "ocean",
        primaryLightHex: "#3D8BF5",
        primaryDarkHex: "#5DA0FA",
        secondaryLightHex: "#2EBFD8",
        secondaryDarkHex: "#5AD3E6"
    )

    static let forest = WidgetTheme(
        id: "forest",
        primaryLightHex: "#2FA060",
        primaryDarkHex: "#56C589",
        secondaryLightHex: "#7DBE3A",
        secondaryDarkHex: "#A8D560"
    )

    static let sunset = WidgetTheme(
        id: "sunset",
        primaryLightHex: "#EE6B2D",
        primaryDarkHex: "#FF8B55",
        secondaryLightHex: "#E89740",
        secondaryDarkHex: "#F5B373"
    )

    static let berry = WidgetTheme(
        id: "berry",
        primaryLightHex: "#D8417A",
        primaryDarkHex: "#EC6094",
        secondaryLightHex: "#A04AB5",
        secondaryDarkHex: "#BC75CC"
    )

    static let graphite = WidgetTheme(
        id: "graphite",
        primaryLightHex: "#4D5563",
        primaryDarkHex: "#A6ACB8",
        secondaryLightHex: "#7B828F",
        secondaryDarkHex: "#C2C8D2"
    )

    // MARK: - Pastels (kept in sync with AppTheme.swift)

    static let lavender = WidgetTheme(
        id: "lavender",
        primaryLightHex: "#9580E5",
        primaryDarkHex: "#AC9AF0",
        secondaryLightHex: "#B59BE0",
        secondaryDarkHex: "#C8B4ED"
    )

    static let mint = WidgetTheme(
        id: "mint",
        primaryLightHex: "#3DC0A0",
        primaryDarkHex: "#5BD0B5",
        secondaryLightHex: "#6BD0BB",
        secondaryDarkHex: "#82DCC8"
    )

    static let peach = WidgetTheme(
        id: "peach",
        primaryLightHex: "#F58A60",
        primaryDarkHex: "#FFA383",
        secondaryLightHex: "#FFAA90",
        secondaryDarkHex: "#FFBFA8"
    )

    static let sky = WidgetTheme(
        id: "sky",
        primaryLightHex: "#5AAEE0",
        primaryDarkHex: "#78C0E8",
        secondaryLightHex: "#88C5E5",
        secondaryDarkHex: "#A2D2EE"
    )

    static let rose = WidgetTheme(
        id: "rose",
        primaryLightHex: "#E3819A",
        primaryDarkHex: "#ED9DB0",
        secondaryLightHex: "#EBA5B8",
        secondaryDarkHex: "#F0BBC8"
    )

    static let sage = WidgetTheme(
        id: "sage",
        primaryLightHex: "#75A282",
        primaryDarkHex: "#8DB596",
        secondaryLightHex: "#95B59E",
        secondaryDarkHex: "#ABC4B0"
    )

    static let all: [WidgetTheme] = [
        .mauve, .ocean, .forest, .sunset, .berry, .graphite,
        .lavender, .sky, .mint, .peach, .rose, .sage
    ]

    /// Look up a theme by id, falling back to mauve if the id is
    /// unknown (e.g. a snapshot from a future app version with a
    /// theme this widget binary doesn't know about yet).
    static func resolve(id: String) -> WidgetTheme {
        all.first { $0.id == id } ?? mauve
    }
}

// MARK: - Color hex helper (widget extension)

extension Color {
    /// Tolerant `#RRGGBB` / `#RRGGBBAA` initializer. Returns `nil` for
    /// malformed input so callers can fall back to a sentinel rather
    /// than crashing the widget process.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8)  & 0xFF) / 255
            b = Double( v        & 0xFF) / 255
            a = 1
        } else {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8)  & 0xFF) / 255
            a = Double( v        & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
