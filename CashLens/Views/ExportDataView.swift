import SwiftUI
import UniformTypeIdentifiers

/// `ExportDataView` is the user-facing entry point for backing up CashLens.
///
/// Two formats are offered, with their differences spelled out plainly so users
/// pick the right one rather than guessing:
///
/// - **Complete Backup (.cashlens.json)** — single self-describing JSON file
///   containing every expense, subscription, custom category, **budget**, and
///   user preference (currency, appearance, pinned categories, notification
///   schedules, and so on). This is the only format that fully restores the
///   app on a new install.
///
/// - **Spreadsheet (.csv)** — flat, RFC 4180 CSV of expenses only, with ISO
///   8601 dates so it opens cleanly in Numbers / Excel / Sheets regardless of
///   locale. Use this for analysis, not for restore.
///
/// Both formats are written in the background (`Task.detached`) and produce a
/// share sheet with the resulting file URL.
struct ExportDataView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel

    @State private var exportFormat: ExportFormat = .json
    @State private var exportURL: URL? = nil
    @State private var showingShareSheet = false
    @State private var alertMessage: String? = nil
    @State private var isExporting = false
    @State private var animateIn = false

    /// Mirrors of the backup metadata in `UserDefaults`, refreshed on appear and
    /// whenever a successful export records new metadata. Stored as `Date?` to
    /// stay wire-compatible with `ProfileView`'s `reloadBackupMetadata()`.
    @State private var lastBackupDate: Date? = nil
    @State private var totalBackupCount: Int = 0
    @State private var lastBackupFormat: String = ""

    enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "Complete Backup"
        case csv = "Spreadsheet"
        /// `.cashlens-archive` — JSON bundle plus every receipt
        /// photo, packaged as a single zip-format file the user can
        /// AirDrop / iCloud / email and restore on any device.
        /// Visually we present this as the "premium" choice (the
        /// only one that survives a phone upgrade with receipts).
        case archive = "Full Archive"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .json:    return "cashlens.json"
            case .csv:     return "csv"
            case .archive: return "cashlens-archive"
            }
        }

        var icon: String {
            switch self {
            case .json:    return "shippingbox.fill"
            case .csv:     return "tablecells.fill"
            case .archive: return "archivebox.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .json:    return "Full restore on a new device"
            case .csv:     return "Open in Numbers, Excel, Sheets"
            case .archive: return "Everything above + receipt photos"
            }
        }

        var bullets: [String] {
            switch self {
            case .json:
                return [
                    "All expenses, subscriptions, custom categories",
                    "Budgets and budget alert thresholds",
                    "Currency, appearance, pinned categories, notifications"
                ]
            case .csv:
                return [
                    "Expenses with ISO 8601 dates",
                    "RFC 4180 quoting — opens anywhere",
                    "No subscriptions, budgets, or preferences"
                ]
            case .archive:
                return [
                    "Everything in Complete Backup",
                    "Plus every receipt photo file (.jpg)",
                    "Single .cashlens-archive file — AirDrop, iCloud, email"
                ]
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                backgroundLayer

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xl) {
                        heroSection
                            .modifier(SectionEntrance(order: 0, animate: animateIn))
                        backupStatsCard
                            .modifier(SectionEntrance(order: 1, animate: animateIn))
                        formatPicker
                            .modifier(SectionEntrance(order: 2, animate: animateIn))
                        whatsIncludedCard
                            .modifier(SectionEntrance(order: 3, animate: animateIn))
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }
                .blur(radius: isExporting ? 3 : 0)
                .allowsHitTesting(!isExporting)

                exportActionBar
                    .modifier(SectionEntrance(order: 4, animate: animateIn))

                if isExporting {
                    loadingOverlay
                }
            }
            .navigationBarTitle("Export", displayMode: .inline)
            .navigationBarItems(trailing:
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundColor(.appPrimary)
                    .disabled(isExporting)
            )
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Couldn't export", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                refreshBackupMetadata()
                withAnimation { animateIn = true }
            }
        }
    }

    private func refreshBackupMetadata() {
        lastBackupDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastBackupDate) as? Date
        totalBackupCount = UserDefaults.standard.integer(forKey: UserDefaultsKeys.totalBackupCount)
        lastBackupFormat = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastBackupFormat) ?? ""
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            LinearGradient.appPrimarySoft
                .ignoresSafeArea()
                .opacity(0.85)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.appPrimary.opacity(0.28), radius: 14, x: 0, y: 8)
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text("Back Up Your Data")
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Save a copy you can restore later, or open in any spreadsheet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Backup stats

    private var backupStatsCard: some View {
        HStack(spacing: 0) {
            statTile(
                icon: "clock.fill",
                value: lastBackupRelative,
                label: "Last backup"
            )
            divider
            statTile(
                icon: "checkmark.seal.fill",
                value: "\(totalBackupCount)",
                label: "Total backups"
            )
            divider
            statTile(
                icon: "doc.text.fill",
                value: lastBackupFormatDisplay,
                label: "Format"
            )
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(Color.appPrimary.opacity(0.08), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 32)
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.appPrimary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var lastBackupRelative: String {
        guard let date = lastBackupDate else { return "Never" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var lastBackupFormatDisplay: String {
        if lastBackupFormat.isEmpty { return "—" }
        switch lastBackupFormat {
        case "Spreadsheet":  return "CSV"
        case "Full Archive": return "Archive"
        default:             return "JSON"
        }
    }

    // MARK: - Format picker

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Choose a format")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.md) {
                ForEach(ExportFormat.allCases) { format in
                    formatCard(format)
                }
            }
        }
    }

    private func formatCard(_ format: ExportFormat) -> some View {
        let isSelected = exportFormat == format
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                exportFormat = format
            }
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(LinearGradient.appPrimaryDiagonal)
                              : AnyShapeStyle(Color.tertiarySystemBackground))
                        .frame(width: 52, height: 52)
                    Image(systemName: format.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(format.rawValue)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.primary)
                        if format == .json {
                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(LinearGradient.appPrimaryDiagonal)
                                )
                                .foregroundColor(.white)
                        }
                    }
                    Text(format.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.appPrimary : Color.primary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(LinearGradient.appPrimaryDiagonal)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.appPrimary.opacity(0.45) : Color.primary.opacity(0.05),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.appPrimary.opacity(0.12) : Color.black.opacity(0.03),
                radius: isSelected ? 10 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }

    // MARK: - What's included

    private var whatsIncludedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text("What's included")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(exportFormat.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.appPrimary)
                        }
                        Text(bullet)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
        }
        .animation(Theme.Motion.tap, value: exportFormat)
    }

    // MARK: - Action bar

    private var exportActionBar: some View {
        VStack(spacing: 0) {
            // Hairline divider replaces fade-to-background gradient.
            Divider().opacity(0.35)

            VStack(spacing: 0) {
                Button {
                    HapticManager.shared.mediumTap()
                    exportData()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExporting ? "hourglass" : "square.and.arrow.up.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(isExporting ? "Preparing…" : "Export \(exportFormat.rawValue)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, Theme.Spacing.md + 4)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient.appPrimaryDiagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .shadow(color: Color.appPrimary.opacity(0.32), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isExporting)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .background(Color.systemBackground.ignoresSafeArea(edges: .bottom))
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.appPrimary)
                Text("Preparing your backup…")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }
            .padding(Theme.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
            .shadow(radius: 20)
            .padding(.horizontal, Theme.Spacing.xxl)
        }
    }

    // MARK: - Actions

    private func exportData() {
        isExporting = true
        let format: BackupExporter.Format
        switch exportFormat {
        case .json:    format = .json
        case .csv:     format = .csv
        case .archive: format = .archive
        }

        Task.detached(priority: .userInitiated) {
            let bundle = BackupExporter.buildBundle()

            // Guard against truly-empty backups for the CSV path (the JSON path
            // is still useful as a "schema confirmation" so we allow it).
            if format == .csv, bundle.data.expenses.isEmpty {
                await MainActor.run {
                    self.isExporting = false
                    self.alertMessage = "There aren't any expenses to put in a spreadsheet yet. Add an expense first, or use Complete Backup."
                }
                return
            }

            let url = BackupExporter.write(bundle, as: format)
            await MainActor.run {
                self.isExporting = false
                if let url {
                    self.exportURL = url
                    self.showingShareSheet = true
                    Self.recordBackup(format: self.exportFormat)
                    self.refreshBackupMetadata()
                } else {
                    self.alertMessage = "We couldn't create the export file. Make sure CashLens has enough storage and try again."
                }
            }
        }
    }

    /// Persist backup metadata. `lastBackupDate` is stored as a `Date` (not a
    /// timeInterval) to keep wire-compat with `ProfileView.reloadBackupMetadata`
    /// which casts the value back to `Date?`.
    ///
    /// Posts `.backupMetadataDidChange` so `ProfileView` can refresh its
    /// footer immediately. ProfileView used to listen to
    /// `UserDefaults.didChangeNotification` instead, which fired on
    /// **every** UserDefaults write app-wide — a lot of needless work
    /// while Settings was open. The targeted notification keeps the
    /// UX (instant footer update) while costing essentially nothing.
    private static func recordBackup(format: ExportFormat) {
        UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastBackupDate)
        UserDefaults.standard.set(format.rawValue, forKey: UserDefaultsKeys.lastBackupFormat)
        let count = UserDefaults.standard.integer(forKey: UserDefaultsKeys.totalBackupCount)
        UserDefaults.standard.set(count + 1, forKey: UserDefaultsKeys.totalBackupCount)
        NotificationCenter.default.post(name: .backupMetadataDidChange, object: nil)
    }
}

// MARK: - Section entrance modifier

private struct SectionEntrance: ViewModifier {
    let order: Int
    let animate: Bool

    private var delay: Double { Double(order) * 0.06 }

    func body(content: Content) -> some View {
        content
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 12)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0)
                    .delay(delay),
                value: animate
            )
    }
}

// MARK: - Share sheet

/// Wrapper around `UIActivityViewController` so SwiftUI can present a share
/// sheet with the resulting backup file.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            if let error = error {
                print("ShareSheet error: \(error.localizedDescription)")
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct ExportDataView_Previews: PreviewProvider {
    static var previews: some View {
        ExportDataView()
            .environmentObject(ExpenseViewModel())
    }
}
