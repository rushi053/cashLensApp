import SwiftUI

extension Color {
    // System colors
    static let systemBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
    static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let tertiarySystemGroupedBackground = Color(UIColor.tertiarySystemGroupedBackground)
    
    // System text colors
    static let label = Color(UIColor.label)
    static let secondaryLabel = Color(UIColor.secondaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)
    static let placeholderText = Color(UIColor.placeholderText)
    
    // System fill colors
    static let systemFill = Color(UIColor.systemFill)
    static let secondarySystemFill = Color(UIColor.secondarySystemFill)
    static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
    static let quaternarySystemFill = Color(UIColor.quaternarySystemFill)
    
    // Color palette structs to optimize memory usage.
    // Each color ships hand-tuned light + dark hex pairs so the saturation
    // reads identically across appearance modes. New additions follow the
    // same soft-pastel language (mid-saturation, ~70% luminance in light,
    // ~60% in dark) so the picker grid feels coherent.
    private struct LightColors {
        // Original 10
        static let lemonChiffon = Color(UIColor(red: 245/255, green: 215/255, blue: 70/255, alpha: 1.0))
        static let champagnePink = Color(UIColor(red: 255/255, green: 190/255, blue: 160/255, alpha: 1.0))
        static let teaRose = Color(UIColor(red: 255/255, green: 150/255, blue: 160/255, alpha: 1.0))
        static let pinkLavender = Color(UIColor(red: 235/255, green: 140/255, blue: 210/255, alpha: 1.0))
        static let mauve = Color(UIColor(red: 180/255, green: 140/255, blue: 240/255, alpha: 1.0))
        static let jordyBlue = Color(UIColor(red: 110/255, green: 150/255, blue: 255/255, alpha: 1.0))
        static let nonPhotoBlue = Color(UIColor(red: 100/255, green: 190/255, blue: 255/255, alpha: 1.0))
        static let electricBlue = Color(UIColor(red: 90/255, green: 210/255, blue: 255/255, alpha: 1.0))
        static let aquamarine = Color(UIColor(red: 100/255, green: 220/255, blue: 190/255, alpha: 1.0))
        static let celadon = Color(UIColor(red: 130/255, green: 225/255, blue: 140/255, alpha: 1.0))
        // 14 new — warm/neutral/cool family extensions
        static let coral = Color(UIColor(red: 255/255, green: 130/255, blue: 110/255, alpha: 1.0))
        static let apricot = Color(UIColor(red: 255/255, green: 175/255, blue: 105/255, alpha: 1.0))
        static let goldenrod = Color(UIColor(red: 245/255, green: 195/255, blue: 80/255, alpha: 1.0))
        static let honey = Color(UIColor(red: 240/255, green: 175/255, blue: 95/255, alpha: 1.0))
        static let mint = Color(UIColor(red: 130/255, green: 215/255, blue: 175/255, alpha: 1.0))
        static let sage = Color(UIColor(red: 160/255, green: 200/255, blue: 155/255, alpha: 1.0))
        static let forest = Color(UIColor(red: 95/255, green: 175/255, blue: 130/255, alpha: 1.0))
        static let seafoam = Color(UIColor(red: 130/255, green: 220/255, blue: 215/255, alpha: 1.0))
        static let ocean = Color(UIColor(red: 80/255, green: 165/255, blue: 200/255, alpha: 1.0))
        static let periwinkle = Color(UIColor(red: 155/255, green: 165/255, blue: 240/255, alpha: 1.0))
        static let lavender = Color(UIColor(red: 200/255, green: 175/255, blue: 240/255, alpha: 1.0))
        static let plum = Color(UIColor(red: 165/255, green: 115/255, blue: 195/255, alpha: 1.0))
        static let blush = Color(UIColor(red: 245/255, green: 175/255, blue: 195/255, alpha: 1.0))
        static let slate = Color(UIColor(red: 145/255, green: 160/255, blue: 180/255, alpha: 1.0))
    }
    
