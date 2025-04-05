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
    
    // Color palette structs to optimize memory usage
    private struct LightColors {
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
    
    // App theme colors
    static let appPrimary = mauve
    static let appSecondary = jordyBlue
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