import SwiftUI
import PhotosUI

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @ObservedObject private var templateStore = ExpenseTemplateStore.shared
    /// Pro gate for the Receipt Scanner section. Read via the
    /// singleton so call sites that don't already inject `ProManager`
    /// continue to work — and the view still reacts to `isPro` flipping
    /// after a successful purchase.
    @ObservedObject private var proManager = ProManager.shared

    // State for form fields when adding new expense
    @State private var title: String
    @State private var amount: String
    @State private var date: Date
    @State private var selectedCategory: Expense.Category
    @State private var selectedCustomCategoryId: UUID?
    @State private var notes: String
    @State private var tags: [String]
    @State private var isRefund: Bool
    /// Optional payment instrument. Free for everyone — capturing this is
    /// frictionless data; the Pro analytics donut on Statistics is what
    /// users upgrade for.
    @State private var paymentMethod: PaymentMethod?

    // MARK: - Receipt Scanner state (Pro)
    //
    // The Pro gate lives on the *capture* buttons (Scan / Library), not
    // on storage or display — so a downgraded Pro user still sees and
    // can remove receipts they previously attached. That matches our
    // theme/icon "no data loss after lapse" rule.
    /// Filename of the currently attached receipt, or `nil`. Persisted
    /// to the model on save; held in @State here so the user can attach
    /// → preview → remove without committing the form.
    @State private var receiptImagePath: String?
    /// Cached `UIImage` for the in-form preview. Loaded from disk in
    /// `.task` whenever `receiptImagePath` changes. Kept on @State so
    /// the preview thumbnail doesn't flash during view recomposition.
    @State private var receiptImage: UIImage?
    /// PhotosPicker selection — bound to the picker; we observe changes
    /// and convert to a `UIImage` → file on disk.
    @State private var pickedPhotoItem: PhotosPickerItem?
    /// Drives the VisionKit document scanner full-screen cover.
    @State private var showingScanner: Bool = false
    /// Drives the full-screen receipt viewer modal.
    @State private var showingReceiptViewer: Bool = false
    /// Set when a free user taps a Pro-gated receipt button.
    @State private var showingReceiptPaywall: Bool = false
    /// True while we're compressing/writing a freshly captured image.
    /// Surfaces a small spinner on the receipt card so users know the
    /// app is working — JPEG encoding a 12 MP photo on an older device
    /// can take 200–400 ms.
    @State private var isProcessingReceipt: Bool = false
    /// Non-blocking error message shown inline if `ReceiptStorage`
    /// fails to write. Auto-clears after 4 seconds. Failure is rare —
    /// usually means the user is at quota.
    @State private var receiptErrorMessage: String?
    /// Tracks the original receipt path so we can delete the old file
    /// when the user replaces a receipt or removes it before saving.
    @State private var originalReceiptImagePath: String?

    @State private var showingKeyboard: Bool
    @State private var showingManageCategories: Bool
    @State private var showingDatePicker: Bool

    // Template state
    @State private var showingSaveTemplateAlert: Bool = false
    @State private var templateNameInput: String = ""
    @State private var pendingTemplateDeletionId: UUID? = nil
    @State private var lastAppliedTemplateId: UUID? = nil
    @State private var showingTemplatesInfo: Bool = false
    /// Form state captured *before* the most recent chip tap. Used to roll
    /// back when the user taps a different chip without editing in between
    /// — this keeps template-switching predictable while still preserving
    /// any values the user typed manually.
    @State private var preApplySnapshot: TemplateApplySnapshot? = nil
    /// Form state captured *after* the most recent chip tap. If the current
    /// form still equals this exactly, we know the user hasn't manually
    /// changed anything since, so it's safe to swap templates wholesale.
    @State private var postApplySnapshot: TemplateApplySnapshot? = nil

    /// Lightweight value type that mirrors the form fields a template can fill.
    /// Equatable so we can detect "the user hasn't changed anything since the
    /// last chip tap" with a single comparison.
    private struct TemplateApplySnapshot: Equatable {
        var title: String
        var amount: String
        var category: Expense.Category
        var customCategoryId: UUID?
        var notes: String
        var tags: [String]
        var isRefund: Bool
        var paymentMethod: PaymentMethod?
    }
    
    @FocusState private var focusedField: Field?
    private enum Field: Hashable {
        case amount
        case title
        case notes
    }
    
    // Animation states
    // PERF: Removed `animateCircle` / `showForm` / `animateButton` —
    // they were set in `.onAppear` via `withAnimation(Theme.Motion.emphasized)`
    // but never actually read by any view. The animation block was pure
    // overhead that competed with the system sheet spring, contributing
    // to the "sheet lifts slowly" feel.
    @State private var isSaving: Bool = false
    
    // Additional parameters
    var isEditing: Bool
    /// Saved when editing an existing expense. The trailing `String?`
    /// (receipt image path) was added in v2.0 alongside the Receipt
    /// Scanner; the trailing `PaymentMethod?` was added in v2.2. All
    /// call-sites are updated to pass them through. Older callers
    /// haven't existed since either field shipped, so there's no
    /// compatibility shim needed.
    var onSave: ((String, Double, Date, Expense.Category, UUID?, String?, [String]?, Bool, PaymentMethod?, String?) -> Void)?
    var expenseId: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var showingDraftRestored = false
    @State private var showingDuplicateConfirmation = false
    @State private var pendingAmountValue: Double = 0
    /// PERF: Cached suggestion driven by `onChange(of: title)` instead of
    /// being recomputed inside `body`. Previously the suggestion ran the
    /// O(N) `CategorySuggester.suggest(for:history:)` over every expense
    /// in history (capped at 1500) on **every body re-render** — i.e.
    /// every keystroke, every state change, every parent invalidation.
    /// Now we recompute off-main and only when the title actually
    /// changes.
    @State private var cachedCategorySuggestion: CategorySuggester.Suggestion? = nil
    @State private var categorySuggestionTask: Task<Void, Never>? = nil
    
    // Draft state key
    private let draftKey = UserDefaultsKeys.expenseDraft
    
    // Date formatter
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mma"
        return formatter
    }()
    
    // Initialize for adding new expense.
    //
    // PERF: Kept deliberately lightweight. Previously this `init` did a
    // synchronous `UserDefaults.data(forKey:)` + `JSONDecoder.decode` for
    // the saved draft, which runs **before the sheet animation can
    // start** and was a measurable cause of "the bottom sheet lifts
    // slowly". The draft is now restored in `restoreDraftIfPresent()`,
    // called from `.task` once the sheet has lifted — the form renders
    // empty for one frame then populates, which feels instant.
    init(viewModel: ExpenseViewModel) {
        self.viewModel = viewModel
        self.isEditing = false
        self.onSave = nil

        // Empty / default state — the draft (if any) populates in `.task`.
        _title = State(initialValue: "")
        _amount = State(initialValue: "")
        _date = State(initialValue: Date())
        _selectedCategory = State(initialValue: .food)
        _selectedCustomCategoryId = State(initialValue: nil)
        _notes = State(initialValue: "")
        _tags = State(initialValue: [])
        _isRefund = State(initialValue: false)
        _paymentMethod = State(initialValue: nil)
        // Drafts deliberately don't persist receipt paths — restoring a
        // receipt across app launches would mean keeping the file on
        // disk for an indefinite period (orphan, until the draft is
        // either saved or the user adds a different one). Easier and
        // cleaner to require the user re-attach if they reopen the
        // form. Receipts only matter on real saved expenses.
        _receiptImagePath = State(initialValue: nil)
        _originalReceiptImagePath = State(initialValue: nil)
        _showingKeyboard = State(initialValue: false)
        _showingManageCategories = State(initialValue: false)
        _showingDatePicker = State(initialValue: false)
        _isSaving = State(initialValue: false)
        _showingDraftRestored = State(initialValue: false)
    }
    
    // Initialize for editing existing expense
    init(
        viewModel: ExpenseViewModel,
        title: String,
        amount: String,
        date: Date,
        selectedCategory: Expense.Category,
        selectedCustomCategoryId: UUID?,
        notes: String,
        tags: [String] = [],
        isRefund: Bool = false,
        paymentMethod: PaymentMethod? = nil,
        receiptImagePath: String? = nil,
        isEditing: Bool,
        expenseId: UUID,
        onSave: @escaping (String, Double, Date, Expense.Category, UUID?, String?, [String]?, Bool, PaymentMethod?, String?) -> Void
    ) {
        self.viewModel = viewModel
        self.isEditing = isEditing
        self.onSave = onSave
        self.expenseId = expenseId

        // Initialize state with provided values
        _title = State(initialValue: title)
        _amount = State(initialValue: amount)
        _date = State(initialValue: date)
        _selectedCategory = State(initialValue: selectedCategory)
        _selectedCustomCategoryId = State(initialValue: selectedCustomCategoryId)
        _notes = State(initialValue: notes)
        _tags = State(initialValue: tags)
        _isRefund = State(initialValue: isRefund)
        _paymentMethod = State(initialValue: paymentMethod)
        _receiptImagePath = State(initialValue: receiptImagePath)
        // Capture the path the row started with. Used in the form's
        // teardown / save path to delete the previous file when the
        // user replaces or removes a receipt before saving — without
        // this we'd leak the old image file on every replace.
        _originalReceiptImagePath = State(initialValue: receiptImagePath)
        _showingKeyboard = State(initialValue: false)
        _showingManageCategories = State(initialValue: false)
        _showingDatePicker = State(initialValue: false)
        _isSaving = State(initialValue: false)
        _showingDeleteConfirmation = State(initialValue: false)
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: Theme.Spacing.lg) {
                    HStack {
                        Button(action: {
                            if !isEditing {
                                clearDraft()
                            }
                            cleanupUnsavedReceipt()
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
                        } else {
                            saveAsTemplateButton
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.xl)
                    .animation(Theme.Motion.snappy, value: canSaveCurrentAsTemplate)

                    VStack(spacing: Theme.Spacing.sm) {
                        Text(isEditing ? "Edit Expense" : "Add Expense")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(isEditing ? "Update your expense details" : "Track a new expense")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, Theme.Spacing.sm)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xxxl - 4) {
                        if showingDraftRestored && !isEditing {
                            draftRestoredBanner
                        }

                        if !isEditing && !templateStore.templates.isEmpty {
                            templatesChipStrip
                        }

                        amountField
                        refundToggleRow
                        titleField
                        suggestedCategoryRow
                        categoryPickerField
                        paymentMethodField
                        datePickerField
                        tagsField
                        notesField
                        receiptField
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.sm + 2)
                    .padding(.bottom, 40)
                }

                saveButton
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog("Possible duplicate", isPresented: $showingDuplicateConfirmation, titleVisibility: .visible) {
            Button("Save anyway", role: .destructive) {
                HapticManager.shared.warning()
                isSaving = true
                addExpense()
            }
            Button("Review", role: .cancel) {
                isSaving = false
            }
        } message: {
            Text("A similar expense (same title + amount) was added around the same time. Do you want to save anyway?")
        }
        // Delete confirmation alert
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Expense"),
                message: Text("Are you sure you want to delete this expense? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    // Delete the expense
                    deleteExpense()
                },
                secondaryButton: .cancel()
            )
        }
        // Auto-save draft functionality for new expenses
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && !isEditing {
                saveDraft()
            }
        }
        .onChange(of: title) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
                recomputeCategorySuggestion()
            }
        }
        .onChange(of: amount) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
                recomputeCategorySuggestion()
            }
        }
        .onChange(of: selectedCustomCategoryId) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
                recomputeCategorySuggestion()
            }
        }
        .onChange(of: notes) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: date) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: tags) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .onChange(of: paymentMethod) { _, _ in
            if !isEditing {
                saveDraftWithDelay()
            }
        }
        .alert("Save as template", isPresented: $showingSaveTemplateAlert) {
            TextField("Template name", text: $templateNameInput)
            Button("Save", action: saveCurrentAsTemplate)
                .disabled(templateNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saved templates appear above the form for one-tap reuse.")
        }
        // MARK: Receipt Scanner — sheets, covers, and pipeline hooks
        //
        // The scanner is full-screen (the camera viewfinder needs the
        // whole canvas; presenting in a sheet clips it badly). Picker
        // results land via `.onChange(of: pickedPhotoItem)` and run
        // through `attachReceipt(image:)`, which compresses + writes
        // off-main and updates form state on success.
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView(
                onCapture: { image in
                    showingScanner = false
                    attachReceipt(image: image)
                },
                onDismiss: { showingScanner = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingReceiptViewer) {
            if let img = receiptImage {
                ReceiptViewerView(
                    image: img,
                    onDismiss: { showingReceiptViewer = false },
                    onDelete: {
                        showingReceiptViewer = false
                        removeAttachedReceipt()
                    }
                )
            }
        }
        .sheet(isPresented: $showingReceiptPaywall) {
            PaywallView()
        }
        .onChange(of: pickedPhotoItem) { _, newItem in
            // Convert the PhotosPicker selection to a UIImage off-main,
            // then route through `attachReceipt` to compress + persist.
            // Resetting `pickedPhotoItem` to nil immediately after we
            // grab it lets the user pick the same image twice in a row
            // (otherwise SwiftUI sees no change and the picker no-ops).
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        attachReceipt(image: image)
                        pickedPhotoItem = nil
                    }
                } else {
                    await MainActor.run { pickedPhotoItem = nil }
                }
            }
        }
        .task(id: receiptImagePath) {
            // Combined into a single `.task` modifier rather than two
            // adjacent ones to keep the body's type-checker complexity
            // within budget. `restoreDraftIfPresent()` short-circuits if
            // editing, if the user has already typed, or if there's no
            // saved draft, so running it again when `receiptImagePath`
            // changes is a cheap no-op.
            await loadReceiptImage(for: receiptImagePath)
            restoreDraftIfPresent()
        }
        .alert("About Templates", isPresented: $showingTemplatesInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Templates are saved presets for expenses you log often — like 'Morning coffee · $4 · Food'.\n\n• Tap a chip to fill the form (your typed values are kept).\n• Long-press to remove a chip.\n• Use the 'Save preset' button at the top of this screen to save the current entry as a new template.")
        }
        .alert(
            "Delete template?",
            isPresented: Binding(
                get: { pendingTemplateDeletionId != nil },
                set: { if !$0 { pendingTemplateDeletionId = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingTemplateDeletionId {
                    HapticManager.shared.warning()
                    withAnimation(Theme.Motion.snappy) {
                        templateStore.remove(id: id)
                    }
                }
                pendingTemplateDeletionId = nil
            }
            Button("Cancel", role: .cancel) { pendingTemplateDeletionId = nil }
        } message: {
            Text("This template will be removed. You can always create a new one from any expense form.")
        }
    }

    // MARK: - View Components

    private var draftRestoredBanner: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.appPrimary)

            Text("Previous draft restored")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            Button("Dismiss") {
                withAnimation(Theme.Motion.snappy) {
                    showingDraftRestored = false
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.appPrimary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Color.appPrimary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private static let fieldLabelFont = Font.system(size: 18, weight: .bold, design: .rounded)

    private var titleField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Title")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            TextField("Expense title", text: $title)
                .font(.system(size: 17, weight: .medium))
                .focused($focusedField, equals: .title)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: focusedField == .title)
                .contentShape(Rectangle())
                .onTapGesture {
                    showingKeyboard = true
                    focusedField = .title
                }

            if !isEditing,
               focusedField == .title,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleSuggestions
            }
        }
    }

    private var titleSuggestions: some View {
        let suggestions = filteredTitleSuggestions()

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !suggestions.isEmpty {
                Text("Suggestions")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            HapticManager.shared.selectionChanged()
                            title = suggestion
                            showingKeyboard = false
                            focusedField = nil
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, Theme.Spacing.md + 2)
                            .padding(.vertical, Theme.Spacing.sm + 2)
                            .cardSurface(radius: Theme.Radius.chip)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Amount")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            HStack(spacing: Theme.Spacing.lg) {
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)

                TextField("0.00", text: $amount)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .fieldCard(isFocused: focusedField == .amount)
            .contentShape(Rectangle())
            .onTapGesture {
                showingKeyboard = true
                focusedField = .amount
            }
        }
    }
    
    private var datePickerField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Date")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            Button(action: {
                focusedField = nil
                showingDatePicker = true
            }) {
                HStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Color.appPrimary.opacity(0.15))
                            .frame(width: 48, height: 48)

                        Image(systemName: "calendar")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Selected Date")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)

                        Text(dateFormatter.string(from: date))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .cardSurface()
                .softShadow()
            }
            .buttonStyle(PlainButtonStyle())

            HStack(spacing: Theme.Spacing.sm + 2) {
                quickDateChip(title: "Today") {
                    HapticManager.shared.selectionChanged()
                    date = Date()
                }

                quickDateChip(title: "Yesterday") {
                    HapticManager.shared.selectionChanged()
                    date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            VStack {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .presentationDetents([.height(300)])

                Button("Done") {
                    showingDatePicker = false
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.appPrimary)
                .padding()
            }
            .presentationBackground(Color(.systemGroupedBackground))
        }
    }

    private func quickDateChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.appPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Refund toggle
    //
    // A clean tap-to-toggle chip that flips the entry between "expense" and
    // "refund". When on, totals subtract this row instead of adding it (see
    // `Expense.signedAmount` and `Sequence.netTotal()`). The chip's tint
    // shifts to green and the amount inverts visually so the user has a
    // clear at-a-glance signal that this row will reduce their spending.

    private var refundToggleRow: some View {
        Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                isRefund.toggle()
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: isRefund ? "arrow.uturn.backward.circle.fill" : "arrow.uturn.backward.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isRefund ? .green : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isRefund ? "Refund" : "Mark as refund")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isRefund ? .green : .primary)
                    Text(isRefund ? "Subtracted from totals" : "Money returned? Track it here")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                ZStack(alignment: isRefund ? .trailing : .leading) {
                    Capsule()
                        .fill(isRefund ? Color.green.opacity(0.25) : Color.secondary.opacity(0.18))
                        .frame(width: 38, height: 22)
                    Circle()
                        .fill(isRefund ? Color.green : Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: Color.black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isRefund ? Color.green.opacity(0.10) : Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(isRefund ? Color.green.opacity(0.30) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRefund ? "Marked as refund" : "Mark this entry as a refund")
    }

    // MARK: - Smart category suggestion
    //
    // When the user types a title, we run a tiny on-device frequency model
    // (`CategorySuggester`) over their own history and surface a single
    // "Suggested: Food" pill above the category picker. Tapping it adopts
    // the suggestion. The pill is suppressed in any of these cases so it's
    // never a distraction:
    //   • editing an existing expense
    //   • the suggestion matches the currently-selected category already
    //   • confidence below `CategorySuggester.minConfidence`
    //   • the title is empty / very short

    /// PERF: Now a simple cache read instead of an O(N) compute inside
    /// `body`. The cache is refreshed off-main by
    /// `recomputeCategorySuggestion` whenever the title changes (or the
    /// selection changes, so we can hide the suggestion if it already
    /// matches the current selection).
    private var categorySuggestion: CategorySuggester.Suggestion? {
        cachedCategorySuggestion
    }

    private func recomputeCategorySuggestion() {
        guard !isEditing else {
            cachedCategorySuggestion = nil
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= CategorySuggester.minQueryLength else {
            if cachedCategorySuggestion != nil { cachedCategorySuggestion = nil }
            return
        }

        // Snapshot the inputs the worker needs so we don't capture the
        // view (and we don't have to hop back to main just to read state).
        let history = viewModel.expenses
        let currentDefault = selectedCategory
        let currentCustomId = selectedCustomCategoryId

        categorySuggestionTask?.cancel()
        categorySuggestionTask = Task.detached(priority: .userInitiated) {
            // Tiny debounce — coalesces fast typing without making the
            // suggestion feel laggy on slow typing.
            try? await Task.sleep(nanoseconds: 120_000_000) // 120 ms
            if Task.isCancelled { return }

            let raw = CategorySuggester.suggest(for: trimmed, history: history)

            let next: CategorySuggester.Suggestion?
            if let s = raw {
                let alreadyMatchesDefault =
                    s.category != .custom
                    && s.category == currentDefault
                    && s.customCategoryId == nil
                let alreadyMatchesCustom =
                    s.category == .custom
                    && currentDefault == .custom
                    && s.customCategoryId == currentCustomId
                next = (alreadyMatchesDefault || alreadyMatchesCustom) ? nil : s
            } else {
                next = nil
            }

            if Task.isCancelled { return }
            await MainActor.run {
                cachedCategorySuggestion = next
            }
        }
    }

    private func suggestionDisplayName(_ s: CategorySuggester.Suggestion) -> String {
        if s.category == .custom, let id = s.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return custom.name
        }
        return s.category.displayName
    }

    private func suggestionAccentColor(_ s: CategorySuggester.Suggestion) -> Color {
        if s.category == .custom, let id = s.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return Color.forCategory(custom.colorName)
        }
        return Color.forCategory(s.category.color)
    }

    private func suggestionIcon(_ s: CategorySuggester.Suggestion) -> String {
        if s.category == .custom, let id = s.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return custom.icon
        }
        return s.category.icon
    }

    @ViewBuilder
    private var suggestedCategoryRow: some View {
        if let s = categorySuggestion {
            Button {
                HapticManager.shared.selectionChanged()
                withAnimation(Theme.Motion.snappy) {
                    selectedCategory = s.category
                    selectedCustomCategoryId = s.customCategoryId
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appPrimary)
                    Text("Suggested:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: suggestionIcon(s))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(suggestionAccentColor(s))
                        Text(suggestionDisplayName(s))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    Spacer(minLength: 0)
                    Text("Use")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.sm + 2)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.appPrimary)
                        )
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm + 2)
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
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            EmptyView()
        }
    }

    // MARK: - Templates

    /// Hides the Save action when the form already matches an existing
    /// template, when nothing meaningful has been entered, or when the cap
    /// has been reached. Prevents accidental clutter in the chip strip.
    private var canSaveCurrentAsTemplate: Bool {
        guard !isEditing, isFormValid else { return false }
        guard let amountValue = viewModel.parseAmount(amount), amountValue.isFinite, amountValue > 0 else {
            return false
        }
        let candidate = ExpenseTemplate(
            name: title,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amountValue,
            category: selectedCategory,
            customCategoryId: selectedCategory == .custom ? selectedCustomCategoryId : nil
        )
        if templateStore.containsTemplate(matching: candidate) { return false }
        if templateStore.templates.count >= ExpenseTemplateStore.maxTemplates { return false }
        return true
    }

    /// Header affordance for saving the current form as a reusable preset.
    /// Renders only when the form is in a savable state — keeps the header
    /// uncluttered while the user is still entering data, then animates in
    /// the labeled pill so the action is *self-explanatory* the moment it
    /// appears (no icon-only mystery button).
    @ViewBuilder
    private var saveAsTemplateButton: some View {
        if canSaveCurrentAsTemplate {
            Button {
                HapticManager.shared.lightTap()
                templateNameInput = title.trimmingCharacters(in: .whitespacesAndNewlines)
                showingSaveTemplateAlert = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Save preset")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Theme.Spacing.sm + 2)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.appPrimary.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(Color.appPrimary.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .accessibilityLabel("Save this entry as a reusable template")
        }
    }

    private var templatesChipStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.xs + 2) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.appPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Quick Templates")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.5)

                        Button {
                            HapticManager.shared.lightTap()
                            showingTemplatesInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.appPrimary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("What are templates")
                    }
                    Text("Tap a chip to fill the form")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.85))
                }

                Spacer(minLength: 0)

                Text("\(templateStore.templates.count) of \(ExpenseTemplateStore.maxTemplates)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.appPrimary.opacity(0.12)))
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm + 2) {
                    ForEach(templateStore.displayOrder) { template in
                        templateChip(template)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .transition(.opacity)
    }

    private func templateChip(_ template: ExpenseTemplate) -> some View {
        let accent = templateAccentColor(for: template)
        let icon = templateIcon(for: template)
        // "Applied" only stays true while the form still matches what we
        // filled in. The moment the user edits anything, the highlight
        // drops — so the chip never claims to be active when it isn't.
        let isApplied: Bool = {
            guard lastAppliedTemplateId == template.id else { return false }
            guard let post = postApplySnapshot else { return true }
            return currentTemplateApplySnapshot() == post
        }()
        return Button {
            applyTemplate(template)
        } label: {
            HStack(spacing: Theme.Spacing.sm - 2) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isApplied ? 0.25 : 0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(template.trimmedName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(viewModel.formattedAmount(template.amount))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, Theme.Spacing.sm)
            .padding(.trailing, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isApplied
                          ? accent.opacity(0.12)
                          : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(isApplied
                            ? accent.opacity(0.45)
                            : Color.secondary.opacity(0.15),
                            lineWidth: isApplied ? 1.2 : 1)
            )
            .scaleEffect(isApplied ? 1.02 : 1.0)
            .animation(Theme.Motion.snappy, value: isApplied)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                applyTemplate(template)
            } label: {
                Label("Use template", systemImage: "arrow.up.forward")
            }
            Button(role: .destructive) {
                pendingTemplateDeletionId = template.id
            } label: {
                Label("Delete template", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(template.trimmedName), \(viewModel.formattedAmount(template.amount))")
        .accessibilityHint("Double tap to fill the form with this template")
    }

    private func templateAccentColor(for template: ExpenseTemplate) -> Color {
        if template.category == .custom, let id = template.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return Color.forCategory(custom.colorName)
        }
        return Color.forCategory(template.category.color)
    }

    private func templateIcon(for template: ExpenseTemplate) -> String {
        if template.category == .custom, let id = template.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == id }) {
            return custom.icon
        }
        return template.category.icon
    }

    private func applyTemplate(_ template: ExpenseTemplate) {
        HapticManager.shared.selectionChanged()
        withAnimation(Theme.Motion.snappy) {
            // Step 1: if the form is still exactly what the previous chip
            // tap produced, the user hasn't edited anything since — roll
            // back to whatever they had before that tap. This is what makes
            // tapping a *different* chip actually update the form instead
            // of silently doing nothing because the fields are non-empty.
            if let post = postApplySnapshot,
               currentTemplateApplySnapshot() == post,
               let pre = preApplySnapshot {
                restore(from: pre)
            }

            // Step 2: capture the pre-apply baseline for *this* tap so a
            // subsequent chip tap can roll back to here if needed.
            let baseline = currentTemplateApplySnapshot()

            // Step 3: fill the form additively — never overwrite values the
            // user typed (or that survived rollback because they typed them
            // before the previous tap).
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = template.title
            }
            if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                amount = formatTemplateAmountForInput(template.amount)
            }
            selectedCategory = template.category
            selectedCustomCategoryId = template.category == .custom ? template.customCategoryId : nil
            if let templateNotes = template.notes, notes.isEmpty {
                notes = templateNotes
            }
            if let templateTags = template.tags, !templateTags.isEmpty {
                let existing = Set(tags.map { $0.lowercased() })
                for tag in templateTags where !existing.contains(tag.lowercased()) {
                    tags.append(tag)
                }
            }
            if template.isRefund && !isRefund {
                isRefund = true
            }
            // Payment method follows the same additive rule: only fill in
            // when the form has none, so a user who manually picked one
            // before tapping the chip keeps their choice.
            if let templatePM = template.paymentMethod, paymentMethod == nil {
                paymentMethod = templatePM
            }

            // Step 4: persist snapshots so the next chip tap can detect
            // "did the user edit since?" with a single equality check.
            preApplySnapshot = baseline
            postApplySnapshot = currentTemplateApplySnapshot()
            lastAppliedTemplateId = template.id
        }
        templateStore.markUsed(id: template.id)
    }

    private func currentTemplateApplySnapshot() -> TemplateApplySnapshot {
        TemplateApplySnapshot(
            title: title,
            amount: amount,
            category: selectedCategory,
            customCategoryId: selectedCustomCategoryId,
            notes: notes,
            tags: tags,
            isRefund: isRefund,
            paymentMethod: paymentMethod
        )
    }

    private func restore(from snapshot: TemplateApplySnapshot) {
        title = snapshot.title
        amount = snapshot.amount
        selectedCategory = snapshot.category
        selectedCustomCategoryId = snapshot.customCategoryId
        notes = snapshot.notes
        tags = snapshot.tags
        isRefund = snapshot.isRefund
        paymentMethod = snapshot.paymentMethod
    }

    private func formatTemplateAmountForInput(_ value: Double) -> String {
        // Mirror the input style: integers shown without decimals, others
        // shown with up to 2 decimals. Avoids "5.00" when "5" is friendlier.
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func saveCurrentAsTemplate() {
        guard let amountValue = viewModel.parseAmount(amount), amountValue.isFinite, amountValue > 0 else {
            return
        }
        let trimmedName = templateNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? trimmedTitle : trimmedName
        guard !resolvedName.isEmpty else { return }

        let template = ExpenseTemplate(
            name: String(resolvedName.prefix(40)),
            title: trimmedTitle,
            amount: amountValue,
            category: selectedCategory,
            customCategoryId: selectedCategory == .custom ? selectedCustomCategoryId : nil,
            notes: notes.isEmpty ? nil : notes,
            tags: tags.isEmpty ? nil : tags,
            isRefund: isRefund,
            paymentMethod: paymentMethod
        )
        HapticManager.shared.success()
        withAnimation(Theme.Motion.snappy) {
            templateStore.add(template)
        }
        templateNameInput = ""
    }

    private var categoryPickerField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Category")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    showingManageCategories = true
                }) {
                    HStack(spacing: Theme.Spacing.xs + 2) {
                        Text("Manage")
                            .foregroundColor(.appPrimary)

                        Image(systemName: "gearshape.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.appPrimary)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xl) {
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
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
        .sheet(isPresented: $showingManageCategories) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(viewModel)
        }
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Tags")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if !tags.isEmpty {
                    Text("\(tags.count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.appPrimary.opacity(0.15)))
                        .transition(.scale.combined(with: .opacity))
                }
            }

            TagInputField(
                tags: $tags,
                suggestionStats: viewModel.tagStats
            )
        }
        .animation(Theme.Motion.snappy, value: tags.count)
    }

    // MARK: - Payment method
    //
    // Horizontally-scrolling pill row, same shape language as the category
    // picker so the form reads as one connected pattern. We deliberately
    // make this **free for everyone** — collecting the data clean is what
    // makes the Pro "Payment Methods" donut on Statistics light up the
    // moment a user upgrades. Gating the picker would create dirty data.
    //
    // Tapping the active pill clears the choice (back to "Not set"),
    // matching the behaviour of every other deselect-by-tap-again interaction
    // in this form. Long-form names ("Bank Transfer") use a constrained
    // width with `.lineLimit(1)` so the row never wraps.

    private var paymentMethodField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Payment")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if let method = paymentMethod {
                    HStack(spacing: 4) {
                        Image(systemName: method.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(method.shortLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(method.color)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(method.color.opacity(0.15)))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm + 2) {
                    paymentMethodPill(nil)
                    ForEach(PaymentMethod.allCases) { method in
                        paymentMethodPill(method)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .animation(Theme.Motion.snappy, value: paymentMethod)
    }

    @ViewBuilder
    private func paymentMethodPill(_ method: PaymentMethod?) -> some View {
        let isSelected: Bool = (method == paymentMethod)
        let label = method?.shortLabel ?? "None"
        let icon = method?.icon ?? "minus.circle"
        // "None" pill stays neutral so it never looks like a competing choice.
        let accent: Color = method?.color ?? .secondary

        Button {
            HapticManager.shared.lightTap()
            withAnimation(Theme.Motion.snappy) {
                if isSelected {
                    paymentMethod = nil
                } else {
                    paymentMethod = method
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : accent)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                Capsule()
                    .fill(isSelected ? accent : accent.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .stroke(accent.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method?.displayName ?? "No payment method")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

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

            TextField("Add details about this expense...", text: $notes, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .focused($focusedField, equals: .notes)
                .lineLimit(3, reservesSpace: true)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: focusedField == .notes)
                .contentShape(Rectangle())
                .onTapGesture {
                    showingKeyboard = true
                    focusedField = .notes
                }
        }
    }

    // MARK: - Receipt Section (Pro)

    /// "Receipt" section. Two states:
    ///   1. **Empty** → shows a CTA card with "Scan" and "Library" buttons.
    ///      Free users see a Pro lock badge; tapping any button opens the
    ///      paywall instead of triggering the picker.
    ///   2. **Attached** → shows a small thumbnail row with "View",
    ///      "Replace", and "Remove" actions. Removal is always allowed
    ///      regardless of Pro state — that's user-owned data.
    private var receiptField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Receipt")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if !proManager.isPro {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.4)
                    }
                    .foregroundColor(Color.appPrimary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.appPrimary.opacity(0.13)))
                }
            }

            if receiptImagePath != nil {
                receiptAttachedCard
            } else {
                receiptEmptyCard
            }

            if let message = receiptErrorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.Motion.snappy, value: receiptImagePath)
        .animation(Theme.Motion.snappy, value: receiptErrorMessage)
    }

    /// Empty state — invitation to scan or pick.
    private var receiptEmptyCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.appPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attach a receipt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    // Receipts ride along with `.cashlens-archive`
                    // exports, so the cross-device story is honest:
                    // back up via Settings → Export → Full Archive,
                    // restore on the new device. iCloud auto-sync is
                    // still on the v2.1 roadmap.
                    Text("Saved to your CashLens archive — back up & restore anywhere.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Theme.Spacing.md) {
                receiptActionButton(
                    title: "Scan",
                    systemImage: "camera.viewfinder",
                    isPrimary: true,
                    isDisabled: !DocumentScannerView.isSupported,
                    action: { handleScanTapped() }
                )

                if proManager.isPro {
                    // Real PhotosPicker — no Pro gate, the user is Pro.
                    PhotosPicker(
                        selection: $pickedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        receiptActionButtonContent(
                            title: "Library",
                            systemImage: "photo.on.rectangle",
                            isPrimary: false,
                            isDisabled: false
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    // Stub button that opens the paywall instead of the picker.
                    receiptActionButton(
                        title: "Library",
                        systemImage: "photo.on.rectangle",
                        isPrimary: false,
                        isDisabled: false,
                        action: { handleLibraryTapped() }
                    )
                }
            }

            if isProcessingReceipt {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing receipt…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    /// Attached state — shows a thumbnail with quick actions.
    private var receiptAttachedCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Thumbnail. Tappable → opens the full-screen viewer.
            Button {
                HapticManager.shared.lightTap()
                showingReceiptViewer = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 56, height: 72)
                    if let img = receiptImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View attached receipt")

            VStack(alignment: .leading, spacing: 4) {
                Text("Receipt attached")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Tap to view full size")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 14) {
                    if proManager.isPro {
                        // Re-use PhotosPicker for the Replace action so the
                        // user can swap to a library image in one tap.
                        PhotosPicker(
                            selection: $pickedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.appPrimary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        HapticManager.shared.warning()
                        removeAttachedReceipt()
                    } label: {
                        Label("Remove", systemImage: "xmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    /// Real `Button` variant — used for everything except the Library
    /// action when the user is Pro (that one needs to be a real
    /// `PhotosPicker` so iOS actually presents the library).
    @ViewBuilder
    private func receiptActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            receiptActionButtonContent(
                title: title,
                systemImage: systemImage,
                isPrimary: isPrimary,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    /// Visual content shared by the `Button` and `PhotosPicker` variants
    /// so the row stays pixel-identical regardless of which control it
    /// renders for the current user state.
    @ViewBuilder
    private func receiptActionButtonContent(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundColor(isDisabled ? .secondary : (isPrimary ? .white : Color.appPrimary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            Capsule()
                .fill(isPrimary ? Color.appPrimary : Color.appPrimary.opacity(0.13))
                .opacity(isDisabled ? 0.4 : 1)
        )
        .overlay(
            Capsule()
                .stroke(Color.appPrimary.opacity(isPrimary ? 0 : 0.25), lineWidth: 1)
        )
    }

    // MARK: - Receipt actions

    private func handleScanTapped() {
        HapticManager.shared.lightTap()
        guard proManager.isPro else {
            showingReceiptPaywall = true
            return
        }
        guard DocumentScannerView.isSupported else {
            // Quietly fall through. Not surfacing an alert because (a)
            // the scanner button is also disabled visually in this
            // state, and (b) a future Mac Catalyst run might enter
            // here. The library path still works.
            return
        }
        showingScanner = true
    }

    private func handleLibraryTapped() {
        HapticManager.shared.lightTap()
        // Only reachable for non-Pro users — Pro path uses a real
        // `PhotosPicker` directly, no intermediate handler.
        showingReceiptPaywall = true
    }

    /// Persist a freshly captured `UIImage` to disk and update form
    /// state. Replaces any previously-attached (but not yet committed)
    /// receipt — the original baseline is preserved separately so the
    /// save path can clean up the row's pre-edit file.
    private func attachReceipt(image: UIImage) {
        // Capture any in-flight (added during this session, not yet
        // saved) attachment so we can clean it up after the new file
        // lands. We only delete files that aren't the pre-edit
        // baseline — that one is owned by the caller until save.
        let priorInSession = receiptImagePath != originalReceiptImagePath ? receiptImagePath : nil

        withAnimation(Theme.Motion.snappy) {
            isProcessingReceipt = true
            receiptErrorMessage = nil
        }

        Task.detached(priority: .userInitiated) {
            do {
                let filename = try ReceiptStorage.save(image)
                await MainActor.run {
                    if let prior = priorInSession {
                        ReceiptStorage.delete(filename: prior)
                    }
                    withAnimation(Theme.Motion.snappy) {
                        self.receiptImage = image
                        self.receiptImagePath = filename
                        self.isProcessingReceipt = false
                    }
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    withAnimation(Theme.Motion.snappy) {
                        self.isProcessingReceipt = false
                        self.receiptErrorMessage = error.localizedDescription
                    }
                    HapticManager.shared.warning()
                    // Auto-clear so the message doesn't linger forever.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        if self.receiptErrorMessage == error.localizedDescription {
                            withAnimation(Theme.Motion.snappy) {
                                self.receiptErrorMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }

    /// Remove a receipt before saving the form. If the file was added
    /// during this session (not the pre-edit baseline), delete it from
    /// disk immediately. The pre-edit baseline waits for the save path
    /// to confirm the user actually committed the removal — otherwise
    /// dismissing without saving would lose the original.
    private func removeAttachedReceipt() {
        if let current = receiptImagePath, current != originalReceiptImagePath {
            ReceiptStorage.delete(filename: current)
        }
        withAnimation(Theme.Motion.snappy) {
            receiptImagePath = nil
            receiptImage = nil
        }
    }

    /// Called by the close button. Discards any session-added receipt
    /// file the user never committed by saving. The pre-edit baseline
    /// is left alone — that file still belongs to the un-edited row.
    private func cleanupUnsavedReceipt() {
        if let current = receiptImagePath, current != originalReceiptImagePath {
            ReceiptStorage.delete(filename: current)
        }
    }

    // Computed property to check if form is valid
    private var isFormValid: Bool {
        if isEditing {
            // For editing, we only need a non-empty title and a valid amount
            let parsedAmount = viewModel.parseAmount(amount)
            // In edit mode, don't require the amount to be positive, just valid
            return !title.isEmpty && parsedAmount != nil
        } else {
            // For new expenses, we need a non-empty title and a positive amount
            return !title.isEmpty && 
                   !amount.isEmpty && 
                   (viewModel.parseAmount(amount) ?? 0) > 0
        }
    }
    
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
                        Text(isEditing ? "Update Expense" : "Add Expense")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isFormValid ? Color.appPrimary : Color.gray.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(
                    color: isFormValid ? Color.appPrimary.opacity(0.3) : Color.gray.opacity(0.18),
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }
            .disabled(!isFormValid || isSaving)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
            .background(Color(.systemGroupedBackground))
        }
    }

    private func handleSaveTap() {
        guard let amountValue = viewModel.parseAmount(amount) else { return }
        pendingAmountValue = amountValue

        if let onSave = onSave {
            isSaving = true
            HapticManager.shared.mediumTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HapticManager.shared.success()
            }

            // If the user removed or replaced the receipt during this
            // edit session, delete the original file from disk now so
            // we don't leak it. The CRUD layer also runs an orphan
            // sweep on foreground, so this is belt-and-braces — but
            // the immediate cleanup keeps the user's storage tidy
            // between sessions.
            if let original = originalReceiptImagePath, original != receiptImagePath {
                ReceiptStorage.delete(filename: original)
            }

            onSave(
                title,
                amountValue,
                date,
                selectedCategory,
                selectedCategory == .custom ? selectedCustomCategoryId : nil,
                notes.isEmpty ? nil : notes,
                tags.isEmpty ? nil : tags,
                isRefund,
                paymentMethod,
                receiptImagePath
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismiss()
            }
        } else {
            if isPotentialDuplicate(amountValue: amountValue) {
                showingDuplicateConfirmation = true
            } else {
                isSaving = true
                addExpense()
            }
        }
    }
    
    // MARK: - Helper Views
    
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
                    .stroke(selectedCategory == category ? 
                           Color.forCategory(category.color).opacity(0.9) : 
                           Color.clear, 
                           lineWidth: 3)
            )
            .shadow(color: selectedCategory == category ? 
                   Color.forCategory(category.color).opacity(0.3) : 
                   Color.clear, 
                   radius: 4, x: 0, y: 0)
            
            Text(category.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(selectedCategory == category ? Color.forCategory(category.color) : .secondary)
        }
        .onTapGesture {
            selectedCategory = category
            if category != .custom {
                selectedCustomCategoryId = nil
            }
            HapticManager.shared.lightTap()
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
            selectedCategory = .custom
            selectedCustomCategoryId = category.id
            HapticManager.shared.lightTap()
        }
    }
    
    // MARK: - Actions
    
    private func addExpense() {
        guard let amountValue = viewModel.parseAmount(amount) else { return }
        
        // Enhanced haptic feedback sequence
        HapticManager.shared.mediumTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticManager.shared.success()
        }
        
        // Create new expense
        let newExpense = Expense(
            title: title,
            amount: amountValue,
            currency: viewModel.selectedCurrency,
            date: date,
            category: selectedCategory,
            notes: notes.isEmpty ? nil : notes,
            customCategoryId: selectedCategory == .custom ? selectedCustomCategoryId : nil,
            tags: tags.isEmpty ? nil : tags,
            isRefund: isRefund,
            paymentMethod: paymentMethod,
            receiptImagePath: receiptImagePath
        )
        
        // Add to view model
        viewModel.addExpense(newExpense)
        
        // Clear draft when expense is successfully added
        clearDraft()
        
        // Dismiss the view
        dismiss()
    }
    
    private func isPotentialDuplicate(amountValue: Double) -> Bool {
        // Only for new expenses; edits should not be blocked.
        guard !isEditing else { return false }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        
        let window: TimeInterval = 5 * 60
        let targetDate = date
        
        return viewModel.expenses.contains { existing in
            let existingTitle = existing.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard existingTitle.caseInsensitiveCompare(trimmedTitle) == .orderedSame else { return false }
            guard abs(existing.amount - amountValue) < 0.0001 else { return false }
            return abs(existing.date.timeIntervalSince(targetDate)) <= window
        }
    }
    
    private func recentTitles(limit: Int = 12) -> [String] {
        // PERF: `viewModel.expenses` is already sorted by date desc by
        // `loadExpenses()`'s `NSSortDescriptor`, so the explicit
        // `.sorted` we used to do here was redundant O(N log N) work
        // on every typed character. We now scan in iteration order and
        // bail as soon as we have `limit` unique titles, which makes
        // this O(k × avg-distinct-density) instead of O(N log N).
        var seen = Set<String>()
        var result: [String] = []
        for expense in viewModel.expenses {
            let trimmed = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
            if result.count >= limit { break }
        }
        return result
    }
    
    private func filteredTitleSuggestions() -> [String] {
        let input = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = recentTitles()
        guard !input.isEmpty else { return [] }
        
        let lower = input.lowercased()
        return Array(all.filter { $0.lowercased().contains(lower) }.prefix(5))
    }
    
    // MARK: - Draft Management
    
    @State private var draftSaveTimer: Timer?
    
    private func saveDraftWithDelay() {
        // Debounce the save operation to avoid excessive UserDefaults writes
        draftSaveTimer?.invalidate()
        draftSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            saveDraft()
        }
    }
    
    private func saveDraft() {
        // Only save draft if there's meaningful content and it's a new expense
        guard !isEditing && (!title.isEmpty || !amount.isEmpty || !notes.isEmpty || !tags.isEmpty) else {
            return
        }

        let draft = ExpenseDraft(
            title: title,
            amount: amount,
            date: date,
            selectedCategory: selectedCategory,
            selectedCustomCategoryId: selectedCustomCategoryId,
            notes: notes,
            tags: tags,
            isRefund: isRefund,
            paymentMethod: paymentMethod
        )
        
        if let encoded = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(encoded, forKey: draftKey)
        }
    }
    
    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        draftSaveTimer?.invalidate()
    }
    
    private func hasDraft() -> Bool {
        return UserDefaults.standard.data(forKey: draftKey) != nil
    }

    /// Load (or reload) the in-form receipt preview when the attached
    /// filename changes.
    ///
    /// PERF: `.task` on a SwiftUI view runs on the **main actor**, so
    /// directly calling `ReceiptStorage.loadImage` (which does sync file
    /// IO + JPEG decode via `UIImage(contentsOfFile:)`) was blocking the
    /// main thread right as the sheet finished animating in — a visible
    /// hitch when editing any expense that had a receipt attached. We
    /// now explicitly hop to a detached background task for the decode
    /// and only return to the main actor to assign the result.
    @MainActor
    private func loadReceiptImage(for filename: String?) async {
        guard let filename else {
            receiptImage = nil
            return
        }
        // If we already have an image set (e.g. just attached this
        // session), don't bounce through disk — the in-memory copy is
        // the most recent.
        if receiptImage != nil { return }
        let loaded = await Task.detached(priority: .userInitiated) {
            ReceiptStorage.loadImage(filename: filename)
        }.value
        receiptImage = loaded
    }

    /// Decode the saved draft (if any) on a background task and apply it
    /// back on the main actor. Only meaningful for the "new expense"
    /// flow; editing always starts pre-populated and skips this entirely.
    ///
    /// Called from `.task` so the work happens after the sheet has been
    /// presented, not during `init`. The form renders empty for one
    /// frame and then populates, which lets the sheet spring play
    /// unhindered.
    private func restoreDraftIfPresent() {
        // Editing already has its initial values; nothing to do.
        if isEditing { return }
        // If the user has already started typing into the empty form
        // before the draft load lands, don't clobber their input.
        if !title.isEmpty || !amount.isEmpty || !notes.isEmpty { return }

        let key = UserDefaultsKeys.expenseDraft
        Task.detached(priority: .userInitiated) {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let draft = try? JSONDecoder().decode(ExpenseDraft.self, from: data) else {
                return
            }
            await MainActor.run {
                // Re-check the "is the user already typing?" guard on the
                // main actor — the user could have typed during the
                // round-trip.
                guard self.title.isEmpty, self.amount.isEmpty, self.notes.isEmpty else { return }
                self.title = draft.title
                self.amount = draft.amount
                self.date = draft.date
                self.selectedCategory = draft.selectedCategory
                self.selectedCustomCategoryId = draft.selectedCustomCategoryId
                self.notes = draft.notes
                self.tags = draft.tags ?? []
                self.isRefund = draft.isRefund ?? false
                self.paymentMethod = draft.resolvedPaymentMethod
                let hasContent =
                    !draft.title.isEmpty
                    || !draft.amount.isEmpty
                    || !draft.notes.isEmpty
                    || !(draft.tags?.isEmpty ?? true)
                if hasContent {
                    self.showingDraftRestored = true
                }
            }
        }
    }
    
    // MARK: - Delete Expense
    
    private func deleteExpense() {
        guard let id = expenseId else { return }
        
        // Use a safer approach that doesn't rely on array indices directly
        // This helps prevent "index out of range" errors
        viewModel.deleteExpenseById(id)
        
        // Haptic feedback for deletion
        HapticManager.shared.success()
        
        // Dismiss the view
        dismiss()
    }
}

struct AddExpenseView_Previews: PreviewProvider {
    static var previews: some View {
        AddExpenseView(viewModel: ExpenseViewModel())
    }
} 