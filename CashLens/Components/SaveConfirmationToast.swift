import SwiftUI

/// Success counterpart to `SaveErrorReporter` / `SaveErrorBanner`.
///
/// **Why this exists.** Saving an expense used to just dismiss the
/// sheet — no acknowledgment that the action landed. This posts a
/// lightweight confirmation ("Added ₹450 to Food") that renders as a
/// small floating capsule on the presenting view *after* the sheet
/// dismisses, so the confirmation never slows the dismissal itself.
///
/// **The contract.** Save sites call
/// `SaveConfirmationReporter.report(message:)` right after a
/// successful save. A host modifier mounted at `MainTabView`
/// (`.saveConfirmationToastHost()`, alongside `.saveErrorBannerHost()`)
/// listens and renders the toast. Same NotificationCenter routing as
/// the error banner so no view model grows a UI dependency.
enum SaveConfirmationReporter {

    /// Post a save-confirmation notification. Safe from any thread;
    /// the host hops to the main actor before touching view state.
    ///
    /// - Parameter message: Short, user-facing summary of what was
    ///   saved — *"Added ₹450 to Food"*, *"Updated ₹450 · Food"*.
    static func report(message: String) {
        NotificationCenter.default.post(
            name: .saveConfirmationOccurred,
            object: SaveConfirmationPayload(message: message)
        )
    }
}

/// Value type carried on `Notification.Name.saveConfirmationOccurred`.
struct SaveConfirmationPayload: Sendable {
    let message: String
    /// Drives the host's animation identity so back-to-back saves
    /// re-trigger the transition instead of silently swapping text.
    let timestamp: Date = Date()
}

extension Notification.Name {
    /// Fired by `SaveConfirmationReporter.report(...)` after a
    /// successful expense save. The `object` is a
    /// `SaveConfirmationPayload`.
    static let saveConfirmationOccurred = Notification.Name("saveConfirmationOccurred")
}

// MARK: - Toast view

/// Compact floating capsule: green check in a soft well + one-line
/// message. Matches the design language of `SaveErrorBanner` (material
/// fill, hairline border, soft elevation) but reads as calm success —
/// no red, no dismiss affordance, short auto-dismiss.
struct SaveConfirmationToast: View {
    let payload: SaveConfirmationPayload

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
            }

            Text(payload.message)
                .font(Theme.Typography.rowTitle)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: Theme.Stroke.hairline)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Toast host

/// Listens for `.saveConfirmationOccurred` and floats a
/// `SaveConfirmationToast` above the host view's bottom edge —
/// mounted at `MainTabView` root next to `SaveErrorBannerHost` so the
/// toast appears over the presenting screen as the save sheet slides
/// away.
struct SaveConfirmationToastHost: ViewModifier {

    @State private var current: SaveConfirmationPayload? = nil
    @State private var dismissTask: Task<Void, Never>? = nil

    /// Short-lived on purpose: the toast is an acknowledgment, not an
    /// alert. Long enough to read one line after the sheet's ~0.3s
    /// dismissal animation, short enough to never feel like clutter.
    private let autoDismissAfter: TimeInterval = 2.2

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let current = current {
                    SaveConfirmationToast(payload: current)
                        // Matches SaveErrorBanner's lift above both the
                        // floating Liquid Glass tab bar (iOS 26) and the
                        // legacy custom tab bar.
                        .padding(.bottom, 84)
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                        .zIndex(999)
                }
            }
            .animation(Theme.Motion.tap, value: current?.timestamp)
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .saveConfirmationOccurred)
                    .receive(on: DispatchQueue.main)
            ) { note in
                guard let payload = note.object as? SaveConfirmationPayload else { return }
                current = payload
                scheduleAutoDismiss()
            }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(Theme.Motion.snappy) {
                    current = nil
                }
            }
        }
    }
}

extension View {
    /// Mount the save-confirmation toast host at the app root.
    /// Listens for `Notification.Name.saveConfirmationOccurred` and
    /// renders a floating capsule above the bottom safe area.
    func saveConfirmationToastHost() -> some View {
        modifier(SaveConfirmationToastHost())
    }
}
