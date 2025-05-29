import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var selectedTimeFrame: ExpenseViewModel.TimeFrame = .month
    @State private var showingAddExpense = false
    @State private var selectedCategory: Expense.Category? = nil // Local category filter
    
    // Computed property for filtered expenses based on local state
    private var filteredExpenses: [Expense] {
        var filtered = viewModel.expenses
        
        // Filter by time frame
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeFrame {
        case .day:
            filtered = filtered.filter { calendar.isDateInToday($0.date) }
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            filtered = filtered.filter { $0.date >= startOfWeek }
        case .month:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            filtered = filtered.filter { $0.date >= startOfMonth }
        case .year:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now))!
            filtered = filtered.filter { $0.date >= startOfYear }
        case .all:
            // No additional filtering
            break
        }
        
        // Filter by local category selection if needed
        if let category = selectedCategory {
            if category == .custom {
                // For custom categories, filter by both category type and specific custom category ID
                if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId {
                    filtered = filtered.filter { 
                        $0.category == .custom && $0.customCategoryId == selectedCustomCategoryId 
                    }
                } else {
                    // If custom is selected but no specific ID, show all custom categories
                    filtered = filtered.filter { $0.category == .custom }
                }
            } else {
                // For default categories, filter normally
                filtered = filtered.filter { $0.category == category }
            }
        }
        
        // Sort by date (newest first)
        return filtered.sorted { $0.date > $1.date }
    }
    
    // Calculate total expenses based on filtered expenses
    private func totalExpenses() -> Double {
        return filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    // Calculate total expenses for a specific category
    private func totalExpenses(for category: Expense.Category) -> Double {
        return filteredExpenses.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
    }
    
    // Calculate total expenses for a specific custom category
    private func totalExpenses(for customCategory: CustomCategory) -> Double {
        return filteredExpenses.filter { 
            $0.category == .custom && $0.customCategoryId == customCategory.id 
        }.reduce(0) { $0 + $1.amount }
    }
    
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    if isIPad {
                        // Custom title for iPad
                        Text("Statistics")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }
                    
                    if isIPad {
                        // iPad layout with separate sections to prevent overlapping
                        iPadLayout
                    } else {
                        // Original iPhone layout
                        iPhoneLayout
                    }
                }
            }
            .background(Color.systemBackground)
            .navigationBarTitle("")
            .navigationBarHidden(isIPad) // Hide the entire navigation bar on iPad
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(viewModel: viewModel)
            }
        }
        .if(isIPad) { view in
            view.navigationViewStyle(StackNavigationViewStyle())
        }
    }
    
    // MARK: - iPhone Layout
    private var iPhoneLayout: some View {
        VStack(spacing: 24) {
            // Time Frame Selector
            timeFrameSelector
            
            // Category Selector
            categorySelector
            
            if viewModel.expenses.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Use adaptive layout for larger screens
                AdaptiveView {
                    // Total Expenses Card
                    totalExpensesCard
                    
                    // Category Breakdown
                    categoryBreakdown
                }
                
                // Expense Trend - always full width
                expenseTrend
            }
        }
        .padding()
        .padding(.bottom, 120)
    }
    
    // MARK: - iPad Layout
    private var iPadLayout: some View {
        VStack(spacing: 48) { // Increased spacing between main sections
            // Filters Section with title
            VStack(spacing: 16) {
                Text("Statistics Filters")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                
                // Filter controls section in a card with more padding
                VStack(spacing: 32) { // More spacing between time frame and categories
                    // Time Frame Selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Time Frame")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        // Just the scrollable time frame buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                                    Button(action: {
                                        HapticManager.shared.selectionChanged()
                                        selectedTimeFrame = timeFrame
                                    }) {
                                        Text(timeFrame.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(selectedTimeFrame == timeFrame ? .bold : .regular)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(selectedTimeFrame == timeFrame ? Color.mauve : Color.secondarySystemBackground)
                                            )
                                            .foregroundColor(selectedTimeFrame == timeFrame ? .white : .primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Category Selector
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Filter by Category")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Clear filter button
                            if selectedCategory != nil {
                                Button(action: {
                                    HapticManager.shared.selectionChanged()
                                    selectedCategory = nil
                                    viewModel.selectedCustomCategoryId = nil
                                }) {
                                    Text("Clear")
                                        .font(.subheadline)
                                        .foregroundColor(.appPrimary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Standard categories - reuse the content
                        categoryFilterContent
                    }
                }
                .padding(24) // More padding inside the card
                .background(Color.secondarySystemBackground)
                .cornerRadius(16)
            }
            
            if viewModel.expenses.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Summary Section
                VStack(spacing: 16) {
                    Text("Expense Summary")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    
                    // Data section with cards in its own container
                    AdaptiveView {
                        // Total Expenses Card
                        totalExpensesCard
                        
                        // Category Breakdown
                        categoryBreakdown
                    }
                    .padding(24)
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                }
                
                // Trend Section
                VStack(spacing: 16) {
                    Text("Expense Trends")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    
                    // Expense Trend in its own container
                    expenseTrend
                        .padding(24)
                        .background(Color.secondarySystemBackground)
                        .cornerRadius(16)
                }
            }
        }
        .padding(24)
        .padding(.bottom, 120)
        .frame(maxWidth: 1200) // Set a maximum width for very large screens
        .frame(maxWidth: .infinity) // Center content
    }
    
    // Adaptive View that shows content in columns on iPad and stacked on iPhone
    private struct AdaptiveView<Content: View>: View {
        @ViewBuilder let content: Content
        @Environment(\.horizontalSizeClass) private var sizeClass
        
        var body: some View {
            if sizeClass == .regular { // iPad
                HStack(alignment: .top, spacing: 20) {
                    content
                }
            } else { // iPhone
                VStack(spacing: 24) {
                    content
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)
            
            Image(systemName: "chart.pie")
                .font(.system(size: 80))
                .foregroundColor(.appPrimary)
                .padding()
                .background(
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 150, height: 150)
                )
            
            Text("No Statistics Available")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Add some expenses to see your spending patterns and statistics")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                HapticManager.shared.mediumTap()
                showingAddExpense = true
            }) {
                Text("Add Your First Expense")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 16)
            
            Spacer()
        }
        .padding()
        .frame(minHeight: 500)
    }
    
    // MARK: - Time Frame Selector
    private var timeFrameSelector: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Time Frame")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                        Button(action: {
                            HapticManager.shared.selectionChanged()
                            selectedTimeFrame = timeFrame
                        }) {
                            Text(timeFrame.rawValue)
                                .font(.subheadline)
                                .fontWeight(selectedTimeFrame == timeFrame ? .bold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedTimeFrame == timeFrame ? Color.mauve : Color.secondarySystemBackground)
                                )
                                .foregroundColor(selectedTimeFrame == timeFrame ? .white : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Category Selector
    private var categorySelector: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Filter by Category")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Clear filter button
                if selectedCategory != nil {
                    Button(action: {
                        HapticManager.shared.selectionChanged()
                        selectedCategory = nil
                        viewModel.selectedCustomCategoryId = nil
                    }) {
                        Text("Clear")
                            .font(.subheadline)
                            .foregroundColor(.appPrimary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Standard categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        Button(action: {
                            HapticManager.shared.selectionChanged()
                            if selectedCategory == category {
                                selectedCategory = nil
                                viewModel.selectedCustomCategoryId = nil
                            } else {
                                selectedCategory = category
                                viewModel.selectedCustomCategoryId = nil
                            }
                        }) {
                            HStack {
                                Image(systemName: category.icon)
                                    .font(.system(size: 14))
                                
                                Text(category.rawValue)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.forCategory(category.color) : Color.secondarySystemBackground)
                            )
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Custom categories (if any)
            let customCategories = viewModel.getCustomCategories()
            if !customCategories.isEmpty {
                Text("Custom Categories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(customCategories) { category in
                            let isSelected = selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id
                            
                            Button(action: {
                                HapticManager.shared.selectionChanged()
                                if isSelected {
                                    selectedCategory = nil
                                    viewModel.selectedCustomCategoryId = nil
                                } else {
                                    selectedCategory = .custom
                                    viewModel.selectedCustomCategoryId = category.id
                                }
                            }) {
                                HStack {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14))
                                    
                                    Text(category.name)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.forCategory(category.colorName) : Color.secondarySystemBackground)
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Total Expenses Card
    private var totalExpensesCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text(categoryDisplayName())
                    .font(.headline)
                
                Spacer()
                
                Text(selectedTimeFrame.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(viewModel.formattedAmount(totalExpenses()))
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.primary)
            
            HStack {
                Text("vs. Previous \(selectedTimeFrame.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Placeholder for comparison with previous period
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    Text("12.5%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
    }
    
    // Helper function to get the correct category display name for the total expenses card
    private func categoryDisplayName() -> String {
        if selectedCategory == nil {
            return "Total Expenses"
        } else if selectedCategory == .custom {
            // Handle custom category selection
            let customCategories = viewModel.getCustomCategories()
            if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId,
               let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                return "\(customCategory.name) Expenses"
            }
            return "Custom Expenses"
        } else {
            return "\(selectedCategory!.rawValue) Expenses"
        }
    }
    
    // MARK: - Category Breakdown
    private var categoryBreakdown: some View {
        VStack(spacing: 16) {
            Text("Category Breakdown")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if selectedCategory == nil {
                // Show all categories when no filter is applied
                // Default categories (excluding deleted ones)
                ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                    if totalExpenses(for: category) > 0 {
                        categoryRow(for: category)
                    }
                }
                
                // Individual custom categories
                let customCategories = viewModel.getCustomCategories()
                ForEach(customCategories) { customCategory in
                    if totalExpenses(for: customCategory) > 0 {
                        customCategoryRow(for: customCategory)
                    }
                }
            } else {
                // Show only the selected category
                if selectedCategory == .custom {
                    // If custom category is selected, show the specific custom category
                    let customCategories = viewModel.getCustomCategories()
                    if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId,
                       let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                        customCategoryRow(for: customCategory)
                    }
                } else {
                    // Show the selected default category
                    categoryRow(for: selectedCategory!)
                }
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
    }
    
    // Helper function to create a category row
    private func categoryRow(for category: Expense.Category) -> some View {
        VStack(spacing: 8) {
            HStack {
                // Category Icon
                ZStack {
                    Circle()
                        .fill(Color.forCategory(category.color).opacity(0.3))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color.forCategory(category.color))
                }
                
                // Category Name
                Text(category.rawValue)
                    .font(.subheadline)
                
                Spacer()
                
                // Amount
                Text(viewModel.formattedAmount(totalExpenses(for: category)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                // Percentage
                if selectedCategory == nil && totalExpenses() > 0 {
                    Text("\(String(format: "%.1f", (totalExpenses(for: category) / totalExpenses()) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .padding(.vertical, 8)
            
            // Progress Bar
            if selectedCategory == nil && totalExpenses() > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                            .cornerRadius(4)
                        
                        Rectangle()
                            .fill(Color.forCategory(category.color))
                            .frame(width: geometry.size.width * CGFloat(totalExpenses(for: category) / totalExpenses()), height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
            }
        }
    }
    
    // Helper function to create a custom category row
    private func customCategoryRow(for customCategory: CustomCategory) -> some View {
        VStack(spacing: 8) {
            HStack {
                // Category Icon
                ZStack {
                    Circle()
                        .fill(Color.forCategory(customCategory.colorName).opacity(0.3))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: customCategory.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color.forCategory(customCategory.colorName))
                }
                
                // Category Name
                Text(customCategory.name)
                    .font(.subheadline)
                
                Spacer()
                
                // Amount
                Text(viewModel.formattedAmount(totalExpenses(for: customCategory)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                // Percentage
                if selectedCategory == nil && totalExpenses() > 0 {
                    Text("\(String(format: "%.1f", (totalExpenses(for: customCategory) / totalExpenses()) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .padding(.vertical, 8)
            
            // Progress Bar
            if selectedCategory == nil && totalExpenses() > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                            .cornerRadius(4)
                        
                        Rectangle()
                            .fill(Color.forCategory(customCategory.colorName))
                            .frame(width: geometry.size.width * CGFloat(totalExpenses(for: customCategory) / totalExpenses()), height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
            }
        }
    }
    
    // MARK: - Expense Trend
    private var expenseTrend: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Expense Trend")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(selectedTimeFrame.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(12)
            }
            
            VStack(spacing: 8) {
                // Description text to provide more context
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.appPrimary)
                    
                    Text(getTrendDescription())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Enhanced chart with proper styling
                ExpenseTrendChart(
                    expenses: filteredExpenses,
                    timeFrame: selectedTimeFrame,
                    categoryColor: selectedCategory != nil ? 
                        Color.forCategory(selectedCategory!.color) : 
                        Color.appPrimary
                )
                .environmentObject(viewModel)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
        }
    }
    
    // Helper method to provide contextual description for the trend chart
    private func getTrendDescription() -> String {
        if filteredExpenses.isEmpty {
            return "No expenses recorded for this period."
        }
        
        if let category = selectedCategory {
            if category == .custom {
                // Handle custom category selection
                let customCategories = viewModel.getCustomCategories()
                if let selectedCustomCategoryId = viewModel.selectedCustomCategoryId,
                   let customCategory = customCategories.first(where: { $0.id == selectedCustomCategoryId }) {
                    return "Showing spending trend for \(customCategory.name) expenses."
                }
                return "Showing spending trend for Custom expenses."
            } else {
                return "Showing spending trend for \(category.rawValue) expenses."
            }
        } else {
            return "Showing overall spending trend for \(selectedTimeFrame.rawValue.lowercased())."
        }
    }
    
    // Just the category filter buttons without the outer container for reuse
    private var categoryFilterContent: some View {
        VStack(spacing: 16) {
            // Standard categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        Button(action: {
                            HapticManager.shared.selectionChanged()
                            if selectedCategory == category {
                                selectedCategory = nil
                                viewModel.selectedCustomCategoryId = nil
                            } else {
                                selectedCategory = category
                                viewModel.selectedCustomCategoryId = nil
                            }
                        }) {
                            HStack {
                                Image(systemName: category.icon)
                                    .font(.system(size: 14))
                                
                                Text(category.rawValue)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.forCategory(category.color) : Color.tertiarySystemBackground)
                            )
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Custom categories (if any)
            let customCategories = viewModel.getCustomCategories()
            if !customCategories.isEmpty {
                Text("Custom Categories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(customCategories) { category in
                            let isSelected = selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id
                            
                            Button(action: {
                                HapticManager.shared.selectionChanged()
                                if isSelected {
                                    selectedCategory = nil
                                    viewModel.selectedCustomCategoryId = nil
                                } else {
                                    selectedCategory = .custom
                                    viewModel.selectedCustomCategoryId = category.id
                                }
                            }) {
                                HStack {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14))
                                    
                                    Text(category.name)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.forCategory(category.colorName) : Color.tertiarySystemBackground)
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView()
            .environmentObject(ExpenseViewModel())
    }
} 
