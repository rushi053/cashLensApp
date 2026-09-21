import Foundation
import SwiftUI
import LocalAuthentication

/// App-wide Face ID / Touch ID / passcode lock.
///
/// **Free feature, deliberately.** CashLens' brand is "your money
/// stays your business" — charging for the lock would undercut the
/// one promise the app is built on, so nothing here checks
/// `ProManager`.
///
/// **State machine.** Two independent published flags drive the
/// overlay mounted at the root of `CashLensApp`:
///
///   • `isLocked` — authentication is *required* before the app is
///     usable. Set on cold launch (when enabled) and when returning
///     from a real backgrounding whose duration exceeded the grace
///     window. Cleared only by a successful `LAContext` evaluation.
///   • `isCoverVisible` — the overlay should be on screen. True
///     whenever `isLocked`, and also while the scene is merely
///     *inactive* (app switcher, notification shade) so the switcher
///     snapshot never shows amounts. Inactive alone never sets
///     `isLocked`.
///
/// **The classic infinite-relock bug.** Evaluating `LAContext` makes
/// the app inactive (the system Face ID sheet takes focus), and a
/// naive "lock on resign-active" implementation re-locks the moment
/// the user authenticates — forever. Three guards prevent it here:
/// only `.background` (never `.inactive`) records a backgrounding,
/// `isAuthenticating` suppresses phase handling entirely while the
/// system prompt owns the screen, and the auto-prompt fires at most
/// once per lock (`hasAutoPromptedSinceLock`) so a cancel can't spin
/// into an endless prompt loop — the overlay's button re-triggers.
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    // MARK: - Grace period

    /// How long the app may sit in the background before re-auth is
    /// required. Raw value = seconds, persisted directly.
    enum GracePeriod: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneMinute:   return "After 1 minute"
            case .fiveMinutes: return "After 5 minutes"
            }
        }
    }

    // MARK: - Published state

    /// Master switch, persisted. Enabling requires a successful
    /// authentication first (see `enableAfterAuthentication`) so a
    /// user without enrolled biometrics *and* without a passcode can
    /// never lock themselves out.
    @Published private(set) var isEnabled: Bool

    /// Authentication required before the app is usable.
    @Published private(set) var isLocked: Bool

    /// The root overlay should be on screen (lock screen or privacy
    /// cover for the app switcher).
    @Published private(set) var isCoverVisible: Bool

    /// True while a system `LAContext` prompt owns the screen. The
    /// prompt makes the scene inactive; this flag keeps that
    /// self-inflicted phase change from being treated as the user
    /// leaving the app.
    @Published private(set) var isAuthenticating = false

    @Published var gracePeriod: GracePeriod {
        didSet {
            UserDefaults.standard.set(gracePeriod.rawValue, forKey: UserDefaultsKeys.appLockGraceSeconds)
        }
    }

    // MARK: - Private state

    private var isSceneActive = true
    /// Auto-prompt fires once per lock; after a cancel the user
    /// re-triggers via the overlay button instead of being trapped
    /// in an endless system-prompt loop.
    private var hasAutoPromptedSinceLock = false

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: UserDefaultsKeys.appLockEnabled)
        let grace = GracePeriod(rawValue: defaults.integer(forKey: UserDefaultsKeys.appLockGraceSeconds)) ?? .immediately

        isEnabled = enabled
        gracePeriod = grace

        // Cold launch: lock unless the persisted background timestamp
        // proves we're still inside the grace window (covers the
        // "iOS quietly terminated the app 20 seconds ago" case where
        // an immediate re-prompt would feel broken to the user).
        let shouldLock: Bool
        if enabled {
            if grace != .immediately,
               let backgroundedAt = defaults.object(forKey: UserDefaultsKeys.appLockLastBackgroundedAt) as? Date,
               Date().timeIntervalSince(backgroundedAt) < TimeInterval(grace.rawValue) {
                shouldLock = false
            } else {
                shouldLock = true
            }
        } else {
            shouldLock = false
        }
        isLocked = shouldLock
        isCoverVisible = shouldLock
    }

    // MARK: - Scene phase

    /// Root-level scene phase hook — the only input the lock reacts to.
    func handleScenePhase(_ phase: ScenePhase) {
        // The system auth sheet resigns our scene; none of that is
        // real user navigation. Ignore everything until the prompt
        // returns its verdict.
        guard !isAuthenticating else { return }

        switch phase {
        case .active:
            isSceneActive = true
            lockIfGraceExpired()
            refreshCover()
            autoPromptIfNeeded()
        case .inactive:
            // Cover the switcher snapshot, but a brief flicker
            // (notification shade, share sheet) must NOT require
            // re-auth — so no timestamp, no lock.
            isSceneActive = false
            refreshCover()
        case .background:
            isSceneActive = false
            if isEnabled {
                UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.appLockLastBackgroundedAt)
                if gracePeriod == .immediately {
                    lock()
                }
            }
            refreshCover()
        @unknown default:
            break
        }
    }

    /// Returning to the foreground: require re-auth only when a real
    /// backgrounding happened and its duration exceeded the grace
    /// window. (`.immediately` already locked on the way out.)
    private func lockIfGraceExpired() {
        guard isEnabled, !isLocked, gracePeriod != .immediately else { return }
        guard let backgroundedAt = UserDefaults.standard.object(forKey: UserDefaultsKeys.appLockLastBackgroundedAt) as? Date else { return }
        if Date().timeIntervalSince(backgroundedAt) >= TimeInterval(gracePeriod.rawValue) {
            lock()
        }
    }

    private func lock() {
        guard isEnabled else { return }
        isLocked = true
        hasAutoPromptedSinceLock = false
        refreshCover()
        // A fresh backgrounding stamp shouldn't survive the lock — it
        // has served its purpose.
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.appLockLastBackgroundedAt)
    }

    private func refreshCover() {
        let visible = isLocked || (isEnabled && !isSceneActive)
        guard isCoverVisible != visible else { return }
        if visible {
            // Show instantly — the whole point is that the app-switcher
            // snapshot never catches financial data mid-fade.
            isCoverVisible = true
        } else {
            withAnimation(Theme.Motion.snappy) {
                isCoverVisible = false
            }
        }
    }

    // MARK: - Unlocking

    /// Auto-trigger from the overlay's appear / foreground return.
    /// At most once per lock — the overlay button handles retries.
    func autoPromptIfNeeded() {
        guard isLocked, !hasAutoPromptedSinceLock else { return }
        hasAutoPromptedSinceLock = true
        requestUnlock()
    }

    /// Kick off a system authentication to clear the lock. Safe to
    /// call repeatedly — re-entrant calls while a prompt is up are
    /// dropped.
    func requestUnlock() {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let ok = await Self.evaluate(reason: "Unlock CashLens to see your expenses.")
            isAuthenticating = false
            if ok {
                HapticManager.shared.success()
                isLocked = false
                refreshCover()
                // Release anything that deferred itself while locked
                // (deep-link routes, win-back evaluation, …) so those
                // surfaces present *after* the lock screen clears —
                // never floating above it.
                NotificationCenter.default.post(name: .appDidUnlock, object: nil)
            }
        }
    }

    // MARK: - Enable / disable

    /// Turn the lock on — but only after one successful
    /// authentication, so a device with no passcode and no enrolled
    /// biometrics can never end up permanently locked out.
    /// Returns whether enabling succeeded.
    @discardableResult
    func enableAfterAuthentication() async -> Bool {
        guard !isEnabled else { return true }
        isAuthenticating = true
        let ok = await Self.evaluate(reason: "Confirm it's you to turn on App Lock.")
        isAuthenticating = false
        guard ok else { return false }

        isEnabled = true
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.appLockEnabled)
        HapticManager.shared.success()
        return true
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        isLocked = false
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.appLockEnabled)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.appLockLastBackgroundedAt)
        refreshCover()
    }

    // MARK: - LocalAuthentication plumbing

    /// One evaluation with a fresh context. `.deviceOwnerAuthentication`
    /// = biometrics when available, with the device passcode as the
    /// built-in fallback — exactly the behavior we promise in the
    /// settings copy.
    private static func evaluate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set at all — nothing to authenticate with.
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// Resolved biometry on this device — drives naming everywhere
    /// ("Face ID" vs "Touch ID" vs "Optic ID" vs plain "Passcode").
    /// `canEvaluatePolicy` must run before `biometryType` is valid.
    static var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// User-facing name of the unlock method for settings copy and
    /// the lock screen button.
    static var unlockMethodName: String {
        switch biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "Passcode"
        }
    }

    /// SF Symbol matching the unlock method.
    static var unlockMethodSymbol: String {
        switch biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default:       return "lock.fill"
        }
    }
}
