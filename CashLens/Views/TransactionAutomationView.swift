import SwiftUI

struct TransactionAutomationView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @StateObject private var automationManager = TransactionAutomationManager.shared
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTransaction: AutomatedTransaction?
    @State private var showingTransactionDetail = false
    @State private var showingSettings = false
    @State private var selectedSource: TransactionSource?
    @State private var showingApprovalFeedback = false
    @State private var lastApprovedTransaction: String = ""
    @State private var showingSMSInstructions = false
    @State private var showingShortcutInstructions = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header Stats Card
                            statsCard
                            
                            // Filter Bar
                            filterBar
                            
                            // Transactions List
                            transactionsList
                        }
                        .padding()
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(Color.systemBackground)
            .navigationTitle("Pending Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .foregroundColor(.appPrimary)
                    .fontWeight(.medium)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        HapticManager.shared.lightTap()
                        showingSettings = true
                    }
                    .foregroundColor(.appPrimary)
                    .fontWeight(.medium)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            AutomationSettingsView()
        }
        .sheet(isPresented: $showingSMSInstructions) {
            SMSInstructionsView()
        }
        .sheet(isPresented: $showingShortcutInstructions) {
            ShortcutInstructionsView()
        }
        .sheet(isPresented: $showingTransactionDetail) {
            if let transaction = selectedTransaction {
                TransactionDetailView(
                    transaction: transaction,
                    viewModel: viewModel,
                    onApprove: { approvedTransaction, category, customTitle in
                        automationManager.approveTransaction(approvedTransaction, with: viewModel, category: category, customTitle: customTitle)
                        showingApprovalFeedback = true
                        lastApprovedTransaction = approvedTransaction.merchant
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingApprovalFeedback = false
                        }
                    },
                    onDelete: { deletedTransaction in
                        automationManager.deleteTransaction(deletedTransaction)
                    }
                )
                .environmentObject(categoryViewModel)
            }
        }
        .overlay(
            // Approval feedback toast
            Group {
                if showingApprovalFeedback {
                    VStack {
                        Spacer()
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.green)
                            }
                            
                            Text("Approved: \(lastApprovedTransaction)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondarySystemBackground)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(), value: showingApprovalFeedback)
                }
            }
        )
    }
    
    // MARK: - Computed Properties
    
    private var filteredTransactions: [AutomatedTransaction] {
        if let selectedSource = selectedSource {
            return automationManager.pendingTransactions.filter { $0.source == selectedSource }
        }
        return automationManager.pendingTransactions
    }
    
    private var sourceCounts: [TransactionSource: Int] {
        var counts: [TransactionSource: Int] = [:]
        for transaction in automationManager.pendingTransactions {
            counts[transaction.source, default: 0] += 1
        }
        return counts
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pending Review")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(automationManager.pendingTransactions.count) transaction\(automationManager.pendingTransactions.count == 1 ? "" : "s") awaiting review")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.selectedCurrency.symbol + String(format: "%.2f", automationManager.totalPendingAmount))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.appPrimary)
                    
                    Text("Total Amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !automationManager.pendingTransactions.isEmpty {
                Divider()
                
                // Bulk actions
                HStack(spacing: 12) {
                    Button(action: approveAllTransactions) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            
                            Text("Approve All")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.appPrimary, Color.appSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: Color.appPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: clearAllTransactions) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                            
                            Text("Clear All")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Spacer()
                }
            }
            
            // Source breakdown
            if sourceCounts.count > 1 {
                sourceBreakdown
            }
        }
        .padding(20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var sourceBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            
            HStack {
                Text("BY SOURCE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(TransactionSource.allCases, id: \.self) { source in
                    if let count = sourceCounts[source], count > 0 {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(sourceColorFor(source).opacity(0.2))
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: source.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(sourceColorFor(source))
                            }
                            
                            Text(source.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.appPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.tertiarySystemBackground)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text("FILTER BY SOURCE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterChip(
                        title: "All",
                        count: automationManager.pendingTransactions.count,
                        isSelected: selectedSource == nil,
                        color: .appPrimary
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(.spring()) {
                            selectedSource = nil
                        }
                    }
                    
                    ForEach(TransactionSource.allCases, id: \.self) { source in
                        if let count = sourceCounts[source], count > 0 {
                            FilterChip(
                                title: source.rawValue,
                                count: count,
                                isSelected: selectedSource == source,
                                color: sourceColorFor(source)
                            ) {
                                HapticManager.shared.selectionChanged()
                                withAnimation(.spring()) {
                                    selectedSource = selectedSource == source ? nil : source
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Transactions List
    
    private var transactionsList: some View {
        VStack(spacing: 16) {
            HStack {
                Text("TRANSACTIONS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(filteredTransactions.count) item\(filteredTransactions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(filteredTransactions) { transaction in
                    TransactionRowView(
                        transaction: transaction,
                        onTap: {
                            HapticManager.shared.lightTap()
                            selectedTransaction = transaction
                            showingTransactionDetail = true
                        },
                        onQuickApprove: {
                            HapticManager.shared.mediumTap()
                            automationManager.approveTransaction(transaction, with: viewModel)
                            lastApprovedTransaction = transaction.merchant
                            showingApprovalFeedback = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showingApprovalFeedback = false
                            }
                        },
                        onDelete: {
                            HapticManager.shared.lightTap()
                            automationManager.deleteTransaction(transaction)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                
                VStack(spacing: 24) {
                    // Icon with animation
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                    }
                    
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("All caught up!")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("No pending transactions to review")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 12) {
                            Text("When SMS parsing or Apple Pay automation detects new transactions, they'll appear here for review.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Text("Make sure automation is properly configured to start capturing transactions automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }
                
                VStack(spacing: 16) {
                    Button(action: {
                        HapticManager.shared.lightTap()
                        showingSettings = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                            
                            Text("Open Settings")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.appPrimary, Color.appSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    // Quick setup hints
                    VStack(spacing: 12) {
                        HStack {
                            Text("QUICK SETUP")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                            
                            Spacer()
                        }
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                HapticManager.shared.lightTap()
                                showingSMSInstructions = true
                            }) {
                                SetupHintRow(
                                    icon: "message.fill",
                                    title: "SMS Automation",
                                    description: "Parse UPI transactions from SMS",
                                    color: .green
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Button(action: {
                                HapticManager.shared.lightTap()
                                showingShortcutInstructions = true
                            }) {
                                SetupHintRow(
                                    icon: "creditcard.fill",
                                    title: "Apple Pay Automation",
                                    description: "Capture Apple Pay NFC transactions",
                                    color: .blue
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color.systemBackground)
    }
    
    // MARK: - Helper Functions
    
    private func sourceColorFor(_ source: TransactionSource) -> Color {
        switch source.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        default: return .appPrimary
        }
    }
    
    private func approveAllTransactions() {
        HapticManager.shared.mediumTap()
        for transaction in automationManager.pendingTransactions {
            automationManager.approveTransaction(transaction, with: viewModel)
        }
        
        lastApprovedTransaction = "All transactions"
        showingApprovalFeedback = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingApprovalFeedback = false
        }
    }
    
    private func clearAllTransactions() {
        HapticManager.shared.lightTap()
        automationManager.pendingTransactions.removeAll()
    }
}

// MARK: - Setup Hint Row

struct SetupHintRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? color.opacity(0.3) : Color.tertiarySystemBackground)
                    .cornerRadius(6)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color.secondarySystemBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Transaction Row View

struct TransactionRowView: View {
    let transaction: AutomatedTransaction
    let onTap: () -> Void
    let onQuickApprove: () -> Void
    let onDelete: () -> Void
    
    private var sourceColor: Color {
        switch transaction.source.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        default: return .appPrimary
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Source icon
                ZStack {
                    Circle()
                        .fill(sourceColor.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: transaction.source.icon)
                        .font(.system(size: 20))
                        .foregroundColor(sourceColor)
                }
                
                // Transaction details
                VStack(alignment: .leading, spacing: 8) {
                    // Header row
                    HStack {
                        Text(transaction.merchant)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formatAmount(transaction.amount, source: transaction.source))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.appPrimary)
                    }
                    
                    // Payment method and category tags
                    HStack(spacing: 8) {
                        TransactionTag(
                            text: transaction.paymentMethod,
                            color: sourceColor
                        )
                        
                        TransactionTag(
                            text: transaction.suggestedCategory.displayName,
                            color: .orange
                        )
                        
                        Spacer()
                        
                        Text(transaction.date, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // UPI specific details
                    if transaction.source == .upi {
                        HStack(spacing: 12) {
                            if let bankName = transaction.bankName {
                                HStack(spacing: 4) {
                                    Image(systemName: "building.2")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    
                                    Text(bankName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let account = transaction.accountLastFour {
                                HStack(spacing: 4) {
                                    Image(systemName: "creditcard")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    
                                    Text("****\(account)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let upiRef = transaction.upiReference {
                                HStack(spacing: 4) {
                                    Image(systemName: "number")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    
                                    Text("Ref: \(String(upiRef.prefix(8)))...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                }
                
                // Action buttons
                VStack(spacing: 8) {
                    Button(action: onQuickApprove) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: onDelete) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(16)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            
            Button("Approve") {
                onQuickApprove()
            }
            .tint(.green)
        }
    }
    
    private func formatAmount(_ amount: Double, source: TransactionSource) -> String {
        switch source {
        case .upi:
            return "₹\(String(format: "%.2f", amount))"
        case .applePay, .manual:
            return "$\(String(format: "%.2f", amount))"
        }
    }
}

// MARK: - Transaction Tag

struct TransactionTag: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }
}

#Preview {
    TransactionAutomationView(viewModel: ExpenseViewModel(context: PersistenceController.shared.container.viewContext))
        .environmentObject(CategoryViewModel())
} 