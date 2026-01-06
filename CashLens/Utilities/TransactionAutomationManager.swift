import Foundation
import UserNotifications
import SwiftUI
import Combine

@MainActor
class TransactionAutomationManager: ObservableObject {
    static let shared = TransactionAutomationManager()
    
    @Published var pendingTransactions: [AutomatedTransaction] = []
    @Published var processedTransactions: [AutomatedTransaction] = []
    
    private let pendingTransactionsKey = "pendingTransactions"
    private let processedTransactionsKey = "processedTransactions"
    private let settings = AutomationSettings.shared
    
    private init() {
        loadPendingTransactions()
        loadProcessedTransactions()
    }
    
    // MARK: - Pending Transaction Management
    
    func addPendingTransaction(_ transaction: AutomatedTransaction) async {
        var newTransaction = transaction
        newTransaction.suggestCategory()
        
        await MainActor.run {
            pendingTransactions.append(newTransaction)
            savePendingTransactions()
        }
    }
    
    func addPendingTransactionSync(_ transaction: AutomatedTransaction) {
        var newTransaction = transaction
        newTransaction.suggestCategory()
        
        pendingTransactions.append(newTransaction)
        savePendingTransactions()
    }
    
    func approveTransaction(_ transaction: AutomatedTransaction, with viewModel: ExpenseViewModel, category: Expense.Category? = nil, customTitle: String? = nil) {
        // Remove from pending
        if let index = pendingTransactions.firstIndex(where: { $0.id == transaction.id }) {
            pendingTransactions.remove(at: index)
        }
        
        // Create expense
        let expense = transaction.toExpense(
            with: viewModel.selectedCurrency,
            category: category,
            title: customTitle
        )
        
        // Add to expenses
        viewModel.addExpense(expense)
        
        // Mark as processed
        var processedTransaction = transaction
        processedTransaction.isProcessed = true
        processedTransactions.append(processedTransaction)
        
        // Save changes
        savePendingTransactions()
        saveProcessedTransactions()
    }
    
    func deleteTransaction(_ transaction: AutomatedTransaction) {
        if let index = pendingTransactions.firstIndex(where: { $0.id == transaction.id }) {
            pendingTransactions.remove(at: index)
            savePendingTransactions()
        }
    }
    
    // MARK: - Computed Properties
    
    var totalPendingAmount: Double {
        pendingTransactions.reduce(0) { $0 + $1.amount }
    }
    
    // MARK: - Notifications
    
    func scheduleTransactionNotification(for transaction: AutomatedTransaction) async {
        let content = UNMutableNotificationContent()
        content.title = "New Transaction Detected"
        content.body = "\(transaction.source.rawValue): \(formatAmount(transaction.amount, source: transaction.source)) at \(transaction.merchant)"
        content.sound = .default
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "transaction_\(transaction.id.uuidString)",
            content: content,
            trigger: nil // Immediate notification
        )
        
        // Schedule notification
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Persistence
    
    private func savePendingTransactions() {
        if let data = try? JSONEncoder().encode(pendingTransactions) {
            UserDefaults.standard.set(data, forKey: pendingTransactionsKey)
        }
    }
    
    private func loadPendingTransactions() {
        if let data = UserDefaults.standard.data(forKey: pendingTransactionsKey),
           let transactions = try? JSONDecoder().decode([AutomatedTransaction].self, from: data) {
            pendingTransactions = transactions
        }
    }
    
    private func saveProcessedTransactions() {
        if let data = try? JSONEncoder().encode(processedTransactions) {
            UserDefaults.standard.set(data, forKey: processedTransactionsKey)
        }
    }
    
    private func loadProcessedTransactions() {
        if let data = UserDefaults.standard.data(forKey: processedTransactionsKey),
           let transactions = try? JSONDecoder().decode([AutomatedTransaction].self, from: data) {
            processedTransactions = transactions
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatAmount(_ amount: Double, source: TransactionSource) -> String {
        switch source {
        case .upi:
            return "₹\(String(format: "%.2f", amount))"
        case .applePay, .manual:
            return "$\(String(format: "%.2f", amount))"
        }
    }
} 