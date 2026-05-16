import SwiftUI

/// Add / Edit Budget screen.
///
/// Structural twin of `AddExpenseView`: custom header (no nav bar), bold rounded
/// field labels, `cardSurface().softShadow()` inputs, circular category picker,
/// and the same fixed bottom save button with a fade-to-background gradient.
struct BudgetSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager

    // MARK: - State

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var period: Budget.Period = .monthly
    @State private var categoryFilter: Budget.CategoryFilter = .overall
    @State private var alertAt80 = true
    @State private var alertAt100 = true
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    // PERF: Removed `showForm` — it was only set inside `onAppear` via
    // `withAnimation(Theme.Motion.emphasized)` and never read by any
    // view, so the only effect was an animation transaction that
    // competed with the system sheet spring on present.

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, amount }

    // MARK: - Init

    var editingBudget: Budget?
    var isEditing: Bool { editingBudget != nil }

    // MARK: - Tokens

    private static let fieldLabelFont = Font.system(size: 18, weight: .bold, design: .rounded)

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
                        periodField
                        categoryPickerField
                        alertsField

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
        .onAppear {
            if !proManager.isPro {
                dismiss()
                return
            }
            loadEditingData()
        }
        .alert("Delete Budget?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let budget = editingBudget {
                    budgetViewModel.deleteBudget(budget)
                }
                HapticManager.shared.success()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Button(action: { dismiss() }) {
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
                Text(isEditing ? "Edit Budget" : "New Budget")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(isEditing ? "Update your budget details" : "Set a new spending limit")
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
                Text("Budget Amount")
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
                Text("Name")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            TextField("e.g. Monthly Spending", text: $name)
                .font(.system(size: 17, weight: .medium))
                .focused($focusedField, equals: .name)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: focusedField == .name)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .name }
        }
    }

    // MARK: - Period

    private var periodField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Period")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            HStack(spacing: Theme.Spacing.md) {
                ForEach(Budget.Period.allCases, id: \.self) { p in
                    periodButton(p)
                }
            }
        }
    }

    private func periodButton(_ p: Budget.Period) -> some View {
        let isSelected = period == p
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) { period = p }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: p.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(p.rawValue)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg)
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(
                color: isSelected ? Color.appPrimary.opacity(0.3) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 6,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category picker

    private var categoryPickerField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Apply To")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xl) {
                    allSpendingButton

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

    private var allSpendingButton: some View {
        let isSelected = categoryFilter == .overall
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.3))
                    .frame(width: 65, height: 65)

                Image(systemName: "creditcard.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.appPrimary)
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.appPrimary.opacity(0.9) : Color.clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? Color.appPrimary.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 0)

            Text("All")
                .font(.caption)
                .foregroundColor(isSelected ? .appPrimary : .secondary)
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            withAnimation(Theme.Motion.snappy) {
                categoryFilter = .overall
            }
        }
    }

    private func categoryButton(_ category: Expense.Category) -> some View {
        let isSelected = categoryFilter == .defaultCategory(category.rawValue)
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
                categoryFilter = .defaultCategory(category.rawValue)
            }
        }
    }

    private func customCategoryButton(_ category: CustomCategory) -> some View {
        let isSelected = categoryFilter == .customCategory(category.id)
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
                categoryFilter = .customCategory(category.id)
            }
        }
    }

    // MARK: - Alerts

    private var alertsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Alerts")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }

            VStack(spacing: 0) {
                alertToggle(
                    label: "At 80% spent",
                    sublabel: "Get a heads-up as you approach the limit",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    isOn: $alertAt80
                )

                Divider().padding(.horizontal, Theme.Spacing.lg)

                alertToggle(
                    label: "At 100% spent",
                    sublabel: "Notify me when I reach the full budget",
                    icon: "xmark.octagon.fill",
                    color: .red,
                    isOn: $alertAt100
                )
            }
            .cardSurface()
            .softShadow()
        }
    }

    private func alertToggle(
        label: String,
        sublabel: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Text(sublabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.appPrimary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button(role: .destructive) {
            HapticManager.shared.warning()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "trash.fill")
                Text("Delete Budget")
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
                        Text(isEditing ? "Save Changes" : "Create Budget")
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
        isSaving = true
        HapticManager.shared.mediumTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticManager.shared.success()
        }
        save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else {
            return false
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Persistence

    private func save() {
        guard proManager.isPro else {
            dismiss()
            return
        }
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }

        var alertPercentages: [Double] = []
        if alertAt80 { alertPercentages.append(0.8) }
        if alertAt100 { alertPercentages.append(1.0) }

        if var budget = editingBudget {
            budget.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            budget.amount = amount
            budget.period = period
            budget.categoryFilter = categoryFilter
            budget.alertAtPercentages = alertPercentages
            budgetViewModel.updateBudget(budget)
        } else {
            let budget = Budget(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                period: period,
                categoryFilter: categoryFilter,
                alertAtPercentages: alertPercentages
            )
            budgetViewModel.addBudget(budget)
        }
    }

    private func loadEditingData() {
        guard let budget = editingBudget else { return }
        name = budget.name
        amountText = String(format: "%.2f", budget.amount)
        period = budget.period
        categoryFilter = budget.categoryFilter
        alertAt80 = budget.alertAtPercentages.contains(0.8)
        alertAt100 = budget.alertAtPercentages.contains(1.0)
    }
}
