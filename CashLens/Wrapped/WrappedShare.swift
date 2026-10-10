import SwiftUI
import UIKit

/// Instagram Stories sharing needs a Meta App ID.
///
/// PLACEHOLDER: paste your Meta App ID below to show the Instagram button.
/// Create the app at developers.facebook.com, add the Instagram product, and
/// leave this empty until you have a real ID. An invented ID will not work.
/// While this is empty, sharing uses the iOS share sheet only (including X).
enum WrappedShareConfig {
    static let metaAppID: String = ""

    static var isInstagramConfigured: Bool {
        !metaAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum WrappedCardRenderer {
    /// 360×640 points at scale 3 is 1080×1920 pixels.
    static let pointSize = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    @MainActor
    static func pngData(stats: WrappedStats, page: WrappedPageKind, showAmounts: Bool) -> Data? {
        let card = WrappedCardView(page: page, stats: stats, showAmounts: showAmounts, mode: .share)
            .frame(width: pointSize.width, height: pointSize.height)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .large)

        let renderer = ImageRenderer(content: card)
        renderer.scale = renderScale
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: pointSize.width, height: pointSize.height)
        return renderer.uiImage?.pngData()
    }

    @MainActor
    static func writePNG(stats: WrappedStats, page: WrappedPageKind, showAmounts: Bool) -> URL? {
        guard let data = pngData(stats: stats, page: page, showAmounts: showAmounts) else { return nil }
        let slug = page.rawValue
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CashLens-Wrapped-\(slug).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

enum SharePresenter {
    static func present(items: [Any]) {
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            let bounds = presenter.view.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.maxY - 80, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        guard var controller = window?.rootViewController else { return nil }
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }
}

enum InstagramStoriesSharer {
    /// Returns false when the placeholder App ID is empty, Instagram isn't
    /// installed, or the system refuses the URL. Callers should fall back
    /// to the share sheet.
    @discardableResult
    static func share(png: Data) -> Bool {
        let appID = WrappedShareConfig.metaAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty else { return false }
        guard
            let encoded = appID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "instagram-stories://share?source_application=\(encoded)"),
            UIApplication.shared.canOpenURL(url)
        else { return false }

        let item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": png
        ]
        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
        )
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
}
