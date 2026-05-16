import SwiftUI

/// Manage Categories — default + custom category management.
///
/// Visual language matches the rest of the modern settings sub-screens
/// (`AppIconPickerView`, `ThemePickerView`): grouped sections in
/// rounded card containers, generously sized icon medallions, swipe
/// actions and a primary FAB at the bottom for the "add" action so the
/// CTA is always one thumb-reach away regardless of list length.
struct ManageCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var expenseViewModel: ExpenseViewModel

    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    @State private var showingDeleteAlert = false
    @State private var categoryToDelete: CustomCategory?
    @State private var showingDeleteDefaultAlert = false
    @State private var defaultCategoryToDelete: Expense.Category?
    @State private var deletedDefaultCategories: Set<String> = []

    /// Default categories that aren't currently hidden.
    private var visibleDefaults: [Expense.Category] {
        Expense.Category.allCases.filter {
            $0 != .custom && !deletedDefaultCategories.contains($0.rawValue)
        }
    }

    private var hiddenDefaults: [Expense.Category] {
        Expense.Category.allCases.filter {
            $0 != .custom && deletedDefaultCategories.contains($0.rawValue)
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xxl) {
                        if !categoryViewModel.customCategories.isEmpty {
                            customSection
                        }
                        defaultSection

                        if !hiddenDefaults.isEmpty {
                            hiddenSection
                        }

                        // Trailing space so FAB doesn't cover the last
                        // row's swipe affordance.
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.lg)
                }

                fab
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                categoryViewModel.createDefaultCategoriesIfNeeded()
                loadDeletedDefaultCategories()
            }
            .sheet(isPresented: $showingAddCategory) {
                CustomCategoryForm(editingCategory: editingCategory)
                    .environmentObject(categoryViewModel)
            }
            .alert("Delete Custom Category", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let category = categoryToDelete {
                        categoryViewModel.deleteCustomCategory(id: category.id)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Any expenses using this category will be moved to “Other”.")
            }
            .alert("Hide Default Category", isPresented: $showingDeleteDefaultAlert) {
                Button("Hide", role: .destructive) {
                    if let category = defaultCategoryToDelete {
                        deleteDefaultCategory(category)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This hides the category everywhere. Existing expenses move to “Other”. You can restore it from the “Hidden” section anytime.")
            }
        }
    }

    // MARK: - Sections

    private var customSection: some View {
        section(title: "Your Categories", count: categoryViewModel.customCategories.count) {
            VStack(spacing: 0) {
                ForEach(Array(categoryViewModel.customCategories.enumerated()), id: \.element.id) { index, category in
                    customRow(category)
                    if index < categoryViewModel.customCategories.count - 1 {
                        rowDivider
                    }
                }
            }
            .cardSurface()
            .softShadow()
        }
    }

    private var defaultSection: some View {
        section(title: "Default Categories", count: visibleDefaults.count) {
            VStack(spacing: 0) {
                ForEach(Array(visibleDefaults.enumerated()), id: \.element) { index, category in
                    defaultRow(category)
                    if index < visibleDefaults.count - 1 {
                        rowDivider
                    }
                }
            }
            .cardSurface()
            .softShadow()
        }
    }

    private var hiddenSection: some View {
        section(title: "Hidden", count: hiddenDefaults.count) {
            VStack(spacing: 0) {
                ForEach(Array(hiddenDefaults.enumerated()), id: \.element) { index, category in
                    hiddenRow(category)
                    if index < hiddenDefaults.count - 1 {
                        rowDivider
                    }
                }
            }
            .cardSurface()
            .softShadow()
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.tertiaryLabel)
            }
            content()
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 64)
            .opacity(0.5)
    }

    // MARK: - Rows

    private func customRow(_ category: CustomCategory) -> some View {
        let tint = Color.forCategory(category.colorName)
        return Button {
            HapticManager.shared.lightTap()
            editingCategory = category
            showingAddCategory = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: category.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Custom")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.tertiaryLabel)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                HapticManager.shared.warning()
                categoryToDelete = category
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func defaultRow(_ category: Expense.Category) -> some View {
        let tint = Color.forCategory(category.color)
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
            }

            Text(category.rawValue)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer(minLength: 0)

            Text("Built-in")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.secondarySystemBackground)
                )
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                HapticManager.shared.warning()
                defaultCategoryToDelete = category
                showingDeleteDefaultAlert = true
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
        }
    }

    private func hiddenRow(_ category: Expense.Category) -> some View {
        let tint = Color.forCategory(category.color)
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint.opacity(0.55))
            }

            Text(category.rawValue)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Button {
                HapticManager.shared.success()
                restoreDefaultCategory(category)
            } label: {
                Text("Restore")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.appPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.appPrimary.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - FAB

    private var fab: some View {
        // Solid CTA strip — hairline divider rather than a fade gradient
        // separates it from the scrolling content above.
        VStack(spacing: 0) {
            Divider().opacity(0.35)

            Button {
                HapticManager.shared.mediumTap()
                editingCategory = nil
                showingAddCategory = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                    Text("Add Category")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.appPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(color: Color.appPrimary.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Helpers

    private func loadDeletedDefaultCategories() {
        if let deleted = UserDefaults.standard.array(forKey: UserDefaultsKeys.deletedDefaultCategories) as? [String] {
            deletedDefaultCategories = Set(deleted)
        }
    }

    private func saveDeletedDefaultCategories() {
        UserDefaults.standard.set(Array(deletedDefaultCategories), forKey: UserDefaultsKeys.deletedDefaultCategories)
    }

    private func deleteDefaultCategory(_ category: Expense.Category) {
        expenseViewModel.moveExpensesFromDeletedCategory(category.rawValue)
        withAnimation(Theme.Motion.tap) {
            deletedDefaultCategories.insert(category.rawValue)
        }
        saveDeletedDefaultCategories()
    }

    private func restoreDefaultCategory(_ category: Expense.Category) {
        withAnimation(Theme.Motion.tap) {
            deletedDefaultCategories.remove(category.rawValue)
        }
        saveDeletedDefaultCategories()
    }
}

struct ManageCategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        ManageCategoriesView()
            .environmentObject(CategoryViewModel())
            .environmentObject(ExpenseViewModel())
    }
}
