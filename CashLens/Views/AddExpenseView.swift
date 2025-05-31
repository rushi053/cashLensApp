import SwiftUI

// MARK: - Draft Data Model

private struct ExpenseDraft: Codable {
    let title: String
    let amount: String
    let date: Date
    let selectedCategory: Expense.Category
    let selectedCustomCategoryId: UUID?
    let notes: String
    let timestamp: Date
    
    init(title: String, amount: String, date: Date, selectedCategory: Expense.Category, selectedCustomCategoryId: UUID?, notes: String) {
        self.title = title
        self.amount = amount
        self.date = date
        self.selectedCategory = selectedCategory
        self.selectedCustomCategoryId = selectedCustomCategoryId
        self.notes = notes
        self.timestamp = Date()
    }
}

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showingDraftRestored = false
    
    // Draft state key
    private let draftKey = "expense_draft"
    
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
        
        // Try to restore draft state for new expenses
        let draftData = UserDefaults.standard.data(forKey: "expense_draft")
        let draft = draftData.flatMap { try? JSONDecoder().decode(ExpenseDraft.self, from: $0) }
        
        // Initialize state
        _title = State(initialValue: draft?.title ?? "")
        _amount = State(initialValue: draft?.amount ?? "")
        _date = State(initialValue: draft?.date ?? Date())
        _selectedCategory = State(initialValue: draft?.selectedCategory ?? .food)
        _selectedCustomCategoryId = State(initialValue: draft?.selectedCustomCategoryId)
        _notes = State(initialValue: draft?.notes ?? "")
        _showingKeyboard = State(initialValue: false)
        _showingManageCategories = State(initialValue: false)
        _showingDatePicker = State(initialValue: false)
        _animateCircle = State(initialValue: false)
        _showForm = State(initialValue: false)
        _animateButton = State(initialValue: false)
        _isSaving = State(initialValue: false)
        _showingDraftRestored = State(initialValue: draft != nil && (!draft!.title.isEmpty || !draft!.amount.isEmpty || !draft!.notes.isEmpty))
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
            // Background - modernized
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header - modernized
                VStack(spacing: 16) {
                    // Navigation bar
                    HStack {
                        Button(action: {
                            // Clear draft if it's a new expense being dismissed
                            if !isEditing {
                                clearDraft()
                            }
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(.systemGray6))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Delete button (only shown in edit mode)
                        if isEditing {
                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.red)
                                    .frame(width: 32, height: 32)
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // Title
                    VStack(spacing: 8) {
                        Text(isEditing ? "Edit Expense" : "Add Expense")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(isEditing ? "Update your expense details" : "Track a new expense")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)

                // Form
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Draft restored notification
                        if showingDraftRestored && !isEditing {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.appPrimary)
                                
                                Text("Previous draft restored")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button("Dismiss") {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        showingDraftRestored = false
                                    }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appPrimary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.appPrimary.opacity(0.1))
                            .cornerRadius(12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

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
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                    .onAppear {
                        // This forces a re-render of the view
                        if isEditing {
                            showForm = true
                        }
                    }
                }
                
                // Save button - modernized
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
        // Auto-save draft functionality for new expenses
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && !isEditing {
                saveDraft()
            }
        }
        .onChange(of: title) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: amount) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: selectedCustomCategoryId) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: notes) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: date) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
    }
    
    // MARK: - View Components
    
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Title")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            TextField("Expense title", text: $title)
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .onTapGesture {
                    showingKeyboard = true
                }
        }
    }
    
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Amount")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack(spacing: 16) {
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)
                
                TextField("0.00", text: $amount)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            .onTapGesture {
                showingKeyboard = true
            }
        }
    }
    
    private var datePickerField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Date")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Button(action: {
                showingDatePicker = true
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appPrimary.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "calendar")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Date")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text(dateFormatter.string(from: date))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
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
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.appPrimary)
                .padding()
            }
            .presentationBackground(Color(.systemGroupedBackground))
        }
    }
    
    private var categoryPickerField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Category")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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
                .font(.system(size: 15, weight: .semibold))
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
                .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $showingManageCategories) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(viewModel)
        }
    }
    
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notes")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            TextField("Add details about this expense...", text: $notes, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(3, reservesSpace: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .onTapGesture {
                    showingKeyboard = true
                }
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
        VStack(spacing: 0) {
            // Gradient overlay to fade content
            LinearGradient(
                colors: [Color.clear, Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            
            // Save button
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
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text(isEditing ? "Update Expense" : "Add Expense")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: isFormValid ? 
                            [Color.appPrimary, Color.appPrimary.opacity(0.8)] : 
                            [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(
                    color: isFormValid ? Color.appPrimary.opacity(0.4) : Color.gray.opacity(0.2),
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }
            .disabled(!isFormValid || isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .background(Color(.systemGroupedBackground))
        }
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
        
        // Clear draft when expense is successfully added
        clearDraft()
        
        // Dismiss the view
        dismiss()
    }
    
    // MARK: - Draft Management
    
    @State private var draftSaveTimer: Timer?
    
    private func saveDraftWithDelay() {
        // Debounce the save operation to avoid excessive UserDefaults writes
        draftSaveTimer?.invalidate()
        draftSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            saveDraft()
        }
    }
    
    private func saveDraft() {
        // Only save draft if there's meaningful content and it's a new expense
        guard !isEditing && (!title.isEmpty || !amount.isEmpty || !notes.isEmpty) else {
            return
        }
        
        let draft = ExpenseDraft(
            title: title,
            amount: amount,
            date: date,
            selectedCategory: selectedCategory,
            selectedCustomCategoryId: selectedCustomCategoryId,
            notes: notes
        )
        
        if let encoded = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(encoded, forKey: draftKey)
        }
    }
    
    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        draftSaveTimer?.invalidate()
    }
    
    private func hasDraft() -> Bool {
        return UserDefaults.standard.data(forKey: draftKey) != nil
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