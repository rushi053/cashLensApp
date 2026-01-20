import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @State private var showingAddExpense = false
    @State private var showingProfile = false
    @State private var showingAllExpenses = false
    @State private var animateCards = false
    @State private var selectedExpense: Expense?
    @State private var showingCustomizeSummary = false
    @State private var showingManageCategories = false
    @State private var showOnlySubscriptionsOnHome = false
    @State private var showingSearch = false
    
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isCompactPhone: Bool {
        UIDevice.current.userInterfaceIdiom != .pad && UIScreen.main.bounds.height < 760
    }
    
    var body: some View {
        ZStack {
            Color.systemBackground.edgesIgnoringSafeArea(.all)
            
            if isIPad {
                // iPad layout with improved spacing and organization
                iPadLayout
            } else {
                // Original iPhone layout
                iPhoneLayout
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                animateCards = true
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingAllExpenses) {
            AllExpensesView()
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
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
                }
            )
            .environmentObject(categoryViewModel)
        }
        .sheet(isPresented: $showingCustomizeSummary) {
            SummaryCustomizationView()
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
        }
        .sheet(isPresented: $showingManageCategories) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingSearch) {
            QuickSearchView()
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
        }
    }
    
    // MARK: - iPhone Layout
    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: isCompactPhone ? 18 : 24) {
                // Header
                headerView
                
                if viewModel.expenses.isEmpty {
                    // Empty state
                    emptyStateView
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                } else {
                    // Summary Cards
                    summaryCardsView
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                    
                    // Time Frame Selector
                    timeFrameSelector
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                    
                    // Categories
                    categoriesView
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                    
                    // Recent Expenses
                    recentExpensesView
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                }
            }
            .padding()
            .padding(.bottom, isCompactPhone ? 104 : 120) // Slightly tighter on smaller phones
        }
    }
    
    // MARK: - iPad Layout
    private var iPadLayout: some View {
        ScrollView {
            VStack(spacing: 48) { // Increased main spacing for iPad
                // Header
                headerView
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                
                if viewModel.expenses.isEmpty {
                    // Empty state
                    emptyStateView
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                } else {
                    // Complete reorganization for iPad with better structure
                    VStack(spacing: 48) { // More space between main sections
                        // Time Frame Section
                        VStack(spacing: 16) {
                            Text("Time Frame")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            // Time frame selector content without its title in a container
                            VStack {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                                            Button(action: {
                                                HapticManager.shared.selectionChanged()
                                                withAnimation(.spring()) {
                                                    viewModel.selectedTimeFrame = timeFrame
                                                }
                                            }) {
                                                Text(timeFrame.rawValue)
                                                    .font(.subheadline)
                                                    .fontWeight(viewModel.selectedTimeFrame == timeFrame ? .bold : .regular)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        Capsule()
                                                            .fill(viewModel.selectedTimeFrame == timeFrame ? Color.mauve : Color.tertiarySystemBackground)
                                                    )
                                                    .foregroundColor(viewModel.selectedTimeFrame == timeFrame ? .white : .primary)
                                            }
                                            .buttonStyle(ScaleButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, 20)
                            .padding(.horizontal, 20)
                            .background(Color.secondarySystemBackground)
                            .cornerRadius(16)
                        }
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                        
                        // Categories Section
                        VStack(spacing: 16) {
                            Text("Categories")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            // Category content without the header
                            VStack(spacing: 16) {
                                HStack {
                                    Spacer()
                                    
                                    Button(action: {
                                        HapticManager.shared.lightTap()
                                        showingManageCategories = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("See All")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.appPrimary)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        // Standard categories (excluding deleted ones)
                                        ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                                            CategoryItem(
                                                category: category,
                                                isSelected: viewModel.selectedCategory == category,
                                                action: {
                                                    HapticManager.shared.mediumTap()
                                                    // Fast animation for UI, data filtering is debounced
                                                    withAnimation(.easeOut(duration: 0.15)) {
                                                        if viewModel.selectedCategory == category {
                                                            viewModel.selectedCategory = nil
                                                        } else {
                                                            viewModel.selectedCategory = category
                                                            viewModel.selectedCustomCategoryId = nil
                                                        }
                                                    }
                                                }
                                            )
                                        }
                                        
                                        // Custom categories
                                        ForEach(categoryViewModel.customCategories) { category in
                                            CustomCategoryItem(
                                                category: category,
                                                isSelected: viewModel.selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id,
                                                action: {
                                                    HapticManager.shared.mediumTap()
                                                    // Fast animation for UI, data filtering is debounced
                                                    withAnimation(.easeOut(duration: 0.15)) {
                                                        if viewModel.selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id {
                                                            viewModel.selectedCategory = nil
                                                            viewModel.selectedCustomCategoryId = nil
                                                        } else {
                                                            viewModel.selectedCustomCategoryId = category.id
                                                            viewModel.selectedCategory = .custom
                                                        }
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding(.vertical, 20)
                            .padding(.horizontal, 20)
                            .background(Color.secondarySystemBackground)
                            .cornerRadius(16)
                        }
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                        
                        // Summary Section
                        VStack(spacing: 16) {
                            Text("Summary")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            // Summary cards in their own container with proper spacing
                            VStack(spacing: 16) {
                                summaryCardsContent
                                    .frame(minHeight: 180) // Ensure minimum height for visibility
                            }
                            .padding(.vertical, 24)
                            .padding(.horizontal, 20)
                            .background(Color.secondarySystemBackground)
                            .cornerRadius(16)
                        }
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                        
                        // Recent Expenses Section
                        VStack(spacing: 16) {
                            Text("Recent Activity")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            // Recent expenses in their own container
                            recentExpensesContent
                                .padding(.vertical, 24)
                                .padding(.horizontal, 20)
                                .background(Color.secondarySystemBackground)
                                .cornerRadius(16)
                        }
                        .opacity(animateCards ? 1 : 0)
                        .offset(y: animateCards ? 0 : 20)
                    }
                }
            }
            .padding(24) // More padding all around for iPad
            .padding(.bottom, 120)
            .frame(maxWidth: 1200) // Set a maximum width for very large screens
            .frame(maxWidth: .infinity) // Center content
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hello,")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text(viewModel.userName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .opacity(animateCards ? 1 : 0)
                    .offset(x: animateCards ? 0 : -20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateCards)
                
                Text(homeRangeLabel())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Search Button
            Button(action: {
                HapticManager.shared.lightTap()
                showingSearch = true
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color.mauve)
                    .shadow(color: Color.mauve.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .opacity(animateCards ? 1 : 0)
            .scaleEffect(animateCards ? 1 : 0.5)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateCards)
            .padding(.trailing, 8)
            
            // Theme Toggle Button
            Button(action: {
                HapticManager.shared.mediumTap()
                toggleAppearanceMode()
            }) {
                Image(systemName: viewModel.appearanceMode == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color.mauve)
                    .shadow(color: Color.mauve.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .opacity(animateCards ? 1 : 0)
            .scaleEffect(animateCards ? 1 : 0.5)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: animateCards)
            .padding(.trailing, 8)
            
            Button(action: {
                HapticManager.shared.lightTap()
                showingProfile = true
            }) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color.mauve)
                    .shadow(color: Color.mauve.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .opacity(animateCards ? 1 : 0)
            .scaleEffect(animateCards ? 1 : 0.5)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: animateCards)
        }
        .padding(.top, 8)
    }

    private func homeRangeLabel() -> String {
        let tf = viewModel.selectedTimeFrame
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        if tf == .all {
            return "All time"
        }
        
        let range = tf.dateRange(referenceDate: Date())
        let start = formatter.string(from: range.start)
        // end is exclusive; show inclusive label
        let endInclusive = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let end = formatter.string(from: endInclusive)
        
        if start == end { return start }
        return "\(start) – \(end)"
    }
    
    // Toggle between light and dark mode
    private func toggleAppearanceMode() {
        switch viewModel.appearanceMode {
        case .light:
            viewModel.appearanceMode = .dark
        case .dark, .system:
            viewModel.appearanceMode = .light
        }
    }
    
    // MARK: - Summary Cards View
    private var summaryCardsView: some View {
        VStack(spacing: 16) {
            HStack {
            Text("Summary")
                .font(.title3)
                .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    HapticManager.shared.lightTap()
                    showingCustomizeSummary = true
                }) {
                    HStack(spacing: 4) {
                        Text("Customize")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                    }
                    .foregroundColor(.appPrimary)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            // Adaptive grid for different screen sizes
            AdaptiveGrid {
                ForEach(Array(viewModel.getSummaryCardsData().enumerated()), id: \.offset) { index, cardData in
                SummaryCard(
                        title: cardData.title,
                        amount: cardData.amount,
                        icon: cardData.icon,
                        color: cardData.color,
                    action: {
                        HapticManager.shared.lightTap()
                            // Set category filter or clear for total
                            viewModel.selectedCategory = cardData.category
                            viewModel.selectedCustomCategoryId = cardData.customCategoryId
                    }
                )
                .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1 * Double(index + 1)), value: animateCards)
                }
            }
        }
    }
    
    // Adaptive grid that changes columns based on device size
    private struct AdaptiveGrid<Content: View>: View {
        @ViewBuilder let content: Content
        @Environment(\.horizontalSizeClass) private var sizeClass
        
        var body: some View {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // For iPad - show in 4 columns for landscape, 3 for portrait
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                    
                    // Use fixed height to ensure content is visible
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        isLandscape ? GridItem(.flexible()) : nil
                    ].compactMap { $0 }, spacing: 16) {
                        content
                    }
                    .frame(height: 160) // Fixed height for iPad ensures visibility
                }
                .frame(height: 160) // Need to set GeometryReader height as well
            } else {
                // For iPhone - standard 2 column layout
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    content
                }
            }
        }
    }
    
    // MARK: - Time Frame Selector
    private var timeFrameSelector: some View {
        VStack(spacing: 12) {
            Text("Time Frame")
                .font(.title3)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                        Button(action: {
                            HapticManager.shared.selectionChanged()
                            withAnimation(.spring()) {
                                viewModel.selectedTimeFrame = timeFrame
                            }
                        }) {
                            Text(timeFrame.rawValue)
                                .font(.subheadline)
                                .fontWeight(viewModel.selectedTimeFrame == timeFrame ? .bold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.selectedTimeFrame == timeFrame ? Color.mauve : Color.tertiarySystemBackground)
                                )
                                .foregroundColor(viewModel.selectedTimeFrame == timeFrame ? .white : .primary)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: animateCards)
    }
    
    // MARK: - Categories View
    private var categoriesView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Categories")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    HapticManager.shared.lightTap()
                    showingManageCategories = true
                }) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.appPrimary)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    // Standard categories (excluding deleted ones)
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        CategoryItem(
                            category: category,
                            isSelected: viewModel.selectedCategory == category,
                            action: {
                                HapticManager.shared.mediumTap()
                                // Fast animation ONLY for the selection state
                                // Data filtering happens in background via debounced pipeline
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if viewModel.selectedCategory == category {
                                        viewModel.selectedCategory = nil
                                    } else {
                                        viewModel.selectedCategory = category
                                        viewModel.selectedCustomCategoryId = nil
                                    }
                                }
                            }
                        )
                    }
                    
                    // Custom categories
                    ForEach(categoryViewModel.customCategories) { category in
                        CustomCategoryItem(
                            category: category,
                            isSelected: viewModel.selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id,
                            action: {
                                HapticManager.shared.mediumTap()
                                // Fast animation ONLY for the selection state
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if viewModel.selectedCategory == .custom && viewModel.selectedCustomCategoryId == category.id {
                                        viewModel.selectedCategory = nil
                                        viewModel.selectedCustomCategoryId = nil
                                    } else {
                                        viewModel.selectedCustomCategoryId = category.id
                                        viewModel.selectedCategory = .custom
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
        .animation(.easeOut(duration: 0.25), value: animateCards)
    }
    
    // MARK: - Recent Expenses View
    private var recentExpensesView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recent Expenses")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    HapticManager.shared.lightTap()
                    showingAllExpenses = true
                }) {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.appPrimary)
                }
                .buttonStyle(ScaleButtonStyle())
            }

            // Quick filter (composes with existing time frame + category filters)
            HStack(spacing: 10) {
                Button {
                    HapticManager.shared.selectionChanged()
                    withAnimation(.spring()) {
                        showOnlySubscriptionsOnHome = false
                    }
                } label: {
                    Text("All")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(showOnlySubscriptionsOnHome ? .primary : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if showOnlySubscriptionsOnHome {
                                    Color.secondarySystemBackground
                                } else {
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            }
                        )
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button {
                    HapticManager.shared.selectionChanged()
                    withAnimation(.spring()) {
                        showOnlySubscriptionsOnHome = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Subscriptions")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(showOnlySubscriptionsOnHome ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if showOnlySubscriptionsOnHome {
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                Color.secondarySystemBackground
                            }
                        }
                    )
                    .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            
            let list = showOnlySubscriptionsOnHome ? viewModel.filteredExpenses.filter { $0.isFromSubscription } : viewModel.filteredExpenses
            
            if list.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No expenses found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(showOnlySubscriptionsOnHome ? "No subscription expenses in this period" : "Add your first expense by tapping the + button")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                // Use LazyVStack with optimized ExpenseCards
                LazyVStack(spacing: 16) {
                    ForEach(Array(list.prefix(5).enumerated()), id: \.element.id) { index, expense in
                        // Use the optimized initializer to prevent unnecessary re-renders
                        ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
                            .equatable() // Tell SwiftUI to use our Equatable implementation
                            .onTapGesture {
                                HapticManager.shared.impact(style: .light)
                                selectedExpense = expense
                            }
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 10)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: animateCards)
            }
        }
        // Removed heavy spring animation - data changes should not trigger view animations
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)
            
            Image(systemName: "plus.circle")
                .font(.system(size: 80))
                .foregroundColor(.appPrimary)
                .padding()
                .background(
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 150, height: 150)
                )
            
            Text("No Expenses Yet")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Start tracking your expenses by tapping the + button below")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                HapticManager.shared.heavyTap()
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
            .buttonStyle(ScaleButtonStyle())
            .padding(.top, 16)
            
            Spacer()
        }
        .padding()
        .frame(minHeight: 500)
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
                .environmentObject(categoryViewModel)
        }
    }
    
    // MARK: - Content Views without Headers for iPad
    private var summaryCardsContent: some View {
        // Adaptive grid for different screen sizes
        AdaptiveGrid {
            ForEach(Array(viewModel.getSummaryCardsData(customCategories: categoryViewModel.customCategories).enumerated()), id: \.offset) { index, cardData in
            SummaryCard(
                    title: cardData.title,
                    amount: cardData.amount,
                    icon: cardData.icon,
                    color: cardData.color,
                action: {
                    HapticManager.shared.lightTap()
                        // Set category filter or clear for total
                        viewModel.selectedCategory = cardData.category
                        viewModel.selectedCustomCategoryId = cardData.customCategoryId
                }
            )
            .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1 * Double(index + 1)), value: animateCards)
            }
        }
    }
    
    private var recentExpensesContent: some View {
        VStack(spacing: 16) {
            if viewModel.filteredExpenses.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No expenses found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Add your first expense by tapping the + button")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(viewModel.filteredExpenses.prefix(5).enumerated()), id: \.element.id) { index, expense in
                        ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
                            .equatable()
                            .onTapGesture {
                                HapticManager.shared.impact(style: .light)
                                selectedExpense = expense
                            }
                            .opacity(animateCards ? 1 : 0)
                            .offset(y: animateCards ? 0 : 10)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: animateCards)
            }
        }
    }
    
    // MARK: - Automation Banner
    // (Automation banner removed in core-only build)
    
    // MARK: - Haptic Feedback (Deprecated - Using HapticManager instead)
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        HapticManager.shared.impact(style: style)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
    }
}
