#if DEBUG
import SwiftUI

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: ExpenseViewModel
    
    @State private var dataSummary: String = "-"
    @State private var currencyReport: String = "-"
    @State private var smokeCheckResults: [(title: String, status: String, details: String?)] = []
    
    var body: some View {
        NavigationView {
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
                
                Section(header: Text("Feedback Prompt")) {
                    Button("Reset Feedback State (debug)") {
                        FeedbackManager.shared.resetFeedbackState()
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
                }
            }
            .onAppear {
                refreshReports()
            }
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


