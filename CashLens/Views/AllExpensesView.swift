import SwiftUI

struct AllExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    let initialFilter: AllExpensesInitialFilter?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .dateDesc
    @State private var showingSortOptions = false
    @State private var animateContent = false
    @State private var scrollToTop = false  // Track when to scroll to top
    @State private var selectedExpense: Expense?
    @State private var didApplyInitialFilter = false
    
    // Performance: cache computed results + paginate rendering for large datasets
    @State private var computedExpenses: [Expense] = []
    @State private var computedDateGroups: [(Date, [Expense])] = []
    @State private var totalMatchCount: Int = 0
    @State private var displayLimit: Int = 250
    @State private var isRecomputing: Bool = false
    @State private var searchDebounceTask: Task<Void, Never>?
    
    // Date range filter
    @State private var useDateRangeFilter = false
    @State private var rangeStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var rangeEndDate = Date()
    @State private var showingDateRangePicker = false
    
    // Quick filters
    @State private var filterCategory: Expense.Category? = nil
    @State private var filterCustomCategoryId: UUID? = nil
    @State private var showOnlySubscriptions = false
    
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
    
    private var visibleExpenses: [Expense] {
        Array(computedExpenses.prefix(max(0, min(displayLimit, computedExpenses.count))))
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
    
    private var shouldGroupByDate: Bool {
        sortOption == .dateAsc || sortOption == .dateDesc
    }
    
    private var visibleDateGroups: [(Date, [Expense])] {
        var out: [(Date, [Expense])] = []
        out.reserveCapacity(min(computedDateGroups.count, 60))
        var running = 0
        for g in computedDateGroups {
            if running >= displayLimit { break }
            out.append(g)
            running += g.1.count
        }
        return out
    }
    
    private func recomputeResults(resetPagination: Bool) {
        searchDebounceTask?.cancel()
        isRecomputing = true
        
        let expensesSnapshot = viewModel.expenses
        let customCategoriesSnapshot = categoryViewModel.customCategories
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = sortOption
        let useRange = useDateRangeFilter
        let start = rangeStartDate
        let end = rangeEndDate
        let filterCat = filterCategory
        let filterCustomId = filterCustomCategoryId
        let subsOnly = showOnlySubscriptions
        
        Task.detached(priority: .userInitiated) {
            let customNameById: [UUID: String] = Dictionary(uniqueKeysWithValues: customCategoriesSnapshot.map { ($0.id, $0.name) })
            
            var base: [Expense] = expensesSnapshot
            if useRange {
                base = ExpenseFilter.apply(
                    expenses: base,
                    category: nil,
                    customCategoryId: nil,
                    timeFrame: .all,
                    dateRangeStart: start,
                    dateRangeEnd: end
                )
            }
            
            if subsOnly {
                base = base.filter { $0.isFromSubscription }
            }
            
            if let cat = filterCat {
                if cat == .custom {
                    if let id = filterCustomId {
                        base = base.filter { $0.category == .custom && $0.customCategoryId == id }
                    } else {
                        base = base.filter { $0.category == .custom }
                    }
                } else {
                    base = base.filter { $0.category == cat }
                }
            }
            
            if !search.isEmpty {
                let q = search.lowercased()
                base = base.filter { e in
                    if e.title.lowercased().contains(q) { return true }
                    if e.category.rawValue.lowercased().contains(q) { return true }
                    if let notes = e.notes?.lowercased(), notes.contains(q) { return true }
                    if e.category == .custom, let id = e.customCategoryId {
                        return (customNameById[id] ?? "Custom").lowercased().contains(q)
                    }
                    return false
                }
            }
            
            let sorted: [Expense]
            switch sort {
            case .dateDesc:
                sorted = base.sorted { $0.date > $1.date }
            case .dateAsc:
                sorted = base.sorted { $0.date < $1.date }
            case .amountDesc:
                sorted = base.sorted { $0.amount > $1.amount }
            case .amountAsc:
                sorted = base.sorted { $0.amount < $1.amount }
            case .category:
                sorted = base.sorted {
                    let a = ($0.category == .custom && $0.customCategoryId != nil) ? (customNameById[$0.customCategoryId!] ?? "Custom") : $0.category.rawValue
                    let b = ($1.category == .custom && $1.customCategoryId != nil) ? (customNameById[$1.customCategoryId!] ?? "Custom") : $1.category.rawValue
                    if a == b { return $0.date > $1.date }
                    return a < b
                }
            }
            
            let calendar = Calendar.current
            var groups: [(Date, [Expense])] = []
            if sort == .dateAsc || sort == .dateDesc {
                var currentDay: Date? = nil
                for e in sorted {
                    let day = calendar.startOfDay(for: e.date)
                    if currentDay != day {
                        groups.append((day, [e]))
                        currentDay = day
                    } else {
                        groups[groups.count - 1].1.append(e)
                    }
                }
            }
            
            await MainActor.run {
                totalMatchCount = sorted.count
                computedExpenses = sorted
                computedDateGroups = groups
                if resetPagination {
                    displayLimit = 250
                } else {
                    displayLimit = min(max(250, displayLimit), max(250, sorted.count))
                }
                isRecomputing = false
            }
        }
    }
    
    private func recomputeSearchDebounced() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            recomputeResults(resetPagination: true)
        }
    }
    
    private func loadMoreIfNeeded() {
        guard displayLimit < totalMatchCount else { return }
        displayLimit = min(totalMatchCount, displayLimit + 250)
    }
    
    private var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private var quickFiltersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(
                    title: "All",
                    systemIcon: "line.3.horizontal.decrease.circle",
                    isSelected: filterCategory == nil && !showOnlySubscriptions
                ) {
                    HapticManager.shared.selectionChanged()
                    withAnimation(.spring()) {
                        filterCategory = nil
                        filterCustomCategoryId = nil
                        showOnlySubscriptions = false
                        scrollToTop = true
                    }
                }
                
                filterChip(
                    title: "Subscriptions",
                    systemIcon: "arrow.triangle.2.circlepath",
                    isSelected: showOnlySubscriptions
                ) {
                    HapticManager.shared.selectionChanged()
                    withAnimation(.spring()) {
                        showOnlySubscriptions.toggle()
                        scrollToTop = true
                    }
                }
                
                ForEach(viewModel.getAvailableDefaultCategories().filter { $0 != .custom }, id: \.self) { category in
                    filterChip(
                        title: category.rawValue,
                        systemIcon: category.icon,
                        isSelected: filterCategory == category
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(.spring()) {
                            if filterCategory == category {
                                filterCategory = nil
                            } else {
                                filterCategory = category
                            }
                            filterCustomCategoryId = nil
                            scrollToTop = true
                        }
                    }
                }
                
                ForEach(categoryViewModel.customCategories) { custom in
                    filterChip(
                        title: custom.name,
                        systemIcon: custom.icon,
                        isSelected: filterCategory == .custom && filterCustomCategoryId == custom.id
                    ) {
                        HapticManager.shared.selectionChanged()
                        withAnimation(.spring()) {
                            if filterCategory == .custom && filterCustomCategoryId == custom.id {
                                filterCategory = nil
                                filterCustomCategoryId = nil
                            } else {
                                filterCategory = .custom
                                filterCustomCategoryId = custom.id
                            }
                            scrollToTop = true
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }
    
    private func filterChip(title: String, systemIcon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.secondarySystemBackground
                    }
                }
                .cornerRadius(14)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
                            
                            // Date range filter button
                            Button(action: {
                                HapticManager.shared.lightTap()
                                showingDateRangePicker = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: useDateRangeFilter ? "calendar.badge.checkmark" : "calendar")
                                        .font(.system(size: 14))
                                    Text("Date")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.9)
                                }
                                .foregroundColor(useDateRangeFilter ? .white : .appPrimary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    Group {
                                        if useDateRangeFilter {
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        } else {
                                            Color.tertiarySystemBackground
                                        }
                                    }
                                    .cornerRadius(16)
                                )
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Spacer()
                            
                            Text("\(totalMatchCount) expenses")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        // Quick filters
                        quickFiltersRow
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
                    if totalMatchCount == 0 && !isRecomputing {
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
            .confirmationDialog("Sort Expenses", isPresented: $showingSortOptions, titleVisibility: .visible) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(option.rawValue) {
                        HapticManager.shared.selectionChanged()
                        sortOption = option
                        scrollToTop = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    animateContent = true
                }
                // Reset scroll to top flag
                scrollToTop = false
                recomputeResults(resetPagination: true)
            }
            .onReceive(viewModel.$expenses) { _ in
                recomputeResults(resetPagination: false)
            }
            .onChange(of: sortOption) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: useDateRangeFilter) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: rangeStartDate) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: rangeEndDate) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: filterCategory) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: filterCustomCategoryId) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: showOnlySubscriptions) { _ in
                recomputeResults(resetPagination: true)
            }
            .onChange(of: categoryViewModel.customCategories) { _ in
                recomputeResults(resetPagination: false)
            }
            .onChange(of: searchText) { _ in
                recomputeSearchDebounced()
            }
        }
        .if(isIPad) { view in
            view.navigationViewStyle(StackNavigationViewStyle())
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
        .sheet(isPresented: $showingDateRangePicker) {
            dateRangeSheet
        }
    }
    
    private var dateRangeSheet: some View {
        NavigationView {
            Form {
                Toggle("Filter by date range", isOn: $useDateRangeFilter)
                
                DatePicker("Start", selection: $rangeStartDate, displayedComponents: [.date])
                    .disabled(!useDateRangeFilter)
                DatePicker("End", selection: $rangeEndDate, displayedComponents: [.date])
                    .disabled(!useDateRangeFilter)
                
                if useDateRangeFilter {
                    Button("Clear Date Filter") {
                        HapticManager.shared.selectionChanged()
                        useDateRangeFilter = false
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDateRangePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if rangeEndDate < rangeStartDate {
                            let tmp = rangeStartDate
                            rangeStartDate = rangeEndDate
                            rangeEndDate = tmp
                        }
                        showingDateRangePicker = false
                        scrollToTop = true
                    }
                }
            }
        }
        .onAppear {
            guard !didApplyInitialFilter, let initialFilter else { return }
            didApplyInitialFilter = true
            
            if initialFilter.useDateRangeFilter,
               let start = initialFilter.rangeStartDate,
               let end = initialFilter.rangeEndDate {
                useDateRangeFilter = true
                rangeStartDate = start
                rangeEndDate = end
            }
            
            showOnlySubscriptions = initialFilter.showOnlySubscriptions
            
            if let raw = initialFilter.filterCategoryRawValue,
               let cat = Expense.Category(rawValue: raw) {
                filterCategory = cat
                filterCustomCategoryId = initialFilter.filterCustomCategoryId
            } else {
                filterCategory = nil
                filterCustomCategoryId = nil
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
                    if isRecomputing && totalMatchCount == 0 {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    
                    if shouldGroupByDate {
                        ForEach(Array(visibleDateGroups.enumerated()), id: \.element.0) { index, dateGroup in
                            dateGroupView(index: index, dateGroup: dateGroup)
                                .onAppear {
                                    if index == max(0, visibleDateGroups.count - 1) {
                                        loadMoreIfNeeded()
                                    }
                                }
                        }
                    } else {
                        ForEach(Array(visibleExpenses.enumerated()), id: \.element.id) { idx, expense in
                            ExpenseCard(expense: expense)
                                .environmentObject(viewModel)
                                .environmentObject(categoryViewModel)
                                .padding(.horizontal)
                                .padding(.top, idx == 0 ? 12 : 0)
                                .onTapGesture {
                                    HapticManager.shared.impact(style: .light)
                                    selectedExpense = expense
                                }
                                .onAppear {
                                    if idx == max(0, visibleExpenses.count - 1) {
                                        loadMoreIfNeeded()
                                    }
                                }
                        }
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
            }
        }
        .background(Color.systemBackground)
        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func expenseRowView(expense: Expense, groupIndex: Int, expenseIndex: Int) -> some View {
        ExpenseCard(expense: expense)
            .environmentObject(viewModel)
            .environmentObject(categoryViewModel)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.systemBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.shared.impact(style: .light)
                selectedExpense = expense
            }
            .contextMenu {
                Button {
                    selectedExpense = expense
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    HapticManager.shared.impact(style: .medium)
                    deleteExpense(expense)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    HapticManager.shared.impact(style: .medium)
                    deleteExpense(expense)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 20)
            .animation(
                totalMatchCount <= 120
                    ? .spring(response: 0.6, dampingFraction: 0.8).delay(0.1 + Double(groupIndex) * 0.05 + Double(expenseIndex) * 0.03)
                    : .none,
                value: animateContent
            )
    }
    // Grouping is precomputed in `recomputeResults` for date sorts; display limiting is applied by `visibleDateGroups`.
    
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

    init(initialFilter: AllExpensesInitialFilter? = nil) {
        self.initialFilter = initialFilter
    }
}

struct AllExpensesView_Previews: PreviewProvider {
    static var previews: some View {
        AllExpensesView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
    }
} 