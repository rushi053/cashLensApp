import SwiftUI

struct TransactionDetailView: View {
    let transaction: AutomatedTransaction
    @ObservedObject var viewModel: ExpenseViewModel
    
    let onApprove: (AutomatedTransaction, Expense.Category?, String?) -> Void
    let onDelete: (AutomatedTransaction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    @State private var selectedCategory: Expense.Category
    @State private var customTitle: String
    @State private var showingDeleteConfirmation = false
    
    init(transaction: AutomatedTransaction, 
         viewModel: ExpenseViewModel,
         onApprove: @escaping (AutomatedTransaction, Expense.Category?, String?) -> Void,
         onDelete: @escaping (AutomatedTransaction) -> Void) {
        self.transaction = transaction
        self.viewModel = viewModel
        self.onApprove = onApprove
        self.onDelete = onDelete
        
        _selectedCategory = State(initialValue: transaction.suggestedCategory)
        _customTitle = State(initialValue: transaction.merchant)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Transaction Header
                    transactionHeader
                    
                    // Edit Form
                    editForm
                    
                    // Action Buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Review Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete") {
                        showingDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete(transaction)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this automated transaction? This action cannot be undone.")
        }
    }
    
    // MARK: - Transaction Header
    
    private var transactionHeader: some View {
        VStack(spacing: 16) {
            // Amount
            Text(viewModel.selectedCurrency.symbol + String(format: "%.2f", transaction.amount))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            // Merchant & Date
            VStack(spacing: 8) {
                Text(transaction.merchant)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack {
                    Image(systemName: "creditcard.fill")
                    Text(transaction.paymentMethod)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                Text(transaction.date, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Edit Form
    
    private var editForm: some View {
        VStack(spacing: 16) {
            // Title Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Expense Title")
                    .font(.headline)
                
                TextField("Enter expense title", text: $customTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Category Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.headline)
                
                CategoryPicker(selectedCategory: $selectedCategory)
            }
            
            // Notes (if any)
            if let notes = transaction.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                    
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Approve Button
            Button(action: approveTransaction) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Approve & Add to Expenses")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGreen))
                .cornerRadius(12)
            }
            
            // Quick Approve with Suggestions
            if selectedCategory != transaction.suggestedCategory || customTitle != transaction.merchant {
                Button(action: approveWithOriginal) {
                    HStack {
                        Image(systemName: "wand.and.rays")
                        Text("Use Original Suggestions")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func approveTransaction() {
        let finalTitle = customTitle.isEmpty ? transaction.merchant : customTitle
        onApprove(transaction, selectedCategory, finalTitle)
        dismiss()
    }
    
    private func approveWithOriginal() {
        onApprove(transaction, transaction.suggestedCategory, transaction.merchant)
        dismiss()
    }
}

// MARK: - Category Picker

struct CategoryPicker: View {
    @Binding var selectedCategory: Expense.Category
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Expense.Category.allCases, id: \.self) { category in
                if category != .custom {
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
}

struct CategoryButton: View {
    let category: Expense.Category
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : Color(category.color))
                
                Text(category.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color(category.color) : Color(category.color).opacity(0.1)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color(category.color) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let sampleTransaction = AutomatedTransaction(
        amount: 25.67,
        merchant: "Starbucks Coffee",
        paymentMethod: "Apple Pay",
        date: Date(),
        notes: "Morning coffee"
    )
    
    TransactionDetailView(
        transaction: sampleTransaction,
        viewModel: ExpenseViewModel(),
        onApprove: { _, _, _ in },
        onDelete: { _ in }
    )
    .environmentObject(CategoryViewModel())
} 