import Foundation

/// One-stop shop for surfacing Core Data save failures to the user.
///
/// **Why this exists.** The pre-launch audit flagged that every save
/// site in the view models swallows errors with a `print` and the UI
/// happily dismisses sheets / shows "saved" feedback regardless. In a
/// finance app, the worst possible bug is a silent save failure: the
/// user thinks their $200 expense logged when it didn't, or their
/// budget cap update stuck when it didn't. Hours later they discover
/// stale data and lose trust.
///
/// **The contract.** Every `do { try context.save() } catch` site
/// posts via `SaveErrorReporter.report(operation:error:)`. A view
/// modifier mounted at `MainTabView` listens on
/// `Notification.Name.saveErrorOccurred` and renders a non-blocking
/// banner over the tab bar. The user sees what failed, can dismiss
/// manually or wait the auto-dismiss out, and crucially knows their
/// last action did **not** persist.
///
/// **Why notifications instead of an `@Published` coordinator.**
/// Save sites live across multiple view models (`ExpenseViewModel`,
/// `SubscriptionViewModel`, `CategoryViewModel`) and a few utility
/// classes. Routing through `NotificationCenter` keeps each view
/// model from depending on a shared coordinator, matches the
/// codebase's existing notification patterns
/// (`.currencyDidChange`, `.backupImportDidComplete`,
/// `.themeDidChange`), and lets us add new save sites without
/// touching central plumbing.
enum SaveErrorReporter {

    /// Post a save-failure notification + console log. Always safe
    /// to call from any thread; the publisher inside
    /// `SaveErrorBannerHost` hops to the main actor before touching
    /// view state.
    ///
    /// - Parameters:
    ///   - operation: Plain-English present participle describing
    ///     what the user was trying to do — *"saving expense"*,
    ///     *"deleting subscription"*. Surfaces in the banner copy
    ///     ("Couldn't finish *saving expense*"). Keep it short.
    ///   - error: The underlying `Error` from the failing call.
    ///     Logged in full for debugging; only its localized
    ///     description is shown to the user.
    static func report(operation: String, error: Error) {
        // Console log mirrors the previous `print` lines so existing
        // debugging muscle memory still works. Prefixed for grep.
        print("⚠️ SaveError [\(operation)]: \(error.localizedDescription)")

        let payload = SaveErrorPayload(
            operation: operation,
            message: error.localizedDescription
        )
        // `object: payload` so the listener can read all fields in
        // one cast. We don't use `userInfo` because that would force
        // string keys and lossy casts back to typed values.
        NotificationCenter.default.post(
            name: .saveErrorOccurred,
            object: payload
        )
    }
}

/// Value type carried on `Notification.Name.saveErrorOccurred`.
/// Sendable because the listener may receive it on any thread before
/// hopping to the main actor.
struct SaveErrorPayload: Sendable {
    /// User-facing description of what was being attempted.
    /// Example: "saving expense", "deleting subscription".
    let operation: String

    /// Localized error message to surface in the banner subtitle.
    let message: String

    /// Wall-clock timestamp used by the banner host's debounce —
    /// repeated identical errors fired within the dedup window
    /// only present once.
    let timestamp: Date = Date()
}

extension Notification.Name {
    /// Fired by `SaveErrorReporter.report(...)` whenever a Core
    /// Data save (or equivalent persist operation) throws. The
    /// notification's `object` is a `SaveErrorPayload`.
    static let saveErrorOccurred = Notification.Name("saveErrorOccurred")
}
