import SwiftUI

/// Add / Edit Subscription screen.
///
/// Structural twin of `AddExpenseView` and `BudgetSetupView`: custom header
/// (no nav bar), bold rounded field labels, `.fieldCard()` inputs, circular
/// category picker, and the same fixed bottom save button with a fade-to-
/// background gradient.
struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @ObservedObject var subscriptionViewModel: SubscriptionViewModel

    // MARK: - State

    @State private var name: String
    @State private var amountText: String
    @State private var startDate: Date
    @State private var frequency: Subscription.Frequency
    @State private var selectedCategory: Expense.Category
    @State private var selectedCustomCategoryId: UUID?
    @State private var notes: String
    @State private var reminderEnabled: Bool
    @State private var reminderDaysBefore: Int

    @State private var showingManageCategories = false
    @State private var showingDatePicker = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    // PERF: Removed `showForm` — it was only set inside `onAppear` via
    // `withAnimation(Theme.Motion.emphasized)` and never read by any
    // view, so the only effect was an animation transaction that
    // competed with the system sheet spring on present.

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, amount, notes }

    // MARK: - Init

    let editingSubscription: Subscription?
    var isEditing: Bool { editingSubscription != nil }

    init(subscriptionViewModel: SubscriptionViewModel) {
        self.subscriptionViewModel = subscriptionViewModel
        self.editingSubscription = nil

        _name = State(initialValue: "")
        _amountText = State(initialValue: "")
        _startDate = State(initialValue: Date())
        _frequency = State(initialValue: .monthly)
        _selectedCategory = State(initialValue: .entertainment)
        _selectedCustomCategoryId = State(initialValue: nil)
        _notes = State(initialValue: "")
        _reminderEnabled = State(initialValue: true)
        _reminderDaysBefore = State(initialValue: 1)
    }

    init(subscriptionViewModel: SubscriptionViewModel, editingSubscription: Subscription) {
        self.subscriptionViewModel = subscriptionViewModel
        self.editingSubscription = editingSubscription

        _name = State(initialValue: editingSubscription.name)
        _amountText = State(initialValue: String(format: "%.2f", editingSubscription.amount))
        _startDate = State(initialValue: editingSubscription.startDate)
        _frequency = State(initialValue: editingSubscription.frequency)
        _selectedCategory = State(initialValue: editingSubscription.category)
        _selectedCustomCategoryId = State(initialValue: editingSubscription.customCategoryId)
        _notes = State(initialValue: editingSubscription.notes ?? "")
        _reminderEnabled = State(initialValue: editingSubscription.reminderEnabled)
        _reminderDaysBefore = State(initialValue: editingSubscription.reminderDaysBefore)
    }

    // MARK: - Tokens

    private static let fieldLabelFont = Font.system(size: 18, weight: .bold, design: .rounded)

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xxxl - 4) {
                        amountField
                        nameField
                        frequencyField
                        scheduleField
                        categoryPickerField
                        reminderField
                        notesField

                        if isEditing {
                            deleteSection
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.sm + 2)
                    .padding(.bottom, 40)
                }

                saveButton
            }
        }
        .navigationBarHidden(true)
        .alert("Delete Subscription?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSubscription() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showingManageCategories) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(expenseViewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Button(action: {
                    HapticManager.shared.lightTap()
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
                        HapticManager.shared.warning()
                        showDeleteConfirm = true
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
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                Text(isEditing ? "Edit Subscription" : "New Subscription")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(isEditing ? "Update your subscription details" : "Track a recurring expense")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Amount

    private var amountField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Amount")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            HStack(spacing: Theme.Spacing.lg) {
                Text(expenseViewModel.selectedCurrency.symbol)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)

                TextField("0.00", text: $amountText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .fieldCard(isFocused: focusedField == .amount)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .amount }
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Service Name")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            TextField("Netflix, Spotify, Gym…", text: $name)
                .font(.system(size: 17, weight: .medium))
                .focused($focusedField, equals: .name)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: focusedField == .name)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .name }
        }
    }

    // MARK: - Frequency

    private var frequencyField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Billing Frequency")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(Subscription.Frequency.allCases, id: \.self) { freq in
                        frequencyButton(freq)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .padding(.horizontal, -Theme.Spacing.xs)
        }
    }

    private func frequencyButton(_ freq: Subscription.Frequency) -> some View {
        let isSelected = frequency == freq
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) { frequency = freq }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: freq.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(freq.rawValue)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md + 2)
            .background(
                Group {
                    if isSelected {
                        Color.appPrimary
                    } else {
                        Color.secondarySystemBackground
                    }
                }
            )
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? Color.appPrimary.opacity(0.3) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule

    private var scheduleField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Start Date")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            Button {
                HapticManager.shared.lightTap()
                focusedField = nil
                showingDatePicker = true
            } label: {
                HStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Color.appPrimary.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateFormatter.string(from: startDate))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(nextPreviewText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md + 2)
                .fieldCard()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDatePicker) {
                NavigationView {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("Start Date")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingDatePicker = false }
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.appPrimary)
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// Preview string shown under the start date explaining when the next
    /// billing occurrence falls, so the schedule feels predictable.
    private var nextPreviewText: String {
        let next = Subscription.calculateNextDueDate(from: startDate, frequency: frequency)
        return "Next: \(dateFormatter.string(from: next)) · \(frequency.description)"
    }

    // MARK: - Category picker

    private var categoryPickerField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Category")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    HapticManager.shared.lightTap()
                    showingManageCategories = true
                } label: {
                    HStack(spacing: 6) {
                        Text("Manage")
                            .foregroundColor(.appPrimary)
                        Image(systemName: "gearshape.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.appPrimary)
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xl) {
                    ForEach(expenseViewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        categoryButton(category)
                    }

                    ForEach(categoryViewModel.customCategories) { category in
                        customCategoryButton(category)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private func categoryButton(_ category: Expense.Category) -> some View {
        let isSelected = selectedCategory == category && selectedCustomCategoryId == nil
        let tint = Color.forCategory(category.color)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.3))
                    .frame(width: 65, height: 65)

                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(tint)
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? tint.opacity(0.9) : Color.clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? tint.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 0)

            Text(category.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(isSelected ? tint : .secondary)
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            withAnimation(Theme.Motion.snappy) {
                selectedCategory = category
                if category != .custom { selectedCustomCategoryId = nil }
            }
        }
    }

    private func customCategoryButton(_ category: CustomCategory) -> some View {
        let isSelected = selectedCategory == .custom && selectedCustomCategoryId == category.id
        let tint = Color.forCategory(category.colorName)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.3))
                    .frame(width: 65, height: 65)

                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(tint)
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? tint.opacity(0.9) : Color.clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? tint.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 0)

            Text(category.name)
                .font(.caption)
                .foregroundColor(isSelected ? tint : .secondary)
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            withAnimation(Theme.Motion.snappy) {
                selectedCategory = .custom
                selectedCustomCategoryId = category.id
            }
        }
    }

    // MARK: - Reminder

    private var reminderField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Reminder")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }

            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Color.appPrimary.opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: reminderEnabled ? "bell.fill" : "bell.slash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Payment reminder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(reminderEnabled
                             ? "Notify me \(reminderDaysBefore) day\(reminderDaysBefore == 1 ? "" : "s") before"
                             : "No reminder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $reminderEnabled.animation(Theme.Motion.snappy))
                        .labelsHidden()
                        .tint(.appPrimary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)

                if reminderEnabled {
                    Divider().padding(.horizontal, Theme.Spacing.lg)

                    HStack(spacing: Theme.Spacing.md) {
                        Text("Days before")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach([1, 2, 3, 7], id: \.self) { d in
                                reminderDayChip(d)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .cardSurface()
            .softShadow()
        }
    }

    private func reminderDayChip(_ days: Int) -> some View {
        let isSelected = reminderDaysBefore == days
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) { reminderDaysBefore = days }
        } label: {
            Text("\(days)d")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(minWidth: 34)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Group {
                        if isSelected {
                            Color.appPrimary
                        } else {
                            Color.primary.opacity(0.06)
                        }
                    }
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Notes")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }

            TextField("Plan details, account email…", text: $notes, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(3, reservesSpace: true)
                .focused($focusedField, equals: .notes)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: focusedField == .notes)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .notes }
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            HapticManager.shared.warning()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "trash.fill")
                Text("Delete Subscription")
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        // Solid bottom CTA strip — hairline divider replaces the
        // fade-to-background gradient and the button is a flat
        // primary color (no gradient fill).
        VStack(spacing: 0) {
            Divider().opacity(0.35)

            Button(action: handleSaveTap) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text(isEditing ? "Save Changes" : "Add Subscription")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isValid ? Color.appPrimary : Color.gray.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(
                    color: isValid ? Color.appPrimary.opacity(0.3) : Color.gray.opacity(0.18),
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }
            .disabled(!isValid || isSaving)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
            .background(Color(.systemGroupedBackground))
        }
    }

    private func handleSaveTap() {
        guard isValid else { return }
        focusedField = nil
        isSaving = true
        HapticManager.shared.mediumTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticManager.shared.success()
        }
        saveSubscription()
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard let parsed = expenseViewModel.parseAmount(amountText), parsed > 0 else {
            return false
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Persistence

    private func saveSubscription() {
        guard let parsedAmount = expenseViewModel.parseAmount(amountText) else {
            isSaving = false
            return
        }

        var subscription = Subscription(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: parsedAmount,
            currency: expenseViewModel.selectedCurrency,
            startDate: startDate,
            frequency: frequency,
            category: selectedCategory,
            customCategoryId: selectedCustomCategoryId,
            notes: notes.isEmpty ? nil : notes
        )
        subscription.reminderEnabled = reminderEnabled
        subscription.reminderDaysBefore = reminderDaysBefore

        Task {
            if let editing = editingSubscription {
                subscription.id = editing.id
                subscription.isActive = editing.isActive
                subscription.nextDueDate = editing.nextDueDate
                await subscriptionViewModel.updateSubscription(subscription)
            } else {
                await subscriptionViewModel.addSubscription(subscription)
            }

            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isSaving = false
                    dismiss()
                }
            }
        }
    }

    private func deleteSubscription() {
        guard let subscription = editingSubscription else { return }
        HapticManager.shared.mediumTap()
        subscriptionViewModel.deleteSubscription(subscription)
        HapticManager.shared.success()
        dismiss()
    }
}
