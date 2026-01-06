import Foundation
import AppIntents
import SwiftUI

// MARK: - Add Transaction Intent
@available(iOS 16.0, *)
struct AddTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Transaction"
    static var description = IntentDescription("Add a new transaction to CashLens from external automation")
    
    @Parameter(title: "Amount")
    var amount: Double
    
    @Parameter(title: "Merchant")
    var merchant: String
    
    @Parameter(title: "Payment Method", default: "Apple Pay")
    var paymentMethod: String
    
    @Parameter(title: "Notes")
    var notes: String?
    
    @Parameter(title: "Auto-approve", default: false)
    var autoApprove: Bool
    
    static var parameterSummary: some ParameterSummary {
        Summary("Add transaction for \(\.$amount) at \(\.$merchant)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Create automated transaction
        var transaction = AutomatedTransaction(
            amount: amount,
            merchant: merchant,
            paymentMethod: paymentMethod,
            date: Date(),
            notes: notes
        )
        
        // Apply smart categorization
        transaction.suggestCategory()
        
        // Get automation settings
        let settings = AutomationSettings.shared
        
        if settings.autoApproveTransactions || autoApprove {
            // Automatically add to expenses
            let context = PersistenceController.shared.container.viewContext
            let viewModel = ExpenseViewModel(context: context)
            
            let expense = transaction.toExpense(
                with: viewModel.selectedCurrency,
                category: transaction.suggestedCategory,
                title: merchant
            )
            
            viewModel.addExpense(expense)
            transaction.isProcessed = true
            
            return .result(dialog: "Added \(merchant) expense for \(amount) to CashLens")
        } else {
            // Add to pending transactions for review
            await TransactionAutomationManager.shared.addPendingTransaction(transaction)
            
            if settings.notifyOnNewTransaction {
                // Send local notification
                await TransactionAutomationManager.shared.scheduleTransactionNotification(for: transaction)
            }
            
            return .result(dialog: "Transaction from \(merchant) is pending review in CashLens")
        }
    }
}

// MARK: - Parse SMS Intent
@available(iOS 16.0, *)
struct ParseSMSIntent: AppIntent {
    static var title: LocalizedStringResource = "Parse UPI SMS"
    static var description = IntentDescription("Parse UPI transaction details from SMS and add to CashLens")
    
    @Parameter(title: "SMS Text")
    var smsText: String
    
    @Parameter(title: "Sender")
    var sender: String?
    
    @Parameter(title: "Auto-approve UPI", default: false)
    var autoApprove: Bool
    
    static var parameterSummary: some ParameterSummary {
        Summary("Parse UPI transaction from SMS")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Get automation settings
        let settings = AutomationSettings.shared
        
        // Check if SMS automation is enabled
        guard settings.enableSMSAutomation else {
            return .result(dialog: "SMS automation is disabled in CashLens settings")
        }
        
        // Try to parse UPI transaction from SMS
        guard var transaction = UPISMSParser.parseUPITransaction(from: smsText) else {
            return .result(dialog: "Could not parse UPI transaction from this SMS")
        }
        
        // Check amount limits
        if transaction.amount < settings.minimumUPIAmount || transaction.amount > settings.maximumUPIAmount {
            return .result(dialog: "Transaction amount ₹\(transaction.amount) is outside configured limits")
        }
        
        // Add sender information if available
        if let sender = sender {
            let existingNotes = transaction.notes ?? ""
            transaction.notes = existingNotes.isEmpty ? "SMS from \(sender)" : "\(existingNotes) • SMS from \(sender)"
        }
        
        if settings.autoApproveUPITransactions || autoApprove {
            // Automatically add to expenses
            let context = PersistenceController.shared.container.viewContext
            let viewModel = ExpenseViewModel(context: context)
            
            let expense = transaction.toExpense(
                with: .inr, // Default to INR for UPI transactions
                category: transaction.suggestedCategory,
                title: transaction.merchant
            )
            
            viewModel.addExpense(expense)
            transaction.isProcessed = true
            
            return .result(dialog: "Added UPI expense: ₹\(transaction.amount) to \(transaction.merchant)")
        } else {
            // Add to pending transactions for review
            await TransactionAutomationManager.shared.addPendingTransaction(transaction)
            
            if settings.notifyOnNewTransaction {
                // Send local notification
                await TransactionAutomationManager.shared.scheduleTransactionNotification(for: transaction)
            }
            
            return .result(dialog: "UPI transaction ₹\(transaction.amount) to \(transaction.merchant) is pending review")
        }
    }
}

// MARK: - Get Pending Transactions Intent
@available(iOS 16.0, *)
struct GetPendingTransactionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Pending Transactions"
    static var description = IntentDescription("Get the number of pending transactions awaiting review")
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let pendingCount = TransactionAutomationManager.shared.pendingTransactions.count
        return .result(value: pendingCount)
    }
}

// MARK: - Test SMS Parser Intent
@available(iOS 16.0, *)
struct TestSMSParserIntent: AppIntent {
    static var title: LocalizedStringResource = "Test SMS Parser"
    static var description = IntentDescription("Test if an SMS can be parsed for UPI transaction details")
    
    @Parameter(title: "SMS Text")
    var smsText: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Test parsing SMS: \(\.$smsText)")
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let transaction = UPISMSParser.parseUPITransaction(from: smsText) {
            return .result(dialog: "✅ Parsed: ₹\(transaction.amount) to \(transaction.merchant) via \(transaction.paymentMethod)")
        } else {
            return .result(dialog: "❌ Could not parse transaction from this SMS")
        }
    }
}

// MARK: - Transaction Automation Shortcuts
@available(iOS 16.0, *)
struct CashLensShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add transaction in ${applicationName}",
                "Record expense in ${applicationName}"
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle"
        )
        
        AppShortcut(
            intent: ParseSMSIntent(),
            phrases: [
                "Parse UPI SMS in ${applicationName}",
                "Add UPI transaction from SMS in ${applicationName}"
            ],
            shortTitle: "Parse UPI SMS",
            systemImageName: "message.circle"
        )
        
        AppShortcut(
            intent: TestSMSParserIntent(),
            phrases: [
                "Test SMS parser in ${applicationName}"
            ],
            shortTitle: "Test SMS Parser",
            systemImageName: "magnifyingglass.circle"
        )
    }
} 
