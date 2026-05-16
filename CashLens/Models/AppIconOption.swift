import SwiftUI

/// User-selectable alternate app icon. Pro feature.
///
/// `alternateName` matches the asset-catalog appiconset name in
/// `Assets.xcassets`. `nil` means the primary icon (`AppIcon`) — required by
/// `UIApplication.setAlternateIconName(_:)` to clear back to the default.
///
/// `previewAssetName` is the asset-catalog name used by the in-app picker to
/// render a preview tile. Because the project is built with
/// `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`, every appiconset
/// is also addressable via `UIImage(named:)` so we don't need parallel
/// imagesets.
struct AppIconOption: Identifiable, Hashable, Sendable {

    let id: String
    let displayName: String

    /// Pass to `UIApplication.setAlternateIconName(_:)`. `nil` resets to the
    /// primary icon configured in the asset catalog.
    let alternateName: String?

    /// Asset-catalog image name used for the picker preview tile.
    let previewAssetName: String

    var isPrimary: Bool { alternateName == nil }

    // MARK: - Catalog

    static let primary = AppIconOption(
        id: "primary",
        displayName: "Mauve",
        alternateName: nil,
        previewAssetName: "AppIcon"
    )

    static let ocean = AppIconOption(
        id: "ocean",
        displayName: "Ocean",
        alternateName: "AppIcon-Ocean",
        previewAssetName: "AppIcon-Ocean"
    )

    static let forest = AppIconOption(
        id: "forest",
        displayName: "Forest",
        alternateName: "AppIcon-Forest",
        previewAssetName: "AppIcon-Forest"
    )

    static let sunset = AppIconOption(
        id: "sunset",
        displayName: "Sunset",
        alternateName: "AppIcon-Sunset",
        previewAssetName: "AppIcon-Sunset"
    )

    static let berry = AppIconOption(
        id: "berry",
        displayName: "Berry",
        alternateName: "AppIcon-Berry",
        previewAssetName: "AppIcon-Berry"
    )

    static let graphite = AppIconOption(
        id: "graphite",
        displayName: "Graphite",
        alternateName: "AppIcon-Graphite",
        previewAssetName: "AppIcon-Graphite"
    )

    static let monoLight = AppIconOption(
        id: "monoLight",
        displayName: "Mono Light",
        alternateName: "AppIcon-MonoLight",
        previewAssetName: "AppIcon-MonoLight"
    )

    static let monoDark = AppIconOption(
        id: "monoDark",
        displayName: "Mono Dark",
        alternateName: "AppIcon-MonoDark",
        previewAssetName: "AppIcon-MonoDark"
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
