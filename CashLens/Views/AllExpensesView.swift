import SwiftUI

struct AllExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @StateObject private var categoryViewModel = CategoryViewModel()
    @State private var searchText = ""
    @State private var sortOption: SortOption = .dateDesc
    @State private var showingSortOptions = false
    @State private var animateContent = false
    @State private var scrollToTop = false  // Track when to scroll to top
    @State private var selectedExpense: Expense?
    @State private var showingEditSheet = false
    
    enum SortOption: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case amountDesc = "Highest Amount"
        case amountAsc = "Lowest Amount"
        case category = "Category"
        
        var icon: String {
            switch self {
            case .dateDesc: return "calendar.badge.clock"
            case .dateAsc: return "calendar"
            case .amountDesc: return "arrow.down.circle"
            case .amountAsc: return "arrow.up.circle"
            case .category: return "folder"
            }
        }
    }
    
    // Filtered and sorted expenses
    private var filteredExpenses: [Expense] {
        let filtered = searchText.isEmpty ? 
            viewModel.expenses : 
            viewModel.expenses.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
                (viewModel.categoryDisplayName(for: $0).localizedCaseInsensitiveContains(searchText)) ||
                (($0.notes ?? "").localizedCaseInsensitiveContains(searchText))
            }
        
        return sortExpenses(filtered)
    }
    
    // Sort expenses based on selected sort option
    private func sortExpenses(_ expenses: [Expense]) -> [Expense] {
        switch sortOption {
        case .dateDesc:
            return expenses.sorted { $0.date > $1.date }
        case .dateAsc:
            return expenses.sorted { $0.date < $1.date }
        case .amountDesc:
            return expenses.sorted { $0.amount > $1.amount }
        case .amountAsc:
            return expenses.sorted { $0.amount < $1.amount }
        case .category:
            return expenses.sorted { viewModel.categoryDisplayName(for: $0) < viewModel.categoryDisplayName(for: $1) }
        }
    }
    
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.systemBackground.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Custom title bar for iPad to replace navigation bar
                    if isIPad {
                        HStack {
                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back")
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.appPrimary)
                            }
                            
                            Spacer()
                            
                            Text("All Expenses")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            // Balance the layout with an invisible element
                            Color.clear
                                .frame(width: 60, height: 10)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    
                    // Header with search and sort options
                    VStack(spacing: 16) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                            
                            TextField("Search expenses", text: $searchText)
                                .disableAutocorrection(true)
                            
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                    HapticManager.shared.lightTap()
                                    // Set scroll to top flag
                                    scrollToTop = true
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.secondarySystemBackground)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                        .padding(.horizontal)
                        
                        // Sort option bar
                        HStack {
                            Text("Sort by:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                HapticManager.shared.lightTap()
                                showingSortOptions = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: sortOption.icon)
                                        .font(.system(size: 14))
                                    
                                    Text(sortOption.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .cornerRadius(16)
                                )
                                .shadow(color: Color.appPrimary.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Spacer()
                            
                            Text("\(filteredExpenses.count) expenses")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color.systemBackground)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : -10)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 1)
                        .padding(.horizontal)
                    
                    // Expense list
                    if filteredExpenses.isEmpty {
                        emptyStateView
                            .opacity(animateContent ? 1 : 0)
                    } else {
                        expenseList
                            .opacity(animateContent ? 1 : 0)
                    }
                }
            }
            .navigationTitle(isIPad ? "" : "All Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(isIPad) // Hide navigation bar on iPad
            .toolbar {
                if !isIPad {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.appPrimary)
                        }
                    }
                }
            }
            .actionSheet(isPresented: $showingSortOptions) {
                ActionSheet(
                    title: Text("Sort Expenses"),
                    buttons: SortOption.allCases.map { option in
                        .default(Text("\(option.rawValue)")) {
                            HapticManager.shared.selectionChanged()
                            sortOption = option
                            scrollToTop = true
                        }
                    } + [.cancel()]
                )
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    animateContent = true
                }
                // Reset scroll to top flag
                scrollToTop = false
            }
        }
        .if(isIPad) { view in
            view.navigationViewStyle(StackNavigationViewStyle())
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            // Reset selected expense when sheet is dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                selectedExpense = nil
            }
        }) {
            if let expense = selectedExpense {
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
                        // Update expense
                        var updatedExpense = expense
                        updatedExpense.title = title
                        updatedExpense.amount = amount
                        updatedExpense.date = date
                        updatedExpense.category = category
                        updatedExpense.customCategoryId = customCategoryId
                        updatedExpense.notes = notes
                        
                        viewModel.updateExpense(updatedExpense)
                    }
                )
                .environmentObject(categoryViewModel)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if searchText.isEmpty {
                // No expenses
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(Color.appPrimary)
                }
                
                VStack(spacing: 8) {
                    Text("No expenses found")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Add some expenses to see them here")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                // No search results
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(Color.appPrimary)
                }
                
                VStack(spacing: 8) {
                    Text("No matching expenses")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Try adjusting your search term")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Button(action: {
                    searchText = ""
                    HapticManager.shared.lightTap()
                    // Set scroll to top flag
                    scrollToTop = true
                }) {
                    Text("Clear Search")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .cornerRadius(16)
                        )
                        .shadow(color: Color.appPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 16)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var expenseList: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                // Top indicator view with id for scrolling to top
                HStack {
                    Color.clear.frame(height: 1)
                }
                .id("top")
                
                LazyVStack(spacing: 16) {
                    ForEach(Array(groupExpensesByDate().enumerated()), id: \.element.0) { index, dateGroup in
                        dateGroupView(index: index, dateGroup: dateGroup)
                    }
                    
                    // Bottom padding
                    Color.clear.frame(height: 40)
                }
            }
            .onChange(of: sortOption) { _ in
                // Scroll to top when sort option changes
                withAnimation {
                    scrollView.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: searchText) { _ in
                // Scroll to top when search text changes
                withAnimation {
                    scrollView.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: viewModel.selectedCategory) { _ in
                // Scroll to top when category filter changes
                withAnimation {
                    scrollView.scrollTo("top", anchor: .top)
                }
            }
        }
    }
    
    private func dateGroupView(index: Int, dateGroup: (Date, [Expense])) -> some View {
        let (date, expenses) = dateGroup
        
        return VStack(spacing: 0) {
            // Date header with gradient background
            dateHeaderView(date: date, expenses: expenses)
            
            // Expenses for this date
            expensesListView(date: date, expenses: expenses, groupIndex: index)
        }
        .padding(.horizontal)
        .padding(.top, index == 0 ? 8 : 16)
    }
    
    private func dateHeaderView(date: Date, expenses: [Expense]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(date))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                let totalForDay = expenses.reduce(0) { $0 + $1.amount }
                Text("Total: \(viewModel.formattedAmount(totalForDay))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Date badge
            dateBadgeView(date: date)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(16, corners: [.topLeft, .topRight])
    }
    
    private func dateBadgeView(date: Date) -> some View {
        let dayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "d"
            return formatter
        }()
        
        let monthFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter
        }()
        
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.appPrimary.opacity(0.8), Color.appSecondary.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 40, height: 40)
            
            VStack(spacing: 0) {
                Text(dayFormatter.string(from: date))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text(monthFormatter.string(from: date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
    
    private func expensesListView(date: Date, expenses: [Expense], groupIndex: Int) -> some View {
        VStack(spacing: 1) {
            ForEach(Array(expenses.enumerated()), id: \.element.id) { expenseIndex, expense in
                expenseRowView(expense: expense, groupIndex: groupIndex, expenseIndex: expenseIndex)
                
                if expenseIndex < expenses.count - 1 {
                    Divider()
                        .padding(.horizontal)
                }
            }
        }
        .background(Color.systemBackground)
        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func expenseRowView(expense: Expense, groupIndex: Int, expenseIndex: Int) -> some View {
        ExpenseCard(expense: expense)
            .environmentObject(viewModel)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.systemBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                // Set the selected expense first and ensure it's fully saved before showing sheet
                selectedExpense = expense
                
                // Use a slightly longer delay to ensure data is fully prepared
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingEditSheet = true
                }
            }
            .contextMenu {
                Button {
                    // Edit expense
                    selectedExpense = expense
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showingEditSheet = true
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    deleteExpense(expense)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteExpense(expense)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 20)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.8)
                .delay(0.1 + Double(groupIndex) * 0.05 + Double(expenseIndex) * 0.03),
                value: animateContent
            )
    }
    
    // Group expenses by date for sectioned display
    private func groupExpensesByDate() -> [(Date, [Expense])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredExpenses) { expense in
            calendar.startOfDay(for: expense.date)
        }
        
        // Sort by date according to current sort option
        let sortedGroups = grouped.sorted { group1, group2 in
            if sortOption == .dateAsc {
                return group1.key < group2.key
            } else {
                return group1.key > group2.key
            }
        }
        
        return sortedGroups
    }
    
    // Delete an expense - using the safer method to prevent index-related crashes
    private func deleteExpense(_ expense: Expense) {
        // Delete directly by ID instead of finding an index
        viewModel.deleteExpenseById(expense.id)
        HapticManager.shared.success()
    }
    
    // Format date for section headers
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

struct AllExpensesView_Previews: PreviewProvider {
    static var previews: some View {
        AllExpensesView()
            .environmentObject(ExpenseViewModel())
    }
} 