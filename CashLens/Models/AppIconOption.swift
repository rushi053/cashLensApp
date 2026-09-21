import SwiftUI

/// User-selectable alternate app icon. Pro feature.
///
/// `alternateName` matches the asset-catalog appiconset name in
/// `Assets.xcassets`. `nil` means the primary icon (`AppIcon`) — required by
/// `UIApplication.setAlternateIconName(_:)` to clear back to the default.
///
/// `previewAssetName` points at a **regular imageset** (`IconPreview-*`),
/// not the appiconset. iOS 18+ made `UIImage(named:)` return `nil` for
/// anything inside an `.appiconset` (Xcode 16 release notes / FB14052579),
/// so the picker and Appearance studio need a parallel imageset copy to
/// render the tile. The PNGs are the same art as the app icons; regenerating
/// via `Scripts/generate_app_icons.swift` refreshes both.
struct AppIconOption: Identifiable, Hashable, Sendable {

    let id: String
    let displayName: String

    /// Pass to `UIApplication.setAlternateIconName(_:)`. `nil` resets to the
    /// primary icon configured in the asset catalog.
    let alternateName: String?

    /// Asset-catalog **imageset** name used for in-app preview tiles.
    let previewAssetName: String

    var isPrimary: Bool { alternateName == nil }

    // MARK: - Catalog

    static let primary = AppIconOption(
        id: "primary",
        displayName: "Mauve",
        alternateName: nil,
        previewAssetName: "IconPreview-Mauve"
    )

    static let ocean = AppIconOption(
        id: "ocean",
        displayName: "Ocean",
        alternateName: "AppIcon-Ocean",
        previewAssetName: "IconPreview-Ocean"
    )

    static let forest = AppIconOption(
        id: "forest",
        displayName: "Forest",
        alternateName: "AppIcon-Forest",
        previewAssetName: "IconPreview-Forest"
    )

    static let sunset = AppIconOption(
        id: "sunset",
        displayName: "Sunset",
        alternateName: "AppIcon-Sunset",
        previewAssetName: "IconPreview-Sunset"
    )

    static let berry = AppIconOption(
        id: "berry",
        displayName: "Berry",
        alternateName: "AppIcon-Berry",
        previewAssetName: "IconPreview-Berry"
    )

    /// Matches the Ink theme (`AppTheme.graphite` — persisted id kept
    /// for existing users). Near-black + cream coin, same swatch as
    /// `primaryLightHex` `#2C3038`.
    static let graphite = AppIconOption(
        id: "graphite",
        displayName: "Ink",
        alternateName: "AppIcon-Graphite",
        previewAssetName: "IconPreview-Graphite"
    )

    static let monoLight = AppIconOption(
        id: "monoLight",
        displayName: "Mono Light",
        alternateName: "AppIcon-MonoLight",
        previewAssetName: "IconPreview-MonoLight"
    )

    static let monoDark = AppIconOption(
        id: "monoDark",
        displayName: "Mono Dark",
        alternateName: "AppIcon-MonoDark",
        previewAssetName: "IconPreview-MonoDark"
    )

    /// Display order in the picker grid.
    static let all: [AppIconOption] = [
        .primary, .ocean, .forest, .sunset, .berry, .graphite, .monoLight, .monoDark
    ]

    /// Lookup by id (used when restoring from `UserDefaults`).
    static func resolve(id: String?) -> AppIconOption {
        guard let id else { return .primary }
        return all.first { $0.id == id } ?? .primary
    }
}
