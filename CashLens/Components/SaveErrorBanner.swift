import SwiftUI

/// Non-blocking error banner that surfaces Core Data save failures.
/// Slides up from the bottom safe area, sits above the floating tab
/// bar, auto-dismisses after a few seconds, and can be tapped (or
/// the X) to dismiss early.
///
/// Mounted at the `MainTabView` root via `.saveErrorBannerHost()`
/// so it floats above the entire app, including modal sheets and
/// destination views.
struct SaveErrorBanner: View {
    let payload: SaveErrorPayload
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            // Warning glyph in a soft red well — high enough
            // contrast to read at-a-glance, soft enough not to look
            // like a fatal-error modal.
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Title leans on the operation string so the user
                // immediately knows which action failed.
                Text("Couldn't finish \(payload.operation)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(payload.message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            Button {
                HapticManager.shared.lightTap()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
        )
        // Subtle elevation matching the elevated-card design system
        // so the banner reads as floating, not pasted on.
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap the X to dismiss")
    }
}

// MARK: - Banner host

/// View modifier that listens for `.saveErrorOccurred` notifications
/// and renders a `SaveErrorBanner` above the host view's bottom edge.
///
/// **Where it sits.** Attached to `MainTabView` (covers both the
/// iOS 26 modern tab bar and the legacy custom tab bar paths).
/// Renders via `.overlay(alignment: .bottom)` so it floats above
/// the floating tab bar without disturbing layout.
///
/// **Dedup.** The audit specifically warned about background sweeps
/// (currency sync, orphan cleanup) potentially producing repeated
/// failures. We suppress identical (operation + message) errors
/// fired within `dedupWindow` of the last presentation so the
/// user doesn't see the same banner re-fire while reading it.
///
/// **Auto-dismiss.** `autoDismissAfter` seconds. Restarts on every
/// new error so the user always gets a fair read of the latest
/// banner content.
struct SaveErrorBannerHost: ViewModifier {

    @State private var current: SaveErrorPayload? = nil
    @State private var lastShown: SaveErrorPayload? = nil
    @State private var dismissTask: Task<Void, Never>? = nil

    /// Time after presentation before the banner auto-dismisses.
    /// 6 seconds is the iOS Human Interface Guidelines default for
    /// non-critical informational alerts and tested well — long
    /// enough for two-line messages, short enough not to obscure
    /// the screen if the user is mid-task.
    private let autoDismissAfter: TimeInterval = 6

    /// If a duplicate error fires within this window of the
    /// previous one, suppress it. Mainly defends against currency-
    /// sync sweeps that fire on every foreground transition.
    private let dedupWindow: TimeInterval = 2

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let current = current {
                    SaveErrorBanner(payload: current) {
                        dismissCurrent()
                    }
                    // Padding lifts the banner above the floating
                    // Liquid Glass tab bar (iOS 26) and the legacy
                    // custom tab bar. Roughly matches the FAB
                    // bottom inset in `MainTabView.modernTabView`.
                    .padding(.bottom, 84)
                    .transition(
                        .move(edge: .bottom).combined(with: .opacity)
                    )
                    .zIndex(1000)
                }
            }
            .animation(Theme.Motion.snappy, value: current?.timestamp)
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .saveErrorOccurred)
                    .receive(on: DispatchQueue.main)
            ) { note in
                guard let payload = note.object as? SaveErrorPayload else { return }
                present(payload)
            }
    }

    /// Presents the new payload after applying dedup, fires haptic,
    /// schedules auto-dismiss.
    private func present(_ payload: SaveErrorPayload) {
        // Dedup: same operation+message within the window → skip,
        // but still bump the timestamp on the existing banner so
        // its auto-dismiss timer resets (caller knows the issue
        // re-fired).
        if let last = lastShown,
           last.operation == payload.operation,
           last.message == payload.message,
           payload.timestamp.timeIntervalSince(last.timestamp) < dedupWindow {
            // Reset the timer so the banner doesn't disappear
            // mid-stream of repeated errors.
            scheduleAutoDismiss()
            return
        }

        HapticManager.shared.error()
        current = payload
        lastShown = payload
        scheduleAutoDismiss()
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            if !Task.isCancelled {
                dismissCurrent()
            }
        }
    }

    private func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(Theme.Motion.snappy) {
            current = nil
        }
    }
}

extension View {
    /// Mount the save-error banner host at the app root. Listens
    /// for `Notification.Name.saveErrorOccurred` and renders a
    /// floating banner above the bottom safe area.
    func saveErrorBannerHost() -> some View {
        modifier(SaveErrorBannerHost())
    }
}
