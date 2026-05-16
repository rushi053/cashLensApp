import SwiftUI
import Combine

/// Singleton store backing the user's active accent theme.
///
/// `Color.appPrimary` and `Color.appSecondary` resolve their dynamic UIColors
/// against `ThemeStore.shared.currentTheme` at render time, so applying a new
/// theme just requires (a) persisting the choice and (b) telling SwiftUI to
/// redraw any views that should reflect the new color.
///
/// Strategy:
/// 1. `currentTheme` is `@Published` — any view that observes the store
///    re-renders when the value changes. Inject as `@StateObject` at the app
///    root and apply `.id(themeStore.currentTheme.id)` on the top-level
///    container so SwiftUI fully rebuilds the tree on theme change. This
///    keeps the implementation simple — no surgery on ~150 `Color.appPrimary`
///    call sites required.
/// 2. The `applyTheme(_:)` method also forces UIKit to re-resolve cached
///    dynamic colors via the well-known `overrideUserInterfaceStyle` toggle
///    trick, wrapped in a soft cross-dissolve so the transition feels
///    intentional rather than glitchy.
@MainActor
final class ThemeStore: ObservableObject {

    static let shared = ThemeStore()

    /// Published mirror of `_activeTheme` for SwiftUI views that observe the
    /// store. Reads here are MainActor-isolated and safe.
    @Published private(set) var currentTheme: AppTheme

    /// Thread-safe snapshot of the active theme. UIKit dynamic-color closures
    /// (used by `Color.appPrimary` / `Color.appSecondary`) may resolve off the
    /// main thread, so the lookup MUST be readable from any isolation context.
    /// `nonisolated(unsafe)` is sound here because writes only happen on the
    /// main actor inside `applyTheme(_:)`, and reads always observe a fully
    /// constructed `AppTheme` value (immutable struct).
    nonisolated(unsafe) private static var _activeTheme: AppTheme = AppTheme.default

    private init() {
        let id = UserDefaults.standard.string(forKey: UserDefaultsKeys.activeThemeId)
        let resolved = AppTheme.resolve(id: id)
        self.currentTheme = resolved
        ThemeStore._activeTheme = resolved
    }

    /// Read the active theme from any thread / isolation context. Used by the
    /// dynamic `Color.appPrimary` / `Color.appSecondary` resolvers.
    nonisolated static var activeTheme: AppTheme { _activeTheme }

    /// Switch to a new theme. Persists immediately, then publishes
    /// `objectWillChange` (via the `currentTheme` `@Published` setter) so
    /// SwiftUI views observing the store re-render. Also broadcasts
    /// `.themeDidChange` so UIKit-backed chrome (e.g. the legacy `UITabBar`
    /// appearance proxy) can re-apply its tint colors — UIKit's appearance
    /// system caches resolved colors and won't pick up a non-trait theme
    /// change without an explicit nudge.
    ///
    /// Why no `overrideUserInterfaceStyle` toggle anymore: the previous
    /// implementation flipped the window's interface style and back inside
    /// a `UIView.transition`, intending to invalidate UIKit's dynamic-color
    /// cache. In practice the synchronous double-flip got coalesced into a
    /// no-op (no net trait change) and SwiftUI views silently kept the old
    /// color. The new path uses an explicit per-view rebuild via
    /// `.id(themeStore.currentTheme.id)` on each tab's root content (see
    /// `MainTabView`), which is deterministic.
    func applyTheme(_ theme: AppTheme) {
        guard theme.id != currentTheme.id else { return }
        currentTheme = theme
        ThemeStore._activeTheme = theme
        UserDefaults.standard.set(theme.id, forKey: UserDefaultsKeys.activeThemeId)
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }
}

extension Notification.Name {
    /// Posted when the user picks a new accent theme. Listeners only need to
    /// trigger a redraw — the new color resolves automatically through
    /// `ThemeStore.shared.currentTheme`.
    static let themeDidChange = Notification.Name("CashLens.themeDidChange")
}
