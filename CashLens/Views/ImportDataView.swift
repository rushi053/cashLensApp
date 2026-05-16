import SwiftUI
import UniformTypeIdentifiers

/// `ImportDataView` is the user-facing entry point for restoring CashLens data
/// from a backup file or importing transactions from another app / bank CSV.
///
/// Flow:
/// 1. **Pick a file** with `fileImporter`.
/// 2. **Parse + detect format** off-main; show a preview sheet with the
///    detected vendor, counts, any row-level warnings, and a Merge / Replace
///    toggle.
/// 3. On confirm, **apply** the bundle on a background Core Data context.
/// 4. Show a success summary with what was imported and what was skipped.
///
/// Foreign formats (Mint, YNAB, Apple Card, generic bank CSVs) are detected
/// by `BackupImporter` via `GenericCSVAdapter` and gated behind Pro — that's
/// the "magic" Pro experience.
///
/// ## Backward compatibility
///
/// All historical CashLens backup files keep working. `BackupImporter` falls
/// back to `LegacyV1Reader` for both `exportVersion: "1.0"` JSON files and the
/// older `=== EXPENSES ===` sectioned CSVs, so users on this build can still
/// restore from any backup the app has ever produced.
struct ImportDataView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var proManager: ProManager

    // MARK: - State

    @State private var showingFilePicker = false
    @State private var isParsing = false
    @State private var parsingStatus = "Reading file…"
    @State private var animateIn = false

    @State private var preview: BackupImporter.Preview? = nil
    @State private var showingPreview = false
    @State private var importMode: BackupImporter.Mode = .merge
    @State private var showingReplaceConfirm = false

    @State private var isApplying = false
    @State private var applySummary: BackupImporter.ImportSummary? = nil
    @State private var showingSummary = false

    @State private var errorTitle: String = "Import Error"
    @State private var errorMessage: String? = nil
    @State private var showingError = false

    @State private var showingPaywall = false

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                backgroundLayer

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xl) {
                        heroSection
                            .modifier(ImportSectionEntrance(order: 0, animate: animateIn))
                        howItWorksSection
                            .modifier(ImportSectionEntrance(order: 1, animate: animateIn))
                        formatsGrid
                            .modifier(ImportSectionEntrance(order: 2, animate: animateIn))
                        legacyFooterNote
                            .modifier(ImportSectionEntrance(order: 3, animate: animateIn))
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }
                .blur(radius: isParsing || isApplying ? 3 : 0)
                .allowsHitTesting(!(isParsing || isApplying))

                pickFileBar
                    .modifier(ImportSectionEntrance(order: 4, animate: animateIn))

                if isParsing || isApplying {
                    loadingOverlay
                }
            }
            .navigationBarTitle("Import", displayMode: .inline)
            .navigationBarItems(trailing:
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundColor(.appPrimary)
                    .disabled(isParsing || isApplying)
            )
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .json,
                    .commaSeparatedText,
                    .plainText,
                    UTType(filenameExtension: "cashlens.json") ?? .json,
                    // `.cashlens-archive` is a real zip under the
                    // hood, so we register both the custom extension
                    // (preferred — picker shows our icon when iOS
                    // knows the type) and `.zip` as a fallback for
                    // tools that strip / rewrite the extension on
                    // share (some chat apps re-stamp to .zip).
                    UTType(filenameExtension: "cashlens-archive") ?? .zip,
                    .zip
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .sheet(isPresented: $showingPreview) {
                if let preview {
                    ImportPreviewSheet(
                        preview: preview,
                        mode: $importMode,
                        onCancel: { showingPreview = false },
                        onConfirm: { startApply() }
                    )
                }
            }
            .alert("Replace all data?", isPresented: $showingReplaceConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Replace", role: .destructive) {
                    showingPreview = false
                    apply(mode: .replace)
                }
            } message: {
                Text("This will permanently delete all expenses, subscriptions, custom categories, and budgets currently in CashLens, then import what's in the file. There's no undo.")
            }
            .alert(errorTitle, isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingSummary) {
                if let applySummary {
                    ImportSummarySheet(summary: applySummary, onDone: {
                        showingSummary = false
                        dismiss()
                    })
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onAppear {
                withAnimation { animateIn = true }
            }
        }
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
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text("Restore Your Data")
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Bring back a CashLens backup, or import from your bank, Mint, YNAB, or Apple Card.")
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

    // MARK: - How it works (horizontal step pills)

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text("How it works")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                stepRow(
                    number: "1",
                    icon: "doc.badge.arrow.up",
                    title: "Pick a file",
                    description: ".cashlens.json, .csv, or any spreadsheet from another app."
                )
                stepRow(
                    number: "2",
                    icon: "eye.fill",
                    title: "Preview",
                    description: "See exactly what's inside, with Merge or Replace controls."
                )
                stepRow(
                    number: "3",
                    icon: "checkmark.seal.fill",
                    title: "Apply",
                    description: "Imports happen safely — duplicates are skipped automatically."
                )
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
        }
    }

    private func stepRow(number: String, icon: String, title: String, description: String) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.appPrimary.opacity(0.25), radius: 6, x: 0, y: 3)
                Text(number)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appPrimary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Supported formats grid

    private var formatsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text("Supported formats")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                formatTile(title: "CashLens", subtitle: "Backup file", icon: "shippingbox.fill", isPro: false)
                formatTile(title: "Spreadsheet", subtitle: "CashLens CSV", icon: "tablecells.fill", isPro: false)
                formatTile(title: "Mint / YNAB", subtitle: "Auto-mapped", icon: "wand.and.stars", isPro: true)
                formatTile(title: "Bank CSV", subtitle: "Generic statement", icon: "building.columns.fill", isPro: true)
            }
        }
    }

    private func formatTile(title: String, subtitle: String, icon: String, isPro: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(isPro ? AnyShapeStyle(LinearGradient.appPrimaryDiagonal) : AnyShapeStyle(Color.appPrimary.opacity(0.12)))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isPro ? .white : .appPrimary)
                }
                Spacer(minLength: 0)
                if isPro {
                    Text("PRO")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
                        .foregroundColor(.appPrimary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Legacy support note

    /// Reassures users that backups from older CashLens versions still work.
    /// Anything the app has ever produced is consumable: v1 JSON
    /// (`exportVersion: "1.0"`) and the original sectioned CSV.
    private var legacyFooterNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Older backups still work")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Files exported by any previous CashLens version are read automatically.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(LinearGradient.appPrimarySoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(Color.appPrimary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - CTA bar

    private var pickFileBar: some View {
        VStack(spacing: 0) {
            // Hairline divider replaces fade-to-background gradient.
            Divider().opacity(0.35)

            VStack(spacing: 0) {
                Button {
                    HapticManager.shared.mediumTap()
                    showingFilePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Choose a file")
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
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
                .disabled(isParsing || isApplying)
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
                Text(isApplying ? "Saving to CashLens…" : parsingStatus)
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

    // MARK: - File handling

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            startParse(url: url)
        case .failure(let error):
            showError("File selection failed", error.localizedDescription)
        }
    }

    private func startParse(url: URL) {
        isParsing = true
        parsingStatus = "Reading file…"
        let fallbackCurrency = viewModel.selectedCurrency

        Task.detached(priority: .userInitiated) {
            do {
                let preview = try BackupImporter.preview(url: url, fallbackCurrency: fallbackCurrency)
                await MainActor.run {
                    self.isParsing = false

                    // Pro gate for foreign CSVs.
                    if preview.format.requiresPro && !self.proManager.isPro {
                        self.showingPaywall = true
                        return
                    }

                    if preview.bundle.data.isEmpty && !preview.bundle.preferences.hasAny {
                        self.showError(
                            "Nothing to import",
                            "We didn't find any expenses, subscriptions, or settings in this file."
                        )
                        return
                    }

                    self.preview = preview
                    self.importMode = .merge
                    self.showingPreview = true
                }
            } catch {
                await MainActor.run {
                    self.isParsing = false
                    self.showError("Import error", error.localizedDescription)
                }
            }
        }
    }

    private func startApply() {
        switch importMode {
        case .merge:
            apply(mode: .merge)
        case .replace:
            showingReplaceConfirm = true
        }
    }

    private func apply(mode: BackupImporter.Mode) {
        guard let preview else { return }
        isApplying = true
        showingPreview = false

        BackupImporter.apply(preview, mode: mode) { result in
            DispatchQueue.main.async {
                self.isApplying = false
                switch result {
                case .success(let summary):
                    HapticManager.shared.success()
                    self.viewModel.reloadAfterBackupRestore()
                    self.applySummary = summary
                    self.showingSummary = true
                case .failure(let error):
                    self.showError("Import failed", error.localizedDescription)
                }
            }
        }
    }

    private func showError(_ title: String, _ message: String) {
        errorTitle = title
        errorMessage = message
        showingError = true
    }
}

// MARK: - Section entrance modifier

private struct ImportSectionEntrance: ViewModifier {
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

// MARK: - Preview Sheet

/// Confirmation sheet shown after a file has been parsed but before anything
/// is written. Surfaces detected format, per-type counts, any per-row warnings
/// from foreign CSV parsing, and the Merge / Replace toggle.
private struct ImportPreviewSheet: View {

    let preview: BackupImporter.Preview
    @Binding var mode: BackupImporter.Mode
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var animateIn = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                ZStack {
                    Color.systemBackground.ignoresSafeArea()
                    LinearGradient.appPrimarySoft.opacity(0.6).ignoresSafeArea()
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xl) {
                        formatHeaderCard
                            .modifier(ImportSectionEntrance(order: 0, animate: animateIn))
                        countsGrid
                            .modifier(ImportSectionEntrance(order: 1, animate: animateIn))
                        if !preview.foreignMappedColumns.isEmpty {
                            mappingSection
                                .modifier(ImportSectionEntrance(order: 2, animate: animateIn))
                        }
                        if !preview.foreignErrors.isEmpty {
                            warningsSection
                                .modifier(ImportSectionEntrance(order: 3, animate: animateIn))
                        }
                        modeSection
                            .modifier(ImportSectionEntrance(order: 4, animate: animateIn))
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }

                confirmBar
            }
            .navigationBarTitle("Review", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { onCancel(); dismiss() }
                    .foregroundColor(.secondary)
            )
            .onAppear { withAnimation { animateIn = true } }
        }
    }

    // MARK: - Format header

    private var formatHeaderCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.appPrimary.opacity(0.28), radius: 12, x: 0, y: 6)
                Image(systemName: formatIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text(preview.format.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("\(preview.totalRecordCount) record\(preview.totalRecordCount == 1 ? "" : "s") detected")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(Color.appPrimary.opacity(0.1), lineWidth: 1)
        )
        .padding(.top, Theme.Spacing.sm)
    }

    private var formatIcon: String {
        switch preview.format {
        case .cashlensJSONv2, .cashlensJSONv1: return "shippingbox.fill"
        case .cashlensCSVv1: return "tablecells.fill"
        case .foreignCSV: return "wand.and.stars"
        case .cashlensArchive: return "archivebox.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    // MARK: - Counts grid

    private var countsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("What's in the file", icon: "tray.full.fill")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                countTile(label: "Expenses", count: preview.bundle.data.expenses.count, icon: "creditcard.fill")
                countTile(label: "Subscriptions", count: preview.bundle.data.subscriptions.count, icon: "calendar.badge.clock")
                countTile(label: "Categories", count: preview.bundle.data.customCategories.count, icon: "tag.fill")
                countTile(label: "Budgets", count: preview.bundle.data.budgets.count, icon: "chart.pie.fill")
            }

            if preview.bundle.preferences.hasAny
                || !preview.bundle.data.deletedDefaultCategories.isEmpty
                || preview.receiptCount > 0 {
                VStack(spacing: 8) {
                    if preview.receiptCount > 0 {
                        extrasRow(
                            icon: "doc.text.viewfinder",
                            title: "Receipt photos",
                            value: "\(preview.receiptCount)"
                        )
                    }
                    if preview.bundle.preferences.hasAny {
                        extrasRow(icon: "gearshape.fill", title: "Settings & preferences", value: "Included")
                    }
                    if !preview.bundle.data.deletedDefaultCategories.isEmpty {
                        extrasRow(
                            icon: "eye.slash.fill",
                            title: "Hidden default categories",
                            value: "\(preview.bundle.data.deletedDefaultCategories.count)"
                        )
                    }
                }
            }
        }
    }

    private func countTile(label: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(count > 0 ? .primary : .secondary)
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
    }

    private func extrasRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.appPrimary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Color.secondarySystemBackground.opacity(0.6))
        )
    }

    // MARK: - Mapping (foreign CSV)

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Detected columns", icon: "arrow.left.and.right")

            VStack(spacing: 6) {
                ForEach(preview.foreignMappedColumns.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(entry.key)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 8)
                        Text(entry.value.rawValue)
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.4)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
                            .foregroundColor(.appPrimary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            )
        }
    }

    // MARK: - Warnings

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel(
                "\(preview.foreignErrors.count) row\(preview.foreignErrors.count == 1 ? "" : "s") will be skipped",
                icon: "exclamationmark.triangle.fill",
                tint: .orange
            )

            VStack(alignment: .leading, spacing: 6) {
                ForEach(preview.foreignErrors.prefix(5).indices, id: \.self) { i in
                    let err = preview.foreignErrors[i]
                    HStack(alignment: .top, spacing: 8) {
                        Text("L\(err.line)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                        Text(err.reason)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if preview.foreignErrors.count > 5 {
                    Text("…and \(preview.foreignErrors.count - 5) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: - Mode selection

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("How should we apply it?", icon: "arrow.triangle.branch")

            VStack(spacing: Theme.Spacing.sm) {
                modeCard(.merge,
                         title: "Merge",
                         subtitle: "Add anything new, skip duplicates. Existing data stays.",
                         icon: "arrow.triangle.merge")
                modeCard(.replace,
                         title: "Replace",
                         subtitle: "Wipe everything in CashLens first, then import. No undo.",
                         icon: "trash.fill",
                         accent: .red)
            }
        }
    }

    private func modeCard(_ value: BackupImporter.Mode, title: String, subtitle: String, icon: String, accent: Color = .appPrimary) -> some View {
        let isSelected = mode == value
        return Button {
            withAnimation(Theme.Motion.snappy) { mode = value }
            HapticManager.shared.selectionChanged()
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.tertiarySystemBackground))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? accent : Color.primary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
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
                        isSelected ? accent.opacity(0.4) : Color.primary.opacity(0.05),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section label helper

    private func sectionLabel(_ text: String, icon: String, tint: Color = .appPrimary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    // MARK: - Confirm bar

    private var confirmBar: some View {
        VStack(spacing: 0) {
            // Hairline divider replaces fade-to-background gradient.
            Divider().opacity(0.35)

            VStack(spacing: 0) {
                Button { onConfirm() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode == .replace ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(mode == .replace ? "Replace All Data" : "Import")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, Theme.Spacing.md + 4)
                    .frame(maxWidth: .infinity)
                    .background(mode == .replace
                                ? AnyShapeStyle(Color.red)
                                : AnyShapeStyle(LinearGradient.appPrimaryDiagonal))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .shadow(
                        color: (mode == .replace ? Color.red : Color.appPrimary).opacity(0.32),
                        radius: 14, x: 0, y: 6
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .background(Color.systemBackground.ignoresSafeArea(edges: .bottom))
        }
    }
}

// MARK: - Summary Sheet

/// Post-import confirmation sheet. Shows what was actually written and skipped.
private struct ImportSummarySheet: View {
    let summary: BackupImporter.ImportSummary
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var animateIn = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                ZStack {
                    Color.systemBackground.ignoresSafeArea()
                    LinearGradient.appPrimarySoft.opacity(0.6).ignoresSafeArea()
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xl) {
                        successHero
                            .modifier(ImportSectionEntrance(order: 0, animate: animateIn))
                        countsGrid
                            .modifier(ImportSectionEntrance(order: 1, animate: animateIn))
                        if !summary.preferencesUpdated.isEmpty {
                            preferencesCard
                                .modifier(ImportSectionEntrance(order: 2, animate: animateIn))
                        }
                        if !summary.rowErrors.isEmpty {
                            warningsCard
                                .modifier(ImportSectionEntrance(order: 3, animate: animateIn))
                        }
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }

                doneBar
            }
            .navigationBarTitle("Import Complete", displayMode: .inline)
            .navigationBarBackButtonHidden(true)
            .onAppear { withAnimation { animateIn = true } }
        }
    }

    // MARK: - Hero

    private var successHero: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.appPrimary.opacity(0.32), radius: 14, x: 0, y: 8)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text("All set")
                    .font(.system(size: 24, weight: .bold))
                Text("\(summary.totalImported) record\(summary.totalImported == 1 ? "" : "s") added • \(summary.totalSkipped) skipped")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Counts grid

    private var countsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("What we imported", icon: "tray.full.fill")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                tile(icon: "creditcard.fill", label: "Expenses", added: summary.expensesImported, skipped: summary.expensesSkipped)
                tile(icon: "calendar.badge.clock", label: "Subscriptions", added: summary.subscriptionsImported, skipped: summary.subscriptionsSkipped)
                tile(icon: "tag.fill", label: "Categories", added: summary.customCategoriesImported, skipped: summary.customCategoriesSkipped)
                tile(icon: "chart.pie.fill", label: "Budgets", added: summary.budgetsImported, skipped: summary.budgetsSkipped)
            }

            if summary.deletedDefaultsAdded > 0 {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appPrimary)
                        .frame(width: 24)
                    Text("Hidden categories restored")
                        .font(.system(size: 13))
                    Spacer()
                    Text("+\(summary.deletedDefaultsAdded)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.appPrimary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Color.secondarySystemBackground.opacity(0.6))
                )
            }

            if summary.receiptsRestored > 0 || summary.receiptsFailed > 0 {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appPrimary)
                        .frame(width: 24)
                    Text("Receipt photos restored")
                        .font(.system(size: 13))
                    Spacer()
                    if summary.receiptsFailed > 0 {
                        Text("\(summary.receiptsFailed) failed")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                            .foregroundColor(.secondary)
                    }
                    Text("+\(summary.receiptsRestored)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.appPrimary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Color.secondarySystemBackground.opacity(0.6))
                )
            }
        }
    }

    private func tile(icon: String, label: String, added: Int, skipped: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }
                Spacer(minLength: 0)
                if skipped > 0 {
                    Text("\(skipped) skipped")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .foregroundColor(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("+\(added)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(added > 0 ? .appPrimary : .secondary)
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemBackground)
        )
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Preferences updated", icon: "gearshape.fill")
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(summary.preferencesUpdated, id: \.self) { name in
                    HStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.appPrimary)
                        }
                        Text(name)
                            .font(.system(size: 14))
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
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel(
                "\(summary.rowErrors.count) row\(summary.rowErrors.count == 1 ? "" : "s") couldn't be read",
                icon: "exclamationmark.triangle.fill",
                tint: .orange
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.rowErrors.prefix(5).indices, id: \.self) { i in
                    let err = summary.rowErrors[i]
                    HStack(alignment: .top, spacing: 8) {
                        Text("L\(err.line)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                        Text(err.reason)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if summary.rowErrors.count > 5 {
                    Text("…and \(summary.rowErrors.count - 5) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private func sectionLabel(_ text: String, icon: String, tint: Color = .appPrimary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private var doneBar: some View {
        VStack(spacing: 0) {
            // Hairline divider replaces fade-to-background gradient.
            Divider().opacity(0.35)

            VStack(spacing: 0) {
                Button {
                    HapticManager.shared.lightTap()
                    onDone()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, Theme.Spacing.md + 4)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient.appPrimaryDiagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .shadow(color: Color.appPrimary.opacity(0.32), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .background(Color.systemBackground.ignoresSafeArea(edges: .bottom))
        }
    }
}

// MARK: - Preview

struct ImportDataView_Previews: PreviewProvider {
    static var previews: some View {
        ImportDataView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(ProManager.shared)
    }
}
