import SwiftUI

/// Privacy dashboard — pushed from "You → Privacy".
///
/// The app's #1 differentiator (everything is local, nothing phones
/// home) rendered as verifiable facts instead of marketing copy:
/// what's stored, how much space it takes, and the three zeros
/// (servers, trackers, accounts). Calm tone, no scaremongering —
/// this page should read like a receipt, not a pitch.
struct PrivacyDashboardView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appLockManager = AppLockManager.shared

    @State private var showingExportSheet = false
    /// Receipts directory size — file IO, so computed off-main on
    /// appear rather than inline in body.
    @State private var receiptBytes: Int64 = 0

    /// "iPhone" / "iPad" — the hero line should name the device the
    /// user is actually holding.
    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxl) {
                heroCard
                zerosStrip
                storedOnDeviceGroup
                controlsGroup
                explanationNote
            }
            .padding()
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Color.systemBackground)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.large)
        // Parent tab root (You) hides its nav bar; pushed views must
        // explicitly opt back in or the back button disappears.
        .navigationBarHidden(false)
        .sheet(isPresented: $showingExportSheet) {
            ExportDataView()
                .environmentObject(viewModel)
        }
        .task {
            let bytes = await Task.detached(priority: .utility) {
                ReceiptStorage.totalBytesUsed()
            }.value
            receiptBytes = bytes
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            HeroGlyph(systemName: "lock.shield.fill")

            Text("Your data never leaves this \(deviceName)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text("Every expense, budget, and receipt is stored on this device only. There's no account to create, no cloud sync, and no analytics watching how you spend.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: Theme.Radius.hero)
    }

    // MARK: - The three zeros

    /// Servers · Trackers · Accounts, all zero — the whole privacy
    /// story in one glanceable strip.
    private var zerosStrip: some View {
        HStack(spacing: 0) {
            zeroCell(title: "Servers", icon: "server.rack")
            zeroDivider
            zeroCell(title: "Trackers", icon: "eye.slash.fill")
            zeroDivider
            zeroCell(title: "Accounts", icon: "person.crop.circle.badge.xmark")
        }
        .padding(.vertical, Theme.Spacing.lg)
        .cardSurface()
    }

    private func zeroCell(title: String, icon: String) -> some View {
        VStack(spacing: Theme.Spacing.xs + 2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
            Text("0")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var zeroDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 44)
    }

    // MARK: - What's stored here

    private var storedOnDeviceGroup: some View {
        SettingsGroup(title: "Stored on this \(deviceName)") {
            SettingsRow(icon: "list.bullet.rectangle.fill", title: "Expenses", showsChevron: false, style: .bare) {
                SettingsRowValue(text: expensesCountText)
            }
            SettingsRow(icon: "doc.text.viewfinder", title: "Receipts", showsChevron: false, style: .bare) {
                SettingsRowValue(text: receiptStorageText)
            }
        }
    }

    /// With windowed hydration the in-memory array may hold only the
    /// recent launch window for a beat after cold start — don't state
    /// a number that's about to grow.
    private var expensesCountText: String {
        viewModel.isFullyHydrated ? "\(viewModel.expenses.count)" : "Counting…"
    }

    private var receiptStorageText: String {
        guard receiptBytes > 0 else { return "None yet" }
        return ByteCountFormatter.string(fromByteCount: receiptBytes, countStyle: .file)
    }

    // MARK: - Your controls

    private var controlsGroup: some View {
        SettingsGroup(title: "Your Controls") {
            appLockStatusRow
            exportRow
        }
    }

    /// Status + a hop back to the toggle, which lives one level up on
    /// the You tab (this page is pushed from right next to it).
    private var appLockStatusRow: some View {
        SettingsRow(
            icon: AppLockManager.unlockMethodSymbol,
            title: "App Lock",
            subtitle: appLockManager.isEnabled
                ? nil
                : "Add \(AppLockManager.unlockMethodName) on top of your device lock.",
            showsChevron: true,
            style: .bare
        ) {
            Text(appLockManager.isEnabled ? "On" : "Off")
                .font(.caption.weight(.bold))
                .foregroundColor(appLockManager.isEnabled ? .green : .secondary)
                .padding(.horizontal, Theme.Spacing.sm + 2)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        (appLockManager.isEnabled ? Color.green : Color.secondary).opacity(0.14)
                    )
                )
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            dismiss()
        }
    }

    private var exportRow: some View {
        SettingsRow(
            icon: "square.and.arrow.up.fill",
            title: "Export Anytime",
            subtitle: "Your data is yours — take a full copy whenever you like.",
            showsChevron: true,
            style: .bare
        ) {
            EmptyView()
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingExportSheet = true
        }
    }

    // MARK: - Plain-language note

    private var explanationNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm + 2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Text("CashLens has no servers and no analytics — the only connections are Apple's App Store for purchases and web links you tap yourself (like our privacy policy). Home Screen widgets you add can show totals outside the app. Because everything lives here, regular exports are your backup — there's no copy of your data anywhere else.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Preview

struct PrivacyDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PrivacyDashboardView()
                .environmentObject(ExpenseViewModel())
        }
    }
}
