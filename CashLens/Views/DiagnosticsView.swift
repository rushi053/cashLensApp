#if DEBUG
import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ExpenseViewModel
    
    @State private var dataSummary: String = "-"
    @State private var currencyReport: String = "-"
    @State private var smokeCheckResults: [(title: String, status: String, details: String?)] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Data")) {
                    Text(dataSummary)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button("Refresh Data") {
                        viewModel.refreshData()
                        refreshReports()
                    }
                }
                
                Section(header: Text("Currency")) {
                    Text(currencyReport)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button("Re-check Currency Consistency") {
                        refreshReports()
                    }
                    
                    Button("Force Currency Sync (selected currency)") {
                        viewModel.syncCurrencyAcrossStoredData()
                        refreshReports()
                    }
                }
                
                Section(header: Text("Review Prompt")) {
                    Button("Reset Review Prompt State (debug)") {
                        ReviewPromptManager.shared.resetForDebugging()
                    }
                }

                // Perf measurement seeder (see `DebugExpenseSeeder`).
                // Seeded rows are marked and only they are deleted.
                Section(header: Text("Stress Test Data"), footer: Text(seederFooter)) {
                    Button("Seed 5,000 test expenses") {
                        pendingSeedCount = 5_000
                    }
                    .disabled(seederBusy)

                    Button("Seed 20,000 test expenses") {
                        pendingSeedCount = 20_000
                    }
                    .disabled(seederBusy)

                    Button("Delete seeded data", role: .destructive) {
                        confirmDeleteSeeded = true
                    }
                    .disabled(seederBusy)

                    if seederBusy {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Working…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !seederStatus.isEmpty {
                        Text(seederStatus)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                
                Section(header: Text("Smoke Checks")) {
                    Button("Run Smoke Checks") {
                        runSmokeChecks()
                    }
                    
                    if smokeCheckResults.isEmpty {
                        Text("No results yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(smokeCheckResults.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(item.status)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let details = item.details, !details.isEmpty {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .onAppear {
                refreshReports()
            }
            .confirmationDialog(
                seedDialogTitle,
                isPresented: Binding(
                    get: { pendingSeedCount != nil },
                    set: { if !$0 { pendingSeedCount = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Seed") {
                    if let count = pendingSeedCount { runSeeder(count: count) }
                    pendingSeedCount = nil
                }
                Button("Cancel", role: .cancel) { pendingSeedCount = nil }
            } message: {
                Text("Adds marked test rows in \(viewModel.selectedCurrency.rawValue) plus six \"Seed …\" categories. Your real expenses are untouched; use \"Delete seeded data\" to remove them.")
            }
            .confirmationDialog(
                "Delete all seeded test data?",
                isPresented: $confirmDeleteSeeded,
                titleVisibility: .visible
            ) {
                Button("Delete seeded data", role: .destructive) { runDeleteSeeded() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes only rows created by the seeder (marked internally) and the six \"Seed …\" categories.")
            }
        }
    }

    // MARK: - Stress seeder

    @State private var pendingSeedCount: Int? = nil
    @State private var confirmDeleteSeeded = false
    @State private var seederBusy = false
    @State private var seederStatus: String = ""

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private var seederFooter: String {
        "Debug builds only. Also available as the launch argument -\(DebugExpenseSeeder.launchArgumentKey) <n>."
    }

    private var seedDialogTitle: String {
        guard let count = pendingSeedCount else { return "Seed test expenses?" }
        let formatted = Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "Seed \(formatted) test expenses?"
    }

    private func runSeeder(count: Int) {
        seederBusy = true
        seederStatus = ""
        DebugExpenseSeeder.seed(
            count: count,
            container: PersistenceController.shared.container,
            currencyCode: viewModel.selectedCurrency.rawValue
        ) { summary in
            seederBusy = false
            let rows = Self.countFormatter.string(from: NSNumber(value: summary.insertedExpenses)) ?? "\(summary.insertedExpenses)"
            seederStatus = "Inserted \(rows) expenses and \(summary.insertedCategories) categories in \(String(format: "%.2f", summary.elapsed))s."
            refreshReports()
        }
    }

    private func runDeleteSeeded() {
        seederBusy = true
        seederStatus = ""
        DebugExpenseSeeder.deleteSeededData(container: PersistenceController.shared.container) { expenses, categories in
            seederBusy = false
            let rows = Self.countFormatter.string(from: NSNumber(value: expenses)) ?? "\(expenses)"
            seederStatus = "Deleted \(rows) seeded expenses and \(categories) seeded categories."
            refreshReports()
        }
    }
    
    private func refreshReports() {
        dataSummary = viewModel.checkDataExists()
        currencyReport = viewModel.checkCurrencyConsistency().report
    }
    
    private func runSmokeChecks() {
        var results: [(title: String, status: String, details: String?)] = []
        
        // 1) Core fetch paths
        results.append(("Core Data fetches", "OK", viewModel.checkDataExists()))
        
        // 2) Currency consistency
        let consistency = viewModel.checkCurrencyConsistency()
        results.append(("Currency consistency", consistency.isConsistent ? "OK" : "WARN", nil))
        
        // 3) Category fetch sanity
        let customCount = viewModel.getCustomCategories().count
        results.append(("Custom categories fetch", "OK", "Custom categories: \(customCount)"))
        
        // 4) Subscription fetch sanity
        let subsCount = viewModel.loadSubscriptionsForExport().count
        results.append(("Subscriptions fetch", "OK", "Subscriptions: \(subsCount)"))
        
        smokeCheckResults = results
    }
}
#endif


