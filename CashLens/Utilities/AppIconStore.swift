import SwiftUI
import UIKit

/// Singleton store backing the user's active alternate app icon.
///
/// Wraps `UIApplication.setAlternateIconName(_:)` with a clean, async-friendly
/// API plus a published `currentIcon` so SwiftUI views can react. The
/// underlying UIKit call is somewhat finicky (must be on main, can fail with
/// `NSError`s, sometimes presents a system alert) so we centralize all of
/// that here.
@MainActor
final class AppIconStore: ObservableObject {

    static let shared = AppIconStore()

    @Published private(set) var currentIcon: AppIconOption

    private init() {
        // Source of truth: the OS's `alternateIconName` if set, else our
        // persisted id, else `.primary`. Keeping all three in sync handles
        // the edge case where the user changed icons on a different device
        // and CloudKit synced the UserDefaults key before the system applied
        // the change locally.
        let osName = UIApplication.shared.alternateIconName
        if let osName, let match = AppIconOption.all.first(where: { $0.alternateName == osName }) {
            self.currentIcon = match
        } else {
            let persistedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.activeAppIconId)
            self.currentIcon = AppIconOption.resolve(id: persistedId)
        }
    }

    /// Errors surfaced from `UIApplication.setAlternateIconName(_:)` so the
    /// caller can show a friendly toast without leaking UIKit internals.
    enum ApplyError: LocalizedError {
        case notSupported
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notSupported:
                return "Custom icons aren't supported on this device."
            case .failed(let message):
                return message
            }
        }
    }

    /// Apply the icon. Resolves on success, throws on failure. Persists the
    /// id only after the OS confirms the change so a failed apply doesn't
    /// leave a stale persisted value.
    func apply(_ icon: AppIconOption) async throws {
        guard UIApplication.shared.supportsAlternateIcons else {
            throw ApplyError.notSupported
        }
        guard icon.id != currentIcon.id else { return }

        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            currentIcon = icon
            if icon.isPrimary {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAppIconId)
            } else {
                UserDefaults.standard.set(icon.id, forKey: UserDefaultsKeys.activeAppIconId)
            }
            NotificationCenter.default.post(name: .appIconDidChange, object: nil)
        } catch {
            throw ApplyError.failed(error.localizedDescription)
        }
    }
}

extension Notification.Name {
    /// Posted on a successful icon swap so any background-stat tracking can
    /// observe (e.g., Pro engagement counters).
    static let appIconDidChange = Notification.Name("CashLens.appIconDidChange")
}
