import SwiftUI

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    // State for form fields when adding new expense
    @State private var title: String
    @State private var amount: String
    @State private var date: Date
    @State private var selectedCategory: Expense.Category
    @State private var selectedCustomCategoryId: UUID?
    @State private var notes: String
    @State private var showingKeyboard: Bool
    @State private var showingManageCategories: Bool
    @State private var showingDatePicker: Bool
    
    // Animation states
    @State private var animateCircle: Bool
    @State private var showForm: Bool
    @State private var animateButton: Bool
    @State private var isSaving: Bool = false
    
    // Additional parameters
    var isEditing: Bool
    var onSave: ((String, Double, Date, Expense.Category, UUID?, String?) -> Void)?
    var expenseId: UUID?
    @State private var showingDeleteConfirmation = false
    
    // Date formatter
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mma"
        return formatter
    }()
    
    // Initialize for adding new expense
    init(viewModel: ExpenseViewModel) {
        self.viewModel = viewModel
        self.isEditing = false
        self.onSave = nil
        
        // Initialize state
        _title = State(initialValue: "")
        _amount = State(initialValue: "")
        _date = State(initialValue: Date())
        _selectedCategory = State(initialValue: .food)
        _selectedCustomCategoryId = State(initialValue: nil)
        _notes = State(initialValue: "")
        _showingKeyboard = State(initialValue: false)
        _showingManageCategories = State(initialValue: false)
        _showingDatePicker = State(initialValue: false)
        _animateCircle = State(initialValue: false)
        _showForm = State(initialValue: false)
        _animateButton = State(initialValue: false)
        _isSaving = State(initialValue: false)
    }
    
    // Initialize for editing existing expense
    init(
        viewModel: ExpenseViewModel,
        title: String,
        amount: String,
        date: Date,
        selectedCategory: Expense.Category,
        selectedCustomCategoryId: UUID?,
        notes: String,
        isEditing: Bool,
        expenseId: UUID,
        onSave: @escaping (String, Double, Date, Expense.Category, UUID?, String?) -> Void
    ) {
        self.viewModel = viewModel
        self.isEditing = isEditing
        self.onSave = onSave
        self.expenseId = expenseId
        
        // Initialize state with provided values
        _title = State(initialValue: title)
        _amount = State(initialValue: amount)
        _date = State(initialValue: date)
        _selectedCategory = State(initialValue: selectedCategory)
        _selectedCustomCategoryId = State(initialValue: selectedCustomCategoryId)
        _notes = State(initialValue: notes)
        _showingKeyboard = State(initialValue: false)
        _showingManageCategories = State(initialValue: false)
        _showingDatePicker = State(initialValue: false)
        _animateCircle = State(initialValue: false)
        _showForm = State(initialValue: false)
        _animateButton = State(initialValue: false)
        _isSaving = State(initialValue: false)
        _showingDeleteConfirmation = State(initialValue: false)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.systemBackground.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                    }
                    .padding()
                    
                    Spacer()
                    
                    Text(isEditing ? "Edit Expense" : "Add Expense")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // Delete button (only shown in edit mode)
                    if isEditing {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .foregroundColor(.red)
                        }
                        .padding()
                    } else {
                        // Empty view for balance when not in edit mode
                        Color.clear
                            .frame(width: 20, height: 20)
                            .padding()
                    }
                }
                
                // Form
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 30) {
                        // Amount field first
                        amountField
                        
                        // Title field second
                        titleField
                        
                        // Category field third
                        categoryPickerField
                        
                        // Date field fourth
                        datePickerField
                        
                        // Notes field last
                        notesField
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                    .onAppear {
                        // This forces a re-render of the view
                        if isEditing {
                            showForm = true
                        }
                    }
                }
                
                // Save button
                saveButton
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Load categories immediately when view appears
            categoryViewModel.loadCustomCategories()
            
            // Skip animation delay when editing to avoid blank form
            if isEditing {
                // Instantly show the form when editing
                animateCircle = true
                showForm = true
                animateButton = true
            } else {
                // Animate in add mode
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animateCircle = true
                    showForm = true
                    animateButton = true
                }
            }
        }
        // Delete confirmation alert
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Expense"),
                message: Text("Are you sure you want to delete this expense? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    // Delete the expense
                    deleteExpense()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - View Components
    
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField("Expense title", text: $title)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(Color.secondarySystemBackground)
                .cornerRadius(16)
                .onTapGesture {
                    showingKeyboard = true
                }
        }
    }
    
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Amount")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(viewModel.selectedCurrency.symbol)
                    .font(.headline)
                    .foregroundColor(.appPrimary)
            }
            
            TextField("0.00", text: $amount)
                .font(.system(size: 32, weight: .medium))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(.systemGray))
                .padding(.vertical, 16)
                .background(Color.secondarySystemBackground)
                .cornerRadius(16)
                .onTapGesture {
                    showingKeyboard = true
                }
        }
    }
    
    private var datePickerField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.appPrimary)
                    .padding(.leading, 8)
                
                Text(dateFormatter.string(from: date))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
            .onTapGesture {
                showingDatePicker = true
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            VStack {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .presentationDetents([.height(300)])
                
                Button("Done") {
                    showingDatePicker = false
                }
                .font(.headline)
                .foregroundColor(.appPrimary)
                .padding()
            }
            .presentationBackground(Color.secondarySystemBackground)
        }
    }
    
    private var categoryPickerField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Category")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    showingManageCategories = true
                }) {
                    HStack(spacing: 6) {
                        Text("Manage")
                            .foregroundColor(.appPrimary)
                        
                        Image(systemName: "gearshape.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.appPrimary)
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Standard categories (excluding deleted ones)
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        categoryButton(category)
                    }
                    
                    // Custom categories
                    ForEach(categoryViewModel.customCategories) { category in
                        customCategoryButton(category)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingManageCategories, onDismiss: {
            // Reload custom categories when returning from manage categories
            categoryViewModel.loadCustomCategories()
        }) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(viewModel)
        }
        .onAppear {
            // Make sure we have the latest custom categories
            categoryViewModel.loadCustomCategories()
        }
    }
    
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes (Optional)")
                .font(.headline)
                .foregroundColor(.primary)
            
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add details here...")
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                        .padding(.leading, 16)
                }
                
                TextEditor(text: $notes)
                    .frame(height: 120)
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .onTapGesture {
                        showingKeyboard = true
                    }
            }
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
        }
    }
    
    // Computed property to check if form is valid
    private var isFormValid: Bool {
        if isEditing {
            // For editing, we only need a non-empty title and a valid amount
            let parsedAmount = viewModel.parseAmount(amount)
            // In edit mode, don't require the amount to be positive, just valid
            return !title.isEmpty && parsedAmount != nil
        } else {
            // For new expenses, we need a non-empty title and a positive amount
            return !title.isEmpty && 
                   !amount.isEmpty && 
                   (viewModel.parseAmount(amount) ?? 0) > 0
        }
    }
    
    private var saveButton: some View {
        Button(action: {
            guard let amountValue = viewModel.parseAmount(amount) else { return }
            
            // Start saving animation
            isSaving = true
            
            if let onSave = onSave {
                // Enhanced haptic feedback for edit operation
                HapticManager.shared.mediumTap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    HapticManager.shared.success()
                }
                
                onSave(
                    title,
                    amountValue,
                    date,
                    selectedCategory,
                    selectedCategory == .custom ? selectedCustomCategoryId : nil,
                    notes.isEmpty ? nil : notes
                )
                
                // Slight delay to show success state before dismissing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            } else {
                addExpense()
            }
        }) {
            if isSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(30)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
            } else {
                Text(isEditing ? "Update Expense" : "Add Expense")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        isFormValid ?
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(30)
                    .shadow(
                        color: isFormValid ? Color.appPrimary.opacity(0.3) : Color.clear,
                        radius: 4, x: 0, y: 2
                    )
            }
        }
        .disabled(!isFormValid)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Helper Views
    
    private func categoryButton(_ category: Expense.Category) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.forCategory(category.color).opacity(0.3))
                    .frame(width: 65, height: 65)
                
                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(Color.forCategory(category.color))
            }
            .overlay(
                Circle()
                    .stroke(selectedCategory == category ? 
                           Color.forCategory(category.color).opacity(0.9) : 
                           Color.clear, 
                           lineWidth: 3)
            )
            .shadow(color: selectedCategory == category ? 
                   Color.forCategory(category.color).opacity(0.3) : 
                   Color.clear, 
                   radius: 4, x: 0, y: 0)
            
            Text(category.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(selectedCategory == category ? Color.forCategory(category.color) : .secondary)
        }
        .onTapGesture {
            selectedCategory = category
            if category != .custom {
                selectedCustomCategoryId = nil
            }
            HapticManager.shared.lightTap()
        }
    }
    
    private func customCategoryButton(_ category: CustomCategory) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.forCategory(category.colorName).opacity(0.3))
                    .frame(width: 65, height: 65)
                
                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(Color.forCategory(category.colorName))
            }
            .overlay(
                Circle()
                    .stroke(selectedCategory == .custom && selectedCustomCategoryId == category.id ? 
                           Color.forCategory(category.colorName).opacity(0.9) : 
                           Color.clear, 
                           lineWidth: 3)
            )
            .shadow(color: selectedCategory == .custom && selectedCustomCategoryId == category.id ? 
                   Color.forCategory(category.colorName).opacity(0.3) : 
                   Color.clear, 
                   radius: 4, x: 0, y: 0)
            
            Text(category.name)
                .font(.caption)
                .foregroundColor(selectedCategory == .custom && selectedCustomCategoryId == category.id ? 
                                Color.forCategory(category.colorName) : .secondary)
        }
        .onTapGesture {
            selectedCategory = .custom
            selectedCustomCategoryId = category.id
            HapticManager.shared.lightTap()
        }
    }
    
    // MARK: - Actions
    
    private func addExpense() {
        guard let amountValue = viewModel.parseAmount(amount) else { return }
        
        // Enhanced haptic feedback sequence
        HapticManager.shared.mediumTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticManager.shared.success()
        }
        
        // Create new expense
        let newExpense = Expense(
            title: title,
            amount: amountValue,
            currency: viewModel.selectedCurrency,
            date: date,
            category: selectedCategory,
            notes: notes.isEmpty ? nil : notes,
            customCategoryId: selectedCategory == .custom ? selectedCustomCategoryId : nil
        )
        
        // Add to view model
        viewModel.addExpense(newExpense)
        
        // Dismiss the view
        dismiss()
    }
    
    // MARK: - Delete Expense
    
    private func deleteExpense() {
        guard let id = expenseId else { return }
        
        // Use a safer approach that doesn't rely on array indices directly
        // This helps prevent "index out of range" errors
        viewModel.deleteExpenseById(id)
        
        // Haptic feedback for deletion
        HapticManager.shared.success()
        
        // Dismiss the view
        dismiss()
    }
}

struct AddExpenseView_Previews: PreviewProvider {
    static var previews: some View {
        AddExpenseView(viewModel: ExpenseViewModel())
    }
} 