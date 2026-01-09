import SwiftUI
import UniformTypeIdentifiers

struct ImportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var showingFilePicker = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var importStatus = ""
    @State private var importCountsText: String? = nil
    @State private var fakeProgressTask: Task<Void, Never>? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.appPrimary)
                        
                        Text("Import Your Data")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Restore your complete financial data from a previously exported file")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to Import")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            instructionRow(
                                number: "1",
                                title: "Select File",
                                description: "Choose your exported CSV or JSON file"
                            )
                            
                            instructionRow(
                                number: "2",
                                title: "Review Data",
                                description: "We'll show you what will be imported"
                            )
                            
                            instructionRow(
                                number: "3",
                                title: "Import",
                                description: "Your data will be restored completely"
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Warning Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Important")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Importing will add data to your existing records. If you want to replace all data, clear your current data first from Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Import Button
                    Button(action: {
                        hapticFeedback(style: .medium)
                        showingFilePicker = true
                    }) {
                        HStack {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.headline)
                            Text("Select File to Import")
                                .font(.headline)
                        }
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
                    .disabled(isImporting)
                    
                    Spacer()
                }
                .padding()
                .blur(radius: isImporting ? 3 : 0)
                
                // Loading overlay
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.appPrimary)
                                    .scaleEffect(1.15)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Importing…")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(importStatus.isEmpty ? "Working…" : importStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer(minLength: 0)
                                
                                Text("\(Int((max(0, min(1, importProgress)) * 100).rounded()))%")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            
                            ProgressView(value: importProgress.isFinite ? max(0, min(1, importProgress)) : 0.0, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .appPrimary))
                            
                            if let importCountsText {
                                Text(importCountsText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Text("Please keep CashLens open. Large imports can take a minute.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(18)
                        .background(Color.secondarySystemBackground.opacity(0.98))
                        .cornerRadius(16)
                        .shadow(radius: 12)
                        .padding(.horizontal, 28)
                    }
                }
            }
            .navigationBarTitle("Import Data", displayMode: .inline)
            .navigationBarItems(trailing: 
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .fontWeight(.bold)
                        .foregroundColor(.appPrimary)
                }
                .disabled(isImporting)
            )
            .background(Color.systemBackground)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func instructionRow(number: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Text(number)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.appPrimary)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - File Handling
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importDataFromFile(url)
            
        case .failure(let error):
            alertTitle = "File Selection Error"
            alertMessage = "Failed to select file: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func importDataFromFile(_ url: URL) {
        isImporting = true
        importProgress = 0.0
        importStatus = "Reading file…"
        importCountsText = nil
        startFakeProgress()
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Start reading file
                guard url.startAccessingSecurityScopedResource() else {
                    DispatchQueue.main.async {
                        self.showImportError("Unable to access the selected file")
                    }
                    return
                }
                
                defer { url.stopAccessingSecurityScopedResource() }
                
                let fileExtension = url.pathExtension.lowercased()
                let fileData = try Data(contentsOf: url)
                
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.importProgress = max(self.importProgress, 0.25)
                    }
                    self.importStatus = "Parsing data…"
                }
                
                var result: ImportResult
                
                if fileExtension == "json" {
                    result = try self.parseJSONData(fileData)
                } else {
                    // Handle CSV and other text formats
                    let content = String(data: fileData, encoding: .utf8) ?? ""
                    result = try self.parseCSVData(content)
                }
                
                DispatchQueue.main.async {
                    self.importCountsText = "\(result.expenses.count) expenses • \(result.subscriptions.count) subscriptions • \(result.customCategories.count) custom categories"
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.importProgress = max(self.importProgress, 0.65)
                    }
                    self.importStatus = "Saving to database…"
                    
                    self.importDataToDatabase(result) { success, message in
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.importProgress = 1.0
                            }
                            self.stopFakeProgress()
                            self.isImporting = false
                            
                            if success {
                                self.alertTitle = "Import Successful"
                                self.alertMessage = message
                            } else {
                                self.alertTitle = "Import Error"
                                self.alertMessage = message
                            }
                            self.showingAlert = true
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.showImportError("Failed to import data: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showImportError(_ message: String) {
        stopFakeProgress()
        isImporting = false
        alertTitle = "Import Error"
        alertMessage = message
        showingAlert = true
    }
    
    private func startFakeProgress() {
        stopFakeProgress()
        fakeProgressTask = Task { @MainActor in
            if importProgress < 0.05 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    importProgress = 0.05
                }
            }
            while isImporting {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard isImporting else { break }
                let ceiling = 0.95
                if importProgress < ceiling {
                    let remaining = max(0.0001, ceiling - importProgress)
                    let step = min(0.02, remaining * 0.10)
                    withAnimation(.linear(duration: 0.18)) {
                        importProgress = min(ceiling, importProgress + step)
                    }
                }
            }
        }
    }
    
    private func stopFakeProgress() {
        fakeProgressTask?.cancel()
        fakeProgressTask = nil
    }
    
    private func importDataToDatabase(_ result: ImportResult, completion: @escaping (Bool, String) -> Void) {
        viewModel.importData(result) { success, message in
            completion(success, message)
        }
    }
    
    // MARK: - Data Parsing
    
    private func parseJSONData(_ data: Data) throws -> ImportResult {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw ImportError.invalidFormat("Invalid JSON format")
        }
        
        return try ImportResult(from: jsonObject)
    }
    
    private func parseCSVData(_ content: String) throws -> ImportResult {
        return try ImportResult(fromCSV: content)
    }
    
    // MARK: - Haptic Feedback
    
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

struct ImportDataView_Previews: PreviewProvider {
    static var previews: some View {
        ImportDataView()
            .environmentObject(ExpenseViewModel())
    }
} 
