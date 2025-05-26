import SwiftUI

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @ObservedObject var subscriptionViewModel: SubscriptionViewModel
    
    // State for form fields
    @State private var name: String
    @State private var amount: String
    @State private var startDate: Date
    @State private var frequency: Subscription.Frequency
    @State private var selectedCategory: Expense.Category
    @State private var selectedCustomCategoryId: UUID?
    @State private var notes: String
    @State private var reminderEnabled: Bool
    @State private var reminderDaysBefore: Int
    
    // Animation and UI state
    @State private var showingKeyboard = false
    @State private var showingManageCategories = false
    @State private var showingDatePicker = false
    @State private var showForm = false
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    
    // Editing mode
    let editingSubscription: Subscription?
    var isEditing: Bool { editingSubscription != nil }
    
    // Date formatter
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
    
    // Initialize for adding new subscription
    init(subscriptionViewModel: SubscriptionViewModel) {
        self.subscriptionViewModel = subscriptionViewModel
        self.editingSubscription = nil
        
        _name = State(initialValue: "")
        _amount = State(initialValue: "")
        _startDate = State(initialValue: Date())
        _frequency = State(initialValue: .monthly)
        _selectedCategory = State(initialValue: .entertainment)
        _selectedCustomCategoryId = State(initialValue: nil)
        _notes = State(initialValue: "")
        _reminderEnabled = State(initialValue: true)
        _reminderDaysBefore = State(initialValue: 1)
    }
    
    // Initialize for editing existing subscription
    init(subscriptionViewModel: SubscriptionViewModel, editingSubscription: Subscription) {
        self.subscriptionViewModel = subscriptionViewModel
        self.editingSubscription = editingSubscription
        
        _name = State(initialValue: editingSubscription.name)
        _amount = State(initialValue: String(editingSubscription.amount))
        _startDate = State(initialValue: editingSubscription.startDate)
        _frequency = State(initialValue: editingSubscription.frequency)
        _selectedCategory = State(initialValue: editingSubscription.category)
        _selectedCustomCategoryId = State(initialValue: editingSubscription.customCategoryId)
        _notes = State(initialValue: editingSubscription.notes ?? "")
        _reminderEnabled = State(initialValue: editingSubscription.reminderEnabled)
        _reminderDaysBefore = State(initialValue: editingSubscription.reminderDaysBefore)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Header
                        headerSection
                        
                        // Form sections
                        VStack(spacing: 24) {
                            basicInfoSection
                            categorySection
                            frequencySection
                            scheduleSection
                            reminderSection
                            notesSection
                        }
                        .padding(.horizontal, 24)
                        
                        // Bottom padding for save button
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 100)
                    }
                }
                
                // Save button overlay
                VStack {
                    Spacer()
                    saveButtonSection
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            categoryViewModel.loadCustomCategories()
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Subscription"),
                message: Text("Are you sure you want to delete this subscription? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteSubscription()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Navigation bar
            HStack {
                Button(action: {
                    HapticManager.shared.impact(style: .light)
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
                Text(isEditing ? "Edit Subscription" : "Add Subscription")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(isEditing ? "Update your subscription details" : "Track a new recurring expense")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 8)
    }
    
    private var basicInfoSection: some View {
        VStack(spacing: 20) {
            // Name field
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Service Name")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                TextField("Netflix, Spotify, Gym...", text: $name)
                    .font(.system(size: 17, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            
            // Amount field
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Amount")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                HStack(spacing: 16) {
                    Text(expenseViewModel.currencySymbol)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.mauve)
                    
                    TextField("0.00", text: $amount)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Category")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("Manage") {
                    showingManageCategories = true
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.mauve)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Standard categories
                    ForEach(Expense.Category.allCases.filter { $0 != .custom }, id: \.self) { category in
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
        }
    }
    
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
                    .stroke(selectedCategory == category && selectedCustomCategoryId == nil ? 
                           Color.forCategory(category.color).opacity(0.9) : 
                           Color.clear, 
                           lineWidth: 3)
            )
            .shadow(color: selectedCategory == category && selectedCustomCategoryId == nil ? 
                   Color.forCategory(category.color).opacity(0.3) : 
                   Color.clear, 
                   radius: 4, x: 0, y: 0)
            
            Text(category.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(selectedCategory == category && selectedCustomCategoryId == nil ? 
                                Color.forCategory(category.color) : .secondary)
        }
        .onTapGesture {
            HapticManager.shared.impact(style: .light)
            selectedCategory = category
            if category != .custom {
                selectedCustomCategoryId = nil
            }
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
            HapticManager.shared.impact(style: .light)
            selectedCategory = .custom
            selectedCustomCategoryId = category.id
        }
    }
    
    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Billing Frequency")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Subscription.Frequency.allCases, id: \.self) { freq in
                        ModernFrequencyButton(
                            frequency: freq,
                            isSelected: frequency == freq,
                            action: { 
                                HapticManager.shared.impact(style: .light)
                                frequency = freq 
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, -24)
        }
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Schedule")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Button(action: {
                showingDatePicker.toggle()
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.mauve.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "calendar")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.mauve)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Date")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text(dateFormatter.string(from: startDate))
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
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationView {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(WheelDatePickerStyle())
                        .navigationTitle("Start Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingDatePicker = false
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.mauve)
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
    }
    
    private var reminderSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Reminders")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Enable reminders toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payment Reminders")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Get notified before payments are due")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $reminderEnabled)
                        .labelsHidden()
                }
                
                if reminderEnabled {
                    Divider()
                    
                    // Reminder timing
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remind me")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("\(reminderDaysBefore) day\(reminderDaysBefore == 1 ? "" : "s") before due date")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Stepper("", value: $reminderDaysBefore, in: 1...7)
                            .labelsHidden()
                    }
                }
            }
            .padding(20)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
    
    private var notesSection: some View {
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
            
            TextField("Add details about this subscription...", text: $notes, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(3, reservesSpace: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
    
    private var saveButtonSection: some View {
        VStack(spacing: 0) {
            // Gradient overlay to fade content
            LinearGradient(
                colors: [Color.clear, Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            
            // Save button
            Button(action: saveSubscription) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text(isEditing ? "Update Subscription" : "Save Subscription")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: isFormValid ? 
                            [Color.mauve, Color.mauve.opacity(0.8)] : 
                            [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(
                    color: isFormValid ? Color.mauve.opacity(0.4) : Color.gray.opacity(0.2),
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
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        expenseViewModel.parseAmount(amount) != nil &&
        expenseViewModel.parseAmount(amount)! > 0
    }
    
    private func saveSubscription() {
        guard isFormValid else { return }
        
        isSaving = true
        HapticManager.shared.impact(style: .medium)
        
        guard let parsedAmount = expenseViewModel.parseAmount(amount) else {
            isSaving = false
            return
        }
        
        let subscription = Subscription(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: parsedAmount,
            currency: expenseViewModel.selectedCurrency,
            startDate: startDate,
            frequency: frequency,
            category: selectedCategory,
            customCategoryId: selectedCustomCategoryId,
            notes: notes.isEmpty ? nil : notes
        )
        
        var finalSubscription = subscription
        finalSubscription.reminderEnabled = reminderEnabled
        finalSubscription.reminderDaysBefore = reminderDaysBefore
        
        if let editingSubscription = editingSubscription {
            finalSubscription.id = editingSubscription.id
            subscriptionViewModel.updateSubscription(finalSubscription)
        } else {
            subscriptionViewModel.addSubscription(finalSubscription)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            dismiss()
        }
    }
    
    private func deleteSubscription() {
        guard let subscription = editingSubscription else { return }
        subscriptionViewModel.deleteSubscription(subscription)
        dismiss()
    }
}

// Modern Frequency Button
struct ModernFrequencyButton: View {
    let frequency: Subscription.Frequency
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected ? 
                                LinearGradient(colors: [Color.mauve, Color.mauve.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [Color(.systemGray6), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: frequency.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                
                Text(frequency.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .mauve : .secondary)
            }
            .frame(width: 80)
        }
        .buttonStyle(PlainButtonStyle())
    }
} 