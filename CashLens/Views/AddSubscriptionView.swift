import SwiftUI

/// Add / Edit Subscription screen.
///
/// v2 design — visual twin of `AddExpenseView`. Same polished header,
/// same centered hero amount tile (with the frequency selector pill
/// where AddExpense puts the payment pill), same placeholder-driven
/// title field, same usage-sorted horizontal category row, same
/// inline date chips (Today / Tomorrow / Pick), same "More options"
/// collapsible for the secondary fields (Reminder, Notes), and the
/// same solid bottom CTA strip. Every add-sheet in the app now wears
/// the same hat.
///
/// Differences from AddExpense:
/// - **Frequency pill** above the hero amount instead of the wallet-
///   style payment pill. Same shape, same Menu pattern, region-
///   appropriate options.
/// - **Tomorrow** (not Yesterday) is the second quick date chip — for
///   a *future-billing* date, looking forward is the natural default.
/// - **Reminder** lives inside More options instead of Receipt.
struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @ObservedObject var subscriptionViewModel: SubscriptionViewModel

    // MARK: - State

    @State private var name: String
    @State private var amount: String
    @State private var startDate: Date
    @State private var frequency: Subscription.Frequency
    @State private var selectedCategory: Expense.Category
    @State private var selectedCustomCategoryId: UUID?
    @State private var notes: String
    @State private var reminderEnabled: Bool
    @State private var reminderDaysBefore: Int

    @State private var showingManageCategories = false
    @State private var showingCategoryPicker = false
    @State private var showingDatePicker = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var moreOptionsExpanded: Bool

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, amount, notes }

    // MARK: - Init

    let editingSubscription: Subscription?
    var isEditing: Bool { editingSubscription != nil }

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
        _moreOptionsExpanded = State(initialValue: false)
    }

    init(subscriptionViewModel: SubscriptionViewModel, editingSubscription: Subscription) {
        self.subscriptionViewModel = subscriptionViewModel
        self.editingSubscription = editingSubscription

        _name = State(initialValue: editingSubscription.name)
        // Mirror AddExpense — store only the numeric value, never the
        // formatted symbol. The visible hero amount injects the
        // currency symbol itself, so a pre-formatted incoming value
        // would render as "₹ ₹12.00" on the editing pass.
        _amount = State(initialValue: Self.sanitizeIncomingAmount(
            String(format: "%.2f", editingSubscription.amount)
        ))
        _startDate = State(initialValue: editingSubscription.startDate)
        _frequency = State(initialValue: editingSubscription.frequency)
        _selectedCategory = State(initialValue: editingSubscription.category)
        _selectedCustomCategoryId = State(initialValue: editingSubscription.customCategoryId)
        _notes = State(initialValue: editingSubscription.notes ?? "")
        _reminderEnabled = State(initialValue: editingSubscription.reminderEnabled)
        _reminderDaysBefore = State(initialValue: editingSubscription.reminderDaysBefore)
        // Auto-expand More options when editing if any of those fields
        // are populated — otherwise the user wouldn't see their note
        // or reminder configuration unless they hunted for it.
        _moreOptionsExpanded = State(initialValue:
            !(editingSubscription.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || editingSubscription.reminderEnabled
        )
    }

    /// Strip currency symbols / grouping characters from an incoming
    /// amount so the hero display always gets a clean numeric string.
    /// Same helper AddExpense uses for the same reason.
    private static func sanitizeIncomingAmount(_ raw: String) -> String {
        let allowed = Set<Character>("0123456789.,-")
        let cleaned = String(raw.filter { allowed.contains($0) })
        return cleaned.isEmpty ? raw : cleaned
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerStrip
                formScrollContent
                saveButton
            }
        }
        .navigationBarHidden(true)
        // App-wide sheet convention: visible grab handle on every
        // custom-chrome sheet, with the header giving it clear air.
        .presentationDragIndicator(.visible)
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
        .sheet(isPresented: $showingCategoryPicker) {
            categoryPickerSheet
        }
        .sheet(isPresented: $showingDatePicker) {
            startDatePickerSheet
        }
    }

    // MARK: - Header (shared SheetHeader convention)

    private var headerStrip: some View {
        SheetHeader(
            eyebrow: "Subscription",
            title: isEditing ? "Editing" : "Add New",
            onClose: { dismiss() }
        ) {
            headerTrailingSlot
        }
    }

    @ViewBuilder
    private var headerTrailingSlot: some View {
        if isEditing {
            Button {
                HapticManager.shared.warning()
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.red.opacity(0.22), lineWidth: 0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete this subscription")
        } else {
            SheetHeaderSpacer()
        }
    }

    // MARK: - Form scroll content

    private var formScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.xxxl) {
                heroAmountTile
                compactNameField
                smartCategoryRow
                inlineDateField
                moreOptionsSection
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Theme.Motion.snappy, value: frequency)
        .animation(Theme.Motion.snappy, value: startDate)
        .animation(Theme.Motion.snappy, value: moreOptionsExpanded)
        .animation(Theme.Motion.snappy, value: reminderEnabled)
    }

    // MARK: - Hero amount tile (twin of AddExpense)

    private var heroAmountTile: some View {
        VStack(spacing: Theme.Spacing.lg) {
            frequencySelectorPill
            heroAmountEyebrow
            heroAmountValueRow

            // Inline "Next:" preview under the hero so the user can
            // see exactly what their billing schedule means without
            // opening the date picker.
            Text(nextPreviewText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xxl)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.lightTap()
            focusedField = .amount
        }
        .animation(Theme.Motion.snappy, value: focusedField == .amount)
    }

    /// Frequency selector — sits where AddExpense puts the payment
    /// pill, same shape and Menu pattern so the two screens are
    /// instantly recognisable as siblings.
    private var frequencySelectorPill: some View {
        Menu {
            ForEach(Subscription.Frequency.allCases, id: \.self) { freq in
                Button {
                    HapticManager.shared.lightTap()
                    frequency = freq
                } label: {
                    if frequency == freq {
                        Label(freq.rawValue, systemImage: "checkmark")
                    } else {
                        Label(freq.rawValue, systemImage: freq.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: frequency.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.appPrimary)
                Text(frequency.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
        .accessibilityLabel("Billing frequency: \(frequency.rawValue). Tap to change.")
    }

    private var heroAmountEyebrow: some View {
        Text("BILLING AMOUNT")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(1.4)
            .padding(.horizontal, Theme.Spacing.xl)
    }

    /// Centered hero amount with the same ghost-mirror optical-
    /// centering trick AddExpense uses, and the same invisible
    /// `TextField` overlay that captures keystrokes.
    private var heroAmountValueRow: some View {
        ZStack {
            TextField("", text: $amount)
                .focused($focusedField, equals: .amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .opacity(0.001)
                .frame(maxWidth: .infinity, minHeight: 80)
                .allowsHitTesting(false)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(expenseViewModel.selectedCurrency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)

                Text(displayAmount)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(displayAmount == "0" ? .primary.opacity(0.25) : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .contentTransition(.numericText())

                Text(expenseViewModel.selectedCurrency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.clear)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var displayAmount: String {
        amount.isEmpty ? "0" : amount
    }

    private var nextPreviewText: String {
        let next = Subscription.calculateNextDueDate(from: startDate, frequency: frequency)
        return "Next bill: \(Self.previewDateFormatter.string(from: next)) · \(frequency.description)"
    }

    private static let previewDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - Compact name field (twin of AddExpense compactTitleField)

    private var compactNameField: some View {
        TextField("Netflix, Spotify, Gym…", text: $name)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .fieldCard(isFocused: focusedField == .name)
            .contentShape(Rectangle())
            .onTapGesture { focusedField = .name }
    }

    // MARK: - Smart category row (twin of AddExpense)

    private var smartCategoryRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Category")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                Button {
                    HapticManager.shared.lightTap()
                    showingManageCategories = true
                } label: {
                    HStack(spacing: 3) {
                        Text("Manage")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md + 2) {
                    ForEach(sortedCategoryEntries) { entry in
                        switch entry {
                        case .defaultCat(let category):
                            categoryGridCell(category).frame(width: 70)
                        case .customCat(let category):
                            customCategoryGridCell(category).frame(width: 70)
                        }
                    }
                    browseCategoriesTile.frame(width: 70)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    /// Heterogeneous category entry — default or custom.
    enum CategoryEntry: Identifiable {
        case defaultCat(Expense.Category)
        case customCat(CustomCategory)

        var id: String {
            switch self {
            case .defaultCat(let c): return "d_\(c.rawValue)"
            case .customCat(let c):  return "c_\(c.id.uuidString)"
            }
        }
    }

    /// Categories sorted by usage across the user's **subscriptions**
    /// (not expenses). The order is stable across selections so the
    /// row doesn't reshuffle when the user taps — same UX rule as
    /// AddExpense.
    private var sortedCategoryEntries: [CategoryEntry] {
        var counts: [String: Int] = [:]
        for s in subscriptionViewModel.subscriptions {
            if s.category == .custom, let id = s.customCategoryId {
                counts["c_\(id.uuidString)", default: 0] += 1
            } else {
                counts["d_\(s.category.rawValue)", default: 0] += 1
            }
        }

        var entries: [CategoryEntry] = []
        for c in expenseViewModel.getAvailableDefaultCategories() {
            entries.append(.defaultCat(c))
        }
        for c in categoryViewModel.customCategories {
            entries.append(.customCat(c))
        }

        return entries.sorted { a, b in
            (counts[a.id] ?? 0) > (counts[b.id] ?? 0)
        }
    }

    private func categoryGridCell(_ category: Expense.Category) -> some View {
        let isSelected = selectedCategory == category && selectedCustomCategoryId == nil
        return Button {
            HapticManager.shared.selectionChanged()
            selectedCategory = category
            if category != .custom { selectedCustomCategoryId = nil }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.forCategory(category.color).opacity(isSelected ? 0.30 : 0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color.forCategory(category.color))
                }
                .overlay(
                    Circle().stroke(
                        isSelected ? Color.forCategory(category.color).opacity(0.9) : Color.clear,
                        lineWidth: 2.5
                    )
                )

                Text(category.rawValue.capitalized)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.forCategory(category.color) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func customCategoryGridCell(_ category: CustomCategory) -> some View {
        let isSelected = selectedCategory == .custom && selectedCustomCategoryId == category.id
        return Button {
            HapticManager.shared.selectionChanged()
            selectedCategory = .custom
            selectedCustomCategoryId = category.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.forCategory(category.colorName).opacity(isSelected ? 0.30 : 0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color.forCategory(category.colorName))
                }
                .overlay(
                    Circle().stroke(
                        isSelected ? Color.forCategory(category.colorName).opacity(0.9) : Color.clear,
                        lineWidth: 2.5
                    )
                )

                Text(category.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.forCategory(category.colorName) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var browseCategoriesTile: some View {
        Button {
            HapticManager.shared.lightTap()
            showingCategoryPicker = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.10))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle().stroke(Color.appPrimary.opacity(0.25),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        )
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.appPrimary)
                }
                Text("Browse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse all categories")
    }

    private var categoryPickerSheet: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm + 2, alignment: .top),
                    count: 4
                )

                LazyVGrid(columns: columns, alignment: .center, spacing: Theme.Spacing.lg) {
                    ForEach(expenseViewModel.getAvailableDefaultCategories(), id: \.self) { category in
                        Button {
                            HapticManager.shared.selectionChanged()
                            selectedCategory = category
                            if category != .custom { selectedCustomCategoryId = nil }
                            showingCategoryPicker = false
                        } label: {
                            categoryGridCell(category).allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(categoryViewModel.customCategories, id: \.id) { category in
                        Button {
                            HapticManager.shared.selectionChanged()
                            selectedCategory = .custom
                            selectedCustomCategoryId = category.id
                            showingCategoryPicker = false
                        } label: {
                            customCategoryGridCell(category).allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Choose Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingCategoryPicker = false }
                        .fontWeight(.semibold)
                        .foregroundColor(.appPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Inline start date (twin of AddExpense inlineDateField)

    /// Compact date editor — three chips: Today, Tomorrow, Pick. The
    /// 90% case (a sub starting today / tomorrow) is one tap; any
    /// other date opens the picker sheet.
    private var inlineDateField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Start Date")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 2)

            HStack(spacing: Theme.Spacing.sm) {
                dateChip(
                    title: "Today",
                    selected: Calendar.current.isDateInToday(startDate)
                ) {
                    HapticManager.shared.selectionChanged()
                    startDate = Date()
                }

                dateChip(
                    title: "Tomorrow",
                    selected: Calendar.current.isDateInTomorrow(startDate)
                ) {
                    HapticManager.shared.selectionChanged()
                    startDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                }

                pickDateChip
            }
        }
    }

    private func dateChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .background(
                    Capsule().fill(selected ? Color.appPrimary : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var pickDateChip: some View {
        let cal = Calendar.current
        let isCustom = !cal.isDateInToday(startDate) && !cal.isDateInTomorrow(startDate)

        return Button {
            HapticManager.shared.lightTap()
            focusedField = nil
            showingDatePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text(isCustom ? pickChipDateString(startDate) : "Pick a date")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(isCustom ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                Capsule().fill(isCustom ? Color.appPrimary : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(isCustom ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isCustom
                ? "Custom date \(pickChipDateString(startDate)). Tap to change."
                : "Pick a date"
        )
    }

    private static let pickChipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private func pickChipDateString(_ d: Date) -> String {
        Self.pickChipDateFormatter.string(from: d)
    }

    private var startDatePickerSheet: some View {
        VStack {
            DatePicker("", selection: $startDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()

            Button("Done") { showingDatePicker = false }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.appPrimary)
                .padding()
        }
        .presentationDetents([.height(360)])
        .presentationBackground(Color(uiColor: .systemBackground))
    }

    // MARK: - More options collapsible (twin of AddExpense)

    private var moreOptionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            moreOptionsToggle

            if moreOptionsExpanded {
                VStack(spacing: 0) {
                    reminderRow

                    Divider().padding(.leading, 52).opacity(0.35)

                    notesRow
                }
                .cardSurface()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    private var moreOptionsToggle: some View {
        Button {
            HapticManager.shared.lightTap()
            focusedField = nil
            withAnimation(Theme.Motion.snappy) {
                moreOptionsExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: moreOptionsExpanded ? "chevron.up" : "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(moreOptionsExpanded ? "Hide reminder & notes" : "Add reminder or notes")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if !moreOptionsExpanded {
                    moreOptionsSummaryChips
                }
            }
            .foregroundColor(.appPrimary)
            .padding(.horizontal, Theme.Spacing.md + 2)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Color.appPrimary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(Color.appPrimary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var moreOptionsSummaryChips: some View {
        let hasReminder = reminderEnabled
        let hasNote = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasReminder || hasNote {
            HStack(spacing: 6) {
                if hasReminder {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                if hasNote {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundColor(.appPrimary)
        }
    }

    // MARK: - Reminder row inside More options

    @ViewBuilder
    private var reminderRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: reminderEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(reminderEnabled ? .appPrimary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill((reminderEnabled ? Color.appPrimary : Color.secondary).opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment reminder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(reminderEnabled
                         ? "Notify me \(reminderDaysBefore) day\(reminderDaysBefore == 1 ? "" : "s") before"
                         : "Off")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Toggle("", isOn: $reminderEnabled.animation(Theme.Motion.snappy))
                    .labelsHidden()
                    .tint(.appPrimary)
            }
            .padding(.horizontal, Theme.Spacing.md + 2)
            .padding(.vertical, Theme.Spacing.md - 2)

            if reminderEnabled {
                Divider().padding(.leading, 52).opacity(0.35)

                HStack(spacing: Theme.Spacing.sm) {
                    Text("Days before")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach([1, 2, 3, 7], id: \.self) { d in
                            reminderDayChip(d)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md + 2)
                .padding(.vertical, Theme.Spacing.md - 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(isSelected ? Color.appPrimary : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes row inside More options

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(notes.isEmpty ? .secondary : .appPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill((notes.isEmpty ? Color.secondary : Color.appPrimary).opacity(0.12)))

                Text("Note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            TextField("Plan details, account email…", text: $notes, axis: .vertical)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(3, reservesSpace: false)
                .focused($focusedField, equals: .notes)
                .padding(.horizontal, Theme.Spacing.md + 2)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .padding(.leading, Theme.Spacing.md + 2 + 28 + Theme.Spacing.md - (Theme.Spacing.md + 2))
                .padding(.trailing, Theme.Spacing.md + 2)
        }
        .padding(.horizontal, Theme.Spacing.md + 2)
        .padding(.top, Theme.Spacing.md - 2)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Save button (twin of AddExpense)

    private var saveButton: some View {
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
                    radius: 12, x: 0, y: 6
                )
            }
            .disabled(!isValid || isSaving)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
            .background(Color(uiColor: .systemBackground))
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
        guard let parsed = expenseViewModel.parseAmount(amount), parsed > 0 else {
            return false
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Persistence

    private func saveSubscription() {
        guard let parsedAmount = expenseViewModel.parseAmount(amount) else {
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
