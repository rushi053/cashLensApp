import SwiftUI

struct QuickSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    @State private var searchText = ""
    @State private var selectedExpense: Expense?
    @FocusState private var isSearchFocused: Bool
    
    // Debounced search results
    @State private var searchResults: [Expense] = []
    @State private var searchTask: Task<Void, Never>?
    
    private var hasResults: Bool {
        !searchResults.isEmpty
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                searchBar
                
                // Results
                if searchText.isEmpty {
                    recentSearchesView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .background(Color.systemBackground)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.appPrimary)
                }
            }
        }
        .onAppear {
            // Auto-focus the search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFocused = true
            }
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
        .sheet(item: $selectedExpense) { expense in
            AddExpenseView(
                viewModel: viewModel,
                title: expense.title,
                amount: viewModel.formattedAmount(expense.amount),
                date: expense.date,
                selectedCategory: expense.category,
                selectedCustomCategoryId: expense.customCategoryId,
                notes: expense.notes ?? "",
                isEditing: true,
                expenseId: expense.id,
                onSave: { title, amount, date, category, customCategoryId, notes in
                    var updatedExpense = expense
                    updatedExpense.title = title
                    updatedExpense.amount = amount
                    updatedExpense.date = date
                    updatedExpense.category = category
                    updatedExpense.customCategoryId = customCategoryId
                    updatedExpense.notes = notes
                    viewModel.updateExpense(updatedExpense)
                    // Refresh search results
                    performSearch(query: searchText)
                }
            )
            .environmentObject(categoryViewModel)
        }
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 18))
                
                TextField("Search expenses...", text: $searchText)
                    .font(.body)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !searchText.isEmpty {
                    Button(action: {
                        HapticManager.shared.lightTap()
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 18))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.secondarySystemBackground)
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    
    // MARK: - Recent Searches / Suggestions View
    private var recentSearchesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Categories section - horizontally scrollable
                VStack(alignment: .leading, spacing: 10) {
                    Text("Categories")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                                categoryChip(category: category) {
                                    searchText = category.rawValue
                                }
                            }
                            
                            // Include custom categories in the same row
                            ForEach(categoryViewModel.customCategories) { customCategory in
                                customCategoryChip(category: customCategory) {
                                    searchText = customCategory.name
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Recent expenses section
                if !viewModel.expenses.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Expenses")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 8) {
                            ForEach(viewModel.expenses.prefix(5)) { expense in
                                recentExpenseRow(expense: expense)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer(minLength: 50)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - No Results View
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No results found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try searching for a different term")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
            
            Spacer()
        }
    }
    
    // MARK: - Search Results List
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Results count
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
                
                ForEach(searchResults) { expense in
                    searchResultRow(expense: expense)
                        .onTapGesture {
                            HapticManager.shared.impact(style: .light)
                            selectedExpense = expense
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 50)
        }
    }
    
    // MARK: - Helper Views
    
    private func categoryChip(category: Expense.Category, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.lightTap()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(Color.forCategory(category.color))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.forCategory(category.color).opacity(0.15))
            .cornerRadius(20)
        }
    }
    
    private func customCategoryChip(category: CustomCategory, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.lightTap()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                Text(category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(Color.forCategory(category.colorName))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.forCategory(category.colorName).opacity(0.15))
            .cornerRadius(20)
        }
    }
    
    private func recentExpenseRow(expense: Expense) -> some View {
        Button(action: {
            HapticManager.shared.lightTap()
            selectedExpense = expense
        }) {
            HStack(spacing: 12) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(categoryColor(for: expense).opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: categoryIcon(for: expense))
                        .font(.system(size: 16))
                        .foregroundColor(categoryColor(for: expense))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(expense.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(viewModel.formattedAmount(expense.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.secondarySystemBackground)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func searchResultRow(expense: Expense) -> some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor(for: expense).opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: categoryIcon(for: expense))
                    .font(.system(size: 18))
                    .foregroundColor(categoryColor(for: expense))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Highlighted title
                Text(expense.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(categoryName(for: expense))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(expense.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let notes = expense.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text(viewModel.formattedAmount(expense.amount))
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.secondarySystemBackground)
        .cornerRadius(14)
    }
    
    // MARK: - Search Logic
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            return
        }
        
        searchTask = Task { @MainActor in
            // Small debounce
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            
            guard !Task.isCancelled else { return }
            
            let expenses = viewModel.expenses
            let customCategories = categoryViewModel.customCategories
            let query = trimmedQuery.lowercased()
            
            // Perform search on background thread
            let results = await Task.detached(priority: .userInitiated) {
                let customNameById: [UUID: String] = Dictionary(uniqueKeysWithValues: customCategories.map { ($0.id, $0.name) })
                
                return expenses.filter { expense in
                    // Search in title
                    if expense.title.lowercased().contains(query) { return true }
                    
                    // Search in category
                    if expense.category.rawValue.lowercased().contains(query) { return true }
                    
                    // Search in custom category name
                    if expense.category == .custom, let customId = expense.customCategoryId,
                       let customName = customNameById[customId],
                       customName.lowercased().contains(query) {
                        return true
                    }
                    
                    // Search in notes
                    if let notes = expense.notes?.lowercased(), notes.contains(query) {
                        return true
                    }
                    
                    // Search in amount (e.g., "500" matches expenses with 500)
                    let amountString = String(format: "%.2f", expense.amount)
                    if amountString.contains(query) { return true }
                    
                    return false
                }
                .sorted { $0.date > $1.date } // Most recent first
            }.value
            
            guard !Task.isCancelled else { return }
            
            searchResults = results
        }
    }
    
    // MARK: - Helper Functions
    
    private func categoryColor(for expense: Expense) -> Color {
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            return Color.forCategory(custom.colorName)
        }
        return Color.forCategory(expense.category.color)
    }
    
    private func categoryIcon(for expense: Expense) -> String {
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            return custom.icon
        }
        return expense.category.icon
    }
    
    private func categoryName(for expense: Expense) -> String {
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            return custom.name
        }
        return expense.category.rawValue
    }
}

struct QuickSearchView_Previews: PreviewProvider {
    static var previews: some View {
        QuickSearchView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
    }
}