    private struct DarkColors {
        static let lemonChiffon = Color(UIColor(red: 230/255, green: 200/255, blue: 60/255, alpha: 1.0))
        static let champagnePink = Color(UIColor(red: 225/255, green: 165/255, blue: 135/255, alpha: 1.0))
        static let teaRose = Color(UIColor(red: 225/255, green: 125/255, blue: 130/255, alpha: 1.0))
        static let pinkLavender = Color(UIColor(red: 210/255, green: 120/255, blue: 190/255, alpha: 1.0))
        static let mauve = Color(UIColor(red: 170/255, green: 125/255, blue: 220/255, alpha: 1.0))
        static let jordyBlue = Color(UIColor(red: 120/255, green: 150/255, blue: 235/255, alpha: 1.0))
        static let nonPhotoBlue = Color(UIColor(red: 110/255, green: 190/255, blue: 235/255, alpha: 1.0))
        static let electricBlue = Color(UIColor(red: 100/255, green: 210/255, blue: 235/255, alpha: 1.0))
        static let aquamarine = Color(UIColor(red: 110/255, green: 220/255, blue: 190/255, alpha: 1.0))
        static let celadon = Color(UIColor(red: 140/255, green: 225/255, blue: 150/255, alpha: 1.0))
        // 14 new — slightly cooler / desaturated pairs for dark mode
        static let coral = Color(UIColor(red: 235/255, green: 115/255, blue: 95/255, alpha: 1.0))
        static let apricot = Color(UIColor(red: 230/255, green: 160/255, blue: 95/255, alpha: 1.0))
        static let goldenrod = Color(UIColor(red: 225/255, green: 180/255, blue: 75/255, alpha: 1.0))
        static let honey = Color(UIColor(red: 220/255, green: 160/255, blue: 85/255, alpha: 1.0))
        static let mint = Color(UIColor(red: 125/255, green: 210/255, blue: 175/255, alpha: 1.0))
        static let sage = Color(UIColor(red: 150/255, green: 195/255, blue: 150/255, alpha: 1.0))
        static let forest = Color(UIColor(red: 100/255, green: 175/255, blue: 130/255, alpha: 1.0))
        static let seafoam = Color(UIColor(red: 120/255, green: 215/255, blue: 215/255, alpha: 1.0))
        static let ocean = Color(UIColor(red: 90/255, green: 170/255, blue: 200/255, alpha: 1.0))
        static let periwinkle = Color(UIColor(red: 150/255, green: 165/255, blue: 230/255, alpha: 1.0))
        static let lavender = Color(UIColor(red: 195/255, green: 170/255, blue: 235/255, alpha: 1.0))
        static let plum = Color(UIColor(red: 165/255, green: 115/255, blue: 195/255, alpha: 1.0))
        static let blush = Color(UIColor(red: 235/255, green: 170/255, blue: 190/255, alpha: 1.0))
        static let slate = Color(UIColor(red: 150/255, green: 165/255, blue: 185/255, alpha: 1.0))
    }
    
