import SwiftUI
import UniformTypeIdentifiers

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var exportFormat: ExportFormat = .csv
    @State private var exportURL: URL? = nil
    @State private var showingShareSheet = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isExporting = false
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.appPrimary)
                        
                        Text("Export Your Data")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Choose a format to export all your financial data including expenses, subscriptions, and custom categories")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Format Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Format")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Button(action: {
                                hapticFeedback(style: .medium)
                                exportFormat = format
                            }) {
                                HStack {
                                    Image(systemName: format == .csv ? "tablecells" : "curlybraces")
                                        .font(.system(size: 22))
                                        .foregroundColor(.appPrimary)
                                        .frame(width: 30)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(format.rawValue)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(format == .csv ? "Spreadsheet compatible format" : "Developer friendly format")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if exportFormat == format {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.appPrimary)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(exportFormat == format ? Color.appPrimary.opacity(0.1) : Color.secondarySystemBackground)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isExporting)
                        }
                    }
                    .padding()
                    
                    // Export Button
                    Button(action: {
                        hapticFeedback(style: .medium)
                        exportData()
                    }) {
                        Text(isExporting ? "Preparing..." : "Export Data")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .disabled(isExporting)
                    
                    Spacer()
                }
                .padding()
                .blur(radius: isExporting ? 3 : 0)
                
                // Loading overlay
                if isExporting {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        
                        Text("Preparing your data...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(30)
                    .background(Color.secondarySystemBackground.opacity(0.9))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
            .navigationBarTitle("Export Data", displayMode: .inline)
            .navigationBarItems(trailing: 
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .fontWeight(.bold)
                        .foregroundColor(.appPrimary)
                }
                .disabled(isExporting)
            )
            .background(Color.systemBackground)
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("Export Error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func exportData() {
        // Check if there's any data to export
        let customCategories = viewModel.getCustomCategories()
        let hasExpenses = !viewModel.expenses.isEmpty
        let hasSubscriptions = !viewModel.loadSubscriptionsForExport().isEmpty
        let hasCustomCategories = !customCategories.isEmpty
        let hasDeletedCategories = !viewModel.getDeletedDefaultCategories().isEmpty
        
        if !hasExpenses && !hasSubscriptions && !hasCustomCategories && !hasDeletedCategories {
            alertMessage = "You don't have any data to export."
            showingAlert = true
            return
        }
        
        // Show loading state
        isExporting = true
        
        // Perform export on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            var url: URL? = nil
            
            switch exportFormat {
            case .csv:
                url = viewModel.exportToCSV()
            case .json:
                url = viewModel.exportToJSON()
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                isExporting = false
                
                if let exportUrl = url {
                    exportURL = exportUrl
                    showingShareSheet = true
                    
                    // Track successful backup
                    recordBackup(format: exportFormat)
                } else {
                    alertMessage = "Failed to export data to \(exportFormat.rawValue)."
                    showingAlert = true
                }
            }
        }
    }
    
    private func recordBackup(format: ExportFormat) {
        UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastBackupDate)
        UserDefaults.standard.set(format.rawValue, forKey: UserDefaultsKeys.lastBackupFormat)
        
        let currentCount = UserDefaults.standard.integer(forKey: UserDefaultsKeys.totalBackupCount)
        UserDefaults.standard.set(currentCount + 1, forKey: UserDefaultsKeys.totalBackupCount)
    }
    
    // MARK: - Haptic Feedback
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// ShareSheet for exporting files
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Prevent the share sheet from being dismissed when the user interacts with it
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            // Handle completion if needed
            if let error = error {
                print("Share sheet error: \(error.localizedDescription)")
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

struct ExportDataView_Previews: PreviewProvider {
    static var previews: some View {
        ExportDataView()
            .environmentObject(ExpenseViewModel())
    }
} 