import SwiftUI

/// Full-screen fallback shown when the Core Data store failed to load
/// (see `PersistenceController.storeLoadError`). Shown instead of the
/// normal UI so nothing can touch the broken store.
///
/// Principles, in order:
///   1. Never crash.
///   2. Never delete or "reset" the store.
///   3. Always offer the raw data out (share sheet with the .sqlite
///      files) so the user's financial history is recoverable even if
///      this install never opens it again.
struct StoreRecoveryView: View {
    /// On-disk store files that exist right now (.sqlite / -wal / -shm).
    let storeFileURLs: [URL]

    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                HeroGlyph(systemName: "externaldrive.badge.exclamationmark", size: 52)
                    .padding(.bottom, Theme.Spacing.xl)

                Text("Your Data Is Safe")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .padding(.bottom, Theme.Spacing.sm)

                Text("CashLens couldn't open its database in this version of the app. Nothing has been lost — everything is still stored on this device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.xxl)

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    recoveryStep(
                        icon: "arrow.down.app",
                        title: "Update CashLens",
                        detail: "Check the App Store for a newer version — an update usually resolves this."
                    )
                    Divider().opacity(0.4)
                    recoveryStep(
                        icon: "square.and.arrow.up",
                        title: "Export your data files",
                        detail: "Save a copy of the raw database somewhere safe (Files, AirDrop, email to yourself)."
                    )
                    Divider().opacity(0.4)
                    recoveryStep(
                        icon: "envelope",
                        title: "Contact support",
                        detail: "We can help restore everything from the exported files."
                    )
                }
                .padding(Theme.Spacing.lg)
                .background(Color.secondarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        HapticManager.shared.mediumTap()
                        showShareSheet = true
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                            Text("Export My Data Files")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                        .background(Color.appPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .disabled(storeFileURLs.isEmpty)
                    .opacity(storeFileURLs.isEmpty ? 0.5 : 1)

                    Link(destination: URL(string: "mailto:email@rushiraj.me?subject=CashLens%20data%20recovery")!) {
                        Text("Contact Support")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.appPrimary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: storeFileURLs)
        }
    }

    private func recoveryStep(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appPrimary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    StoreRecoveryView(storeFileURLs: [])
}