    // Dynamic colors that adapt to light/dark mode - using optimized helper function
    private static func dynamicColor(light: @escaping () -> Color, dark: @escaping () -> Color) -> Color {
        return Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(dark()) : UIColor(light())
        })
    }
    
    // Dynamic category colors
    static let lemonChiffon = dynamicColor(light: { LightColors.lemonChiffon }, dark: { DarkColors.lemonChiffon })
    static let champagnePink = dynamicColor(light: { LightColors.champagnePink }, dark: { DarkColors.champagnePink })
    static let teaRose = dynamicColor(light: { LightColors.teaRose }, dark: { DarkColors.teaRose })
    static let pinkLavender = dynamicColor(light: { LightColors.pinkLavender }, dark: { DarkColors.pinkLavender })
    static let mauve = dynamicColor(light: { LightColors.mauve }, dark: { DarkColors.mauve })
    static let jordyBlue = dynamicColor(light: { LightColors.jordyBlue }, dark: { DarkColors.jordyBlue })
    static let nonPhotoBlue = dynamicColor(light: { LightColors.nonPhotoBlue }, dark: { DarkColors.nonPhotoBlue })
    static let electricBlue = dynamicColor(light: { LightColors.electricBlue }, dark: { DarkColors.electricBlue })
    static let aquamarine = dynamicColor(light: { LightColors.aquamarine }, dark: { DarkColors.aquamarine })
    static let celadon = dynamicColor(light: { LightColors.celadon }, dark: { DarkColors.celadon })
    // 14 new — exposed via the same dynamic helper so dark-mode contrast
    // is automatic everywhere `Color.<name>` is used.
    static let coral = dynamicColor(light: { LightColors.coral }, dark: { DarkColors.coral })
    static let apricot = dynamicColor(light: { LightColors.apricot }, dark: { DarkColors.apricot })
    static let goldenrod = dynamicColor(light: { LightColors.goldenrod }, dark: { DarkColors.goldenrod })
    static let honey = dynamicColor(light: { LightColors.honey }, dark: { DarkColors.honey })
    static let mint = dynamicColor(light: { LightColors.mint }, dark: { DarkColors.mint })
    static let sage = dynamicColor(light: { LightColors.sage }, dark: { DarkColors.sage })
    static let forest = dynamicColor(light: { LightColors.forest }, dark: { DarkColors.forest })
    static let seafoam = dynamicColor(light: { LightColors.seafoam }, dark: { DarkColors.seafoam })
    static let ocean = dynamicColor(light: { LightColors.ocean }, dark: { DarkColors.ocean })
    static let periwinkle = dynamicColor(light: { LightColors.periwinkle }, dark: { DarkColors.periwinkle })
    static let lavender = dynamicColor(light: { LightColors.lavender }, dark: { DarkColors.lavender })
    static let plum = dynamicColor(light: { LightColors.plum }, dark: { DarkColors.plum })
    static let blush = dynamicColor(light: { LightColors.blush }, dark: { DarkColors.blush })
    static let slate = dynamicColor(light: { LightColors.slate }, dark: { DarkColors.slate })
    
    // App theme colors
    //
    // Computed against `ThemeStore.shared.currentTheme` so that the user's
    // chosen accent theme cascades through every surface that reads these
    // tokens (tab bar tint, pills, FAB, charts, info badges, etc.).
    //
    // The `Color(UIColor { trait in ... })` form keeps light/dark adaptation
    // intact — each theme ships hand-tuned light/dark hex pairs that resolve
    // automatically when the user toggles appearance mode.
    //
    // `appAccent` stays anchored to the historical `teaRose` value because
    // it's used for warm-tinted callouts (refunds, accent secondaries) where
    // theme bleed would feel inconsistent.
    static var appPrimary: Color { ThemeStore.activeTheme.primaryColor }
    static var appSecondary: Color { ThemeStore.activeTheme.secondaryColor }
    static let appAccent = teaRose
    
    // Category colors mapping
    static func forCategory(_ category: String) -> Color {
        switch category.lowercased() {
        case "groceries": return lemonChiffon
        case "food": return champagnePink
        case "transportation": return nonPhotoBlue
        case "entertainment": return pinkLavender
        case "shopping": return teaRose
        case "utilities": return lemonChiffon
        case "health": return mauve
        case "education": return jordyBlue
        case "travel": return electricBlue
        case "other": return celadon
        case "lemonchiffon": return lemonChiffon
        case "champagnepink": return champagnePink
        case "tearose": return teaRose
        case "pinklavender": return pinkLavender
        case "mauve": return mauve
        case "jordyblue": return jordyBlue
        case "nonphotoblue": return nonPhotoBlue
        case "electricblue": return electricBlue
        case "aquamarine": return aquamarine
        case "celadon": return celadon
        // 14 new
        case "coral": return coral
        case "apricot": return apricot
        case "goldenrod": return goldenrod
        case "honey": return honey
        case "mint": return mint
        case "sage": return sage
        case "forest": return forest
        case "seafoam": return seafoam
        case "ocean": return ocean
        case "periwinkle": return periwinkle
        case "lavender": return lavender
        case "plum": return plum
        case "blush": return blush
        case "slate": return slate
        default: return appPrimary
        }
    }
    
    // Color utility functions
    static func darker(_ color: Color, by percentage: CGFloat = 0.2) -> Color {
        guard let uiColor = UIColor(color).cgColor.components else { return color }
        let r = max(uiColor[0] - percentage, 0)
        let g = max(uiColor[1] - percentage, 0)
        let b = max(uiColor[2] - percentage, 0)
        return Color(UIColor(red: r, green: g, blue: b, alpha: 1.0))
    }
    
    static func lighter(_ color: Color, by percentage: CGFloat = 0.2) -> Color {
        guard let uiColor = UIColor(color).cgColor.components else { return color }
        let r = min(uiColor[0] + percentage, 1.0)
        let g = min(uiColor[1] + percentage, 1.0)
        let b = min(uiColor[2] + percentage, 1.0)
        return Color(UIColor(red: r, green: g, blue: b, alpha: 1.0))
    }
}

// MARK: - UIColor hex parsing

extension UIColor {
    /// Tolerant hex initializer. Accepts `#RRGGBB`, `RRGGBB`, `#RRGGBBAA`,
    /// or `RRGGBBAA`. Returns `nil` for malformed input so callers can
    /// fall back to a sentinel color rather than crashing.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        if s.count == 6 {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8)  & 0xFF) / 255
            b = CGFloat( v        & 0xFF) / 255
            a = 1
        } else {
            r = CGFloat((v >> 24) & 0xFF) / 255
            g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8)  & 0xFF) / 255
            a = CGFloat( v        & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
