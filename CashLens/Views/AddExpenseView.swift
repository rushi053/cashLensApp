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

    /// Drives the `.photosPicker(isPresented:)` modifier so we can
    /// surface the system photo library picker programmatically from
    /// the receipt source confirmation dialog. The legacy receipt
    /// field wraps a `PhotosPicker` button directly; the v3.2 compact
    /// row uses this state-driven path so a single tap on the row can
    /// offer both Scan and Library options via a confirmation dialog.
    @State private var showingPhotoLibrary: Bool = false

    /// Drives the receipt-source confirmation dialog. Opens when the
    /// user taps the Receipt row in the compact More section; lets
    /// them choose between camera scan and photo library.
    @State private var showingReceiptSourceDialog: Bool = false
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

    // MARK: - Receipt OCR state (Pro — inherits the capture gate)
    //
    // OCR runs only on images captured/attached in THIS session (never
    // on edit-mode loads of an existing receipt), entirely on-device
    // via `ReceiptOCRService`. It fails silently: manual entry is
    // never blocked, slowed, or overwritten.
    /// True while Vision is reading the freshly attached receipt.
    /// Drives a small unobtrusive "Reading receipt…" state.
    @State private var isScanningReceipt: Bool = false
    /// In-flight OCR task — cancelled if the user removes/replaces the
    /// receipt or dismisses the sheet mid-scan.
    @State private var receiptOCRTask: Task<Void, Never>? = nil
    /// True when the amount field was auto-filled from the receipt.
    /// Shows the "Filled from receipt · Undo" chip under the hero.
    @State private var amountFilledFromReceipt: Bool = false
    /// The exact string OCR wrote into `amount` — used to detect a
    /// manual edit (which quietly retires the chip; the value is the
    /// user's now).
    @State private var ocrFilledAmountString: String = ""
    /// Merchant name extracted from the receipt, offered as a title
    /// suggestion chip while the title is still empty. Never applied
    /// automatically.
    @State private var ocrMerchantSuggestion: String? = nil

    @State private var showingKeyboard: Bool
    @State private var showingManageCategories: Bool
    @State private var showingDatePicker: Bool

    /// Sheet binding for the slim Templates popover (header chip → sheet).
    /// The old "Quick Templates" panel at the top of the form was always
    /// visible and ate the first 100pt of vertical real estate; this
    /// moves the feature behind a one-tap chip so the entry surface stays
    /// focused on Amount + Title + Category.
    @State private var showingTemplatesSheet: Bool = false

    /// Sheet binding for the smart category picker (More tile → sheet).
    /// The "More" tile at the end of the smart category row opens this
    /// so users can pick from every category without a horizontal scroll.
    @State private var showingCategoryPicker: Bool = false

    /// Which secondary-field editor is currently being shown as a
    /// focused half-sheet. Only one at a time — sheets close before a
    /// new one opens, so the user never lands in a stacked-modal mess.
    /// `nil` when no sheet is open. Only Tags and Notes use this — Date
    /// and Payment are inline editors on the form itself; Receipt has
    /// its own dedicated capture flow (scanner / photo picker).
    @State private var activeFieldEditor: FieldEditor? = nil

    /// Whether the "More options" disclosure under Date + Payment is
    /// open. Closed by default; auto-opened on edit if any of the
    /// fields it houses (Tags / Note / Receipt) are populated so the
    /// user doesn't have to hunt for what they already added.
    @State private var moreOptionsExpanded: Bool = false

    /// Identifier for the focused half-sheet that pops up when the user
    /// taps the Tags or Note row. Date and Payment are edited inline
    /// (no sheet) so they don't need an entry here.
    enum FieldEditor: String, Identifiable {
        case tags
        case notes
        var id: String { rawValue }
    }

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

    /// Memoized result of `computeSortedCategoryEntries()` — see that
    /// function's PERF note. Refreshed by the hooks on `smartCategoryRow`.
    @State private var categoryEntries: [CategoryEntry] = []
    
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
        // Strip any currency symbols / grouping characters from the
        // incoming amount string. Most call sites pass
        // `viewModel.formattedAmount(expense.amount)` which returns a
        // formatted "₹12.00"-style display string; storing that
        // directly would cause the hero amount row to render the
        // currency symbol twice (once as the leading badge, once
        // baked into the digit text). Reducing to "12.00" keeps the
        // input field plain and lets the hero own the formatting.
        _amount = State(initialValue: Self.sanitizeIncomingAmount(amount))
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

        _activeFieldEditor = State(initialValue: nil)

        // Auto-open the More section whenever an editing session lands
        // on a row that already has a tag, note, or receipt attached —
        // hiding populated fields behind a disclosure would force the
        // user to hunt for what they already entered.
        let hasMoreContent =
            !tags.isEmpty
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || receiptImagePath != nil
        _moreOptionsExpanded = State(initialValue: hasMoreContent)
    }

    /// Strip currency symbols, grouping characters and any other
    /// non-numeric noise from an incoming amount string. Keeps digits,
    /// a single decimal separator (`.` or `,`), and a leading minus.
    /// Falls back to the original string if the result is empty (so
    /// "₹" alone doesn't reduce to "").
    private static func sanitizeIncomingAmount(_ raw: String) -> String {
        let allowed = Set<Character>("0123456789.,-")
        let cleaned = String(raw.filter { allowed.contains($0) })
        return cleaned.isEmpty ? raw : cleaned
    }

    var body: some View {
        ZStack {
            // v2: page is the same systemBackground as the rest of
            // the app so the elevated white field cards lift cleanly
            // off the page (vs the prior light grey form bg, which
            // muddied the lift and didn't match Today/Activity).
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
            PaywallView(context: .receipts)
        }
        // Receipt source picker + programmatic photo library trigger,
        // grouped in a single ViewModifier so the body's modifier
        // chain stays within Swift's type-check budget.
        .modifier(
            ReceiptSourcePickerModifier(
                showingDialog: $showingReceiptSourceDialog,
                showingScanner: $showingScanner,
                showingPhotoLibrary: $showingPhotoLibrary,
                pickedPhotoItem: $pickedPhotoItem
            )
        )
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
        .sheet(isPresented: $showingTemplatesSheet) {
            templatesSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Focused half-sheet for editing one secondary field at a time.
        // Routes to the right editor based on `activeFieldEditor`. Each
        // editor reuses its existing field component, so the in-sheet
        // experience matches what users saw inline in v2.
        .sheet(item: $activeFieldEditor) { editor in
            fieldEditorSheet(editor)
                .presentationDetents(detents(for: editor))
                .presentationDragIndicator(.visible)
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

    /// v3 sub-field eyebrow font — smaller and lighter than v2's
    /// 18pt rounded bold. The inner fields all sit inside the
    /// Details expander now, so the labels need to read as "section
    /// markers" rather than competing with the hero amount tile.
    private static let fieldLabelFont = Font.system(size: 14, weight: .semibold, design: .rounded)

    // MARK: - v3 Hero Amount Tile
    //
    // Single biggest visual surface in the form. The amount IS the
    // expense — everything else is metadata — so it gets ~25% of the
    // visible canvas with a huge monospaced rounded display, a small
    // currency badge to the left, and a single corner toggle for the
    // refund state. Tap anywhere on the tile to focus the keyboard.

    // v3.4 hero amount — centered, type-on-page, with a "wallet"-style
    // payment selector pill sitting just above the eyebrow.
    //
    // Layout flow:
    //     [💳 Credit ▾]                ← payment selector pill
    //     ENTER AMOUNT     [↩ Refund]   ← eyebrow row + refund toggle
    //     ₹56.00                        ← 72pt hero value
    //
    // The payment pill replaces the prior inline payment row in
    // `secondaryFieldsList`. It opens a native Menu listing every
    // payment method, plus a "No payment method" affordance to
    // clear the choice. Default state reads "Add payment".

    private var heroAmountTile: some View {
        VStack(spacing: Theme.Spacing.lg) {
            paymentSelectorPill
            heroAmountEyebrow
            heroAmountValueRow

            if amountFilledFromReceipt {
                filledFromReceiptChip
            }

            if isRefund {
                Text("Subtracted from your totals")
                    .font(.caption)
                    .foregroundColor(.green.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xxl)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingKeyboard = true
            focusedField = .amount
        }
        .animation(Theme.Motion.snappy, value: isRefund)
        .animation(Theme.Motion.snappy, value: paymentMethod)
        .animation(Theme.Motion.snappy, value: focusedField == .amount)
        .animation(Theme.Motion.snappy, value: amountFilledFromReceipt)
        // A manual edit takes ownership of the value — the chip retires
        // quietly (undo would now discard the USER's number, not ours).
        .onChange(of: amount) { _, newValue in
            if amountFilledFromReceipt && newValue != ocrFilledAmountString {
                amountFilledFromReceipt = false
            }
        }
    }

    /// Subtle indicator that the hero amount came from receipt OCR,
    /// with a one-tap undo. Disappears on manual edit.
    private var filledFromReceiptChip: some View {
        Button(action: undoReceiptAmountFill) {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 10, weight: .semibold))
                Text("Filled from receipt")
                    .font(.system(size: 11, weight: .semibold))
                Text("·")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.5)
                Text("Undo")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.appPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.appPrimary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel("Amount filled from receipt. Tap to undo.")
    }

    /// Wallet-style centered pill that opens a native Menu listing
    /// every payment method. Shows the active method's coloured icon
    /// + name + chevron when set; reads "Add payment" when not.
    private var paymentSelectorPill: some View {
        Menu {
            Button {
                HapticManager.shared.lightTap()
                paymentMethod = nil
            } label: {
                if paymentMethod == nil {
                    Label("No payment method", systemImage: "checkmark")
                } else {
                    Text("No payment method")
                }
            }

            Divider()

            ForEach(PaymentMethod.allCases) { method in
                Button {
                    HapticManager.shared.lightTap()
                    paymentMethod = method
                } label: {
                    if paymentMethod == method {
                        Label(method.displayName, systemImage: "checkmark")
                    } else {
                        Label(method.displayName, systemImage: method.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: paymentMethod?.icon ?? "wallet.pass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(paymentMethod?.color ?? .secondary)
                Text(paymentMethod?.displayName ?? "Add payment")
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
        .accessibilityLabel("Payment method: \(paymentMethod?.displayName ?? "None"). Tap to change.")
    }

    /// Eyebrow row: centered uppercased label with the refund toggle
    /// right-aligned. Uses a ZStack so the label stays optically
    /// centered regardless of how wide the refund pill grows.
    private var heroAmountEyebrow: some View {
        ZStack {
            Text(isRefund ? "REFUND AMOUNT" : "ENTER AMOUNT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isRefund ? .green : .secondary)
                .tracking(1.4)
                .contentTransition(.opacity)

            HStack {
                Spacer()
                refundCornerToggle
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    /// The big centered "₹45" row.
    ///
    /// **Optical centering trick**: an inline `[symbol] [digit]` HStack
    /// is mathematically centered, but visually feels off-centre because
    /// the digit (huge) dominates the visual mass and the symbol (small)
    /// pulls the centre to the left. The fix is a **ghost mirror** — a
    /// hidden copy of the symbol on the trailing side of the digit, so
    /// the HStack reads `[symbol] [digit] [ghost symbol]`. The digit
    /// now sits perfectly between two equal-weight anchors and lands
    /// dead-centre regardless of symbol shape ($/₹/€/kr.).
    ///
    /// **Hidden input field**: the visible display is just `Text` so the
    /// centering is deterministic. A 0-opacity `TextField` overlay
    /// captures keystrokes — invisible but fully focusable — so the
    /// numeric keyboard still drives the underlying `amount` binding.
    /// Cash App, Splitwise and most modern currency apps use this same
    /// pattern; users don't notice the missing cursor on a decimal-pad
    /// field.
    private var heroAmountValueRow: some View {
        ZStack {
            // 0-opacity input field — drives the keyboard, invisible.
            TextField("", text: $amount)
                .focused($focusedField, equals: .amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .opacity(0.001)
                .frame(maxWidth: .infinity, minHeight: 80)
                .allowsHitTesting(false)

            // Visible display — symbol + digit + ghost-symbol mirror.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(isRefund ? .green : .appPrimary)

                Text(displayAmount)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(isRefund ? .green : displayAmount == "0" ? .primary.opacity(0.25) : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .contentTransition(.numericText())

                // Ghost mirror — same font/size as the leading currency
                // symbol but invisible. Optically centres the digit.
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.clear)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Display string for the hero amount. Empty input reads as "0" so
    /// the hero never collapses to nothing; the dim colour treatment on
    /// "0" in the display tells the user it's a placeholder, not data.
    private var displayAmount: String {
        amount.isEmpty ? "0" : amount
    }

    /// Tiny corner toggle that flips the entry between expense and
    /// refund. Subtle by design — most users will never tap this, but
    /// power users who track returns can flip an entry in two taps.
    private var refundCornerToggle: some View {
        Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                isRefund.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isRefund ? "arrow.uturn.backward.circle.fill" : "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .bold))
                Text(isRefund ? "Refund on" : "Refund")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isRefund ? .green : .secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isRefund ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(isRefund ? Color.green.opacity(0.30) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRefund ? "Refund mode on. Tap to mark as expense." : "Mark as refund")
    }

    // MARK: - v3 Compact Title Field
    //
    // No chunky 18pt label — just a placeholder-driven input. Smart
    // title suggestions and the smart category suggestion (when
    // applicable) appear directly under the field as compact chips.

    private var compactTitleField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TextField("What was it for?", text: $title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: focusedField == .title)
                .contentShape(Rectangle())
                .onTapGesture {
                    showingKeyboard = true
                    focusedField = .title
                }

            // Merchant name read off the attached receipt — offered as
            // a suggestion (never auto-applied) while the title is
            // still empty.
            if let merchant = ocrMerchantSuggestion,
               title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ocrMerchantSuggestionChip(merchant)
            }

            // Title autocompletion suggestions — only when the user is
            // typing and the suggestion source has matches.
            if !isEditing,
               focusedField == .title,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleSuggestions
            }

            // Smart category suggestion lives here too (one card down
            // from the title that triggered it) so the cause and effect
            // sit visually adjacent.
            suggestedCategoryRow
        }
        .animation(Theme.Motion.snappy, value: ocrMerchantSuggestion)
    }

    /// One-tap merchant suggestion sourced from receipt OCR. Applies
    /// on tap; dismissible via the small x so it never nags.
    private func ocrMerchantSuggestionChip(_ merchant: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                HapticManager.shared.lightTap()
                withAnimation(Theme.Motion.snappy) {
                    title = merchant
                    ocrMerchantSuggestion = nil
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                    Text("From receipt:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(merchant)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.appPrimary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use merchant name \(merchant) from receipt as title")

            Button {
                withAnimation(Theme.Motion.snappy) {
                    ocrMerchantSuggestion = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss merchant suggestion")

            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - v3.2 Smart Category Row
    //
    // Single-row horizontal scroll sorted **by how often the user
    // actually picks each category**, with a Browse tile at the end
    // that opens the full picker as a sheet. Trades the 4-col grid's
    // vertical footprint (~150pt of always-on space) for a compact
    // ~100pt single row — the user can flick to see more, and the
    // most-used ones are always within the first viewport.

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
                    ForEach(categoryEntries) { entry in
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
        // PERF: recompute the memoized entries only when the category
        // set can actually have changed — never per keystroke.
        .onAppear { categoryEntries = computeSortedCategoryEntries() }
        .onChange(of: categoryViewModel.customCategories) { _, _ in
            categoryEntries = computeSortedCategoryEntries()
        }
        .onChange(of: showingManageCategories) { _, isShowing in
            // Catches deleted/restored *default* categories, which live
            // in UserDefaults and aren't covered by the FRC-synced
            // `customCategories` observer above.
            if !isShowing { categoryEntries = computeSortedCategoryEntries() }
        }
        .sheet(isPresented: $showingManageCategories) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingCategoryPicker) {
            categoryPickerSheet
        }
    }

    /// Heterogeneous category entry — default or custom — used to drive
    /// a single sorted scroll row.
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

    /// Categories ordered by recent usage frequency (descending).
    /// The order is a **stable function of the user's history alone**
    /// — picking a category does NOT reorder the row, because moving
    /// the just-tapped tile into the leading slot feels jumpy and
    /// breaks muscle memory across sessions. Selection state is
    /// communicated by highlight only; position stays put.
    ///
    /// PERF: memoized into `categoryEntries` (@State) rather than being
    /// a computed property. As a computed property it re-ran the tally +
    /// UserDefaults read + sort on **every** body evaluation — i.e. every
    /// keystroke in the title/amount fields and every viewModel publish.
    /// Usage frequency doesn't need keystroke freshness; see the
    /// recompute hooks on `smartCategoryRow`.
    private func computeSortedCategoryEntries() -> [CategoryEntry] {
        // Tally usage over the most recent 500 expenses — enough to
        // give a good signal without scanning the whole history. The
        // scan is O(N) but bounded; for typical users this is microseconds.
        // `expenses` is sorted date-descending (newest first), so
        // `prefix` — not `suffix` — takes the most recent rows.
        let recent = viewModel.expenses.count > 500
            ? Array(viewModel.expenses.prefix(500))
            : viewModel.expenses

        var counts: [String: Int] = [:]
        for e in recent {
            if e.category == .custom, let id = e.customCategoryId {
                counts["c_\(id.uuidString)", default: 0] += 1
            } else {
                counts["d_\(e.category.rawValue)", default: 0] += 1
            }
        }

        var entries: [CategoryEntry] = []
        for c in viewModel.getAvailableDefaultCategories() {
            entries.append(.defaultCat(c))
        }
        for c in categoryViewModel.customCategories {
            entries.append(.customCat(c))
        }

        // Sort by count desc; stable for ties so the underlying
        // declaration order is preserved among equally-used entries.
        return entries.sorted { a, b in
            (counts[a.id] ?? 0) > (counts[b.id] ?? 0)
        }
    }

    /// Default-category cell in the grid. Same visual as
    /// `categoryButton` but width-flexible (no hard 76pt frame) so the
    /// grid columns can equalize.
    private func categoryGridCell(_ category: Expense.Category) -> some View {
        let isSelected = selectedCategory == category
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

    /// Custom-category cell in the grid.
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

    /// Last tile in the grid — opens the full categories sheet. Keeps
    /// every category one tap away even when the grid only has room
    /// for the top 7.
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
                            Circle().stroke(Color.appPrimary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
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

    /// Full categories picker presented as a half-sheet. Lets the user
    /// pick from every default + custom category in a tidy grid,
    /// dismisses on selection, and links out to Manage Categories for
    /// edits.
    private var categoryPickerSheet: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm + 2, alignment: .top),
                    count: 4
                )

                LazyVGrid(columns: columns, alignment: .center, spacing: Theme.Spacing.lg) {
                    ForEach(viewModel.getAvailableDefaultCategories(), id: \.self) { category in
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingCategoryPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showingManageCategories = true
                        }
                    } label: {
                        Text("Manage")
                            .fontWeight(.semibold)
                            .foregroundColor(.appPrimary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - v3.4 Secondary Fields
    //
    // Tier 1 (always visible, inline editable):
    //   · Date     → Today / Yesterday / Pick (chip row)
    // Tier 2 (behind "More options" disclosure):
    //   · Tags     → opens focused sheet
    //   · Note     → opens focused sheet
    //   · Receipt  → opens scan / library picker
    //
    // v3.4 moved Payment up to the hero block as a centered "wallet"-
    // style selector pill. Keeping it inline here too would have been
    // redundant, so the inline 4-pill row was removed.

    private var secondaryFieldsList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxl) {
            inlineDateField
            moreOptionsSection
        }
        .animation(Theme.Motion.snappy, value: tags.count)
        .animation(Theme.Motion.snappy, value: date)
        .animation(Theme.Motion.snappy, value: notes)
        .animation(Theme.Motion.snappy, value: moreOptionsExpanded)
    }

    // MARK: Inline Date

    /// Compact date editor — a slim eyebrow label and a row of three
    /// chips: Today, Yesterday, and a Pick chip that shows the current
    /// date (when it isn't today/yesterday) or the calendar disclosure.
    /// One-tap edit for the 90% case; opens the wheel picker for any
    /// other date.
    private var inlineDateField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Date")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 2)

            HStack(spacing: Theme.Spacing.sm) {
                dateChip(
                    title: "Today",
                    selected: Calendar.current.isDateInToday(date)
                ) {
                    HapticManager.shared.selectionChanged()
                    date = Date()
                }

                dateChip(
                    title: "Yesterday",
                    selected: Calendar.current.isDateInYesterday(date)
                ) {
                    HapticManager.shared.selectionChanged()
                    date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                }

                pickDateChip
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            VStack {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Button("Done") {
                    showingDatePicker = false
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.appPrimary)
                .padding()
            }
            .presentationDetents([.height(360)])
            .presentationBackground(Color(uiColor: .systemBackground))
        }
    }

    /// A Today / Yesterday quick-pick pill.
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

    /// The third chip — either "Pick a date" (when date is today or
    /// yesterday) or the actual date (when it's anything else, so the
    /// user can see at a glance what they previously chose). Tapping
    /// always opens the wheel picker.
    private var pickDateChip: some View {
        let isCustom = !Calendar.current.isDateInToday(date)
            && !Calendar.current.isDateInYesterday(date)

        return Button {
            HapticManager.shared.lightTap()
            focusedField = nil
            showingDatePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text(isCustom ? pickChipDateString(date) : "Pick a date")
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
        .accessibilityLabel(isCustom ? "Custom date \(pickChipDateString(date)). Tap to change." : "Pick a date")
    }

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func pickChipDateString(_ d: Date) -> String {
        Self.monthDayFormatter.string(from: d)
    }

    // MARK: Inline Payment
    //
    // Compact single-row picker. Renders the 4 most-common methods
    // inline as slim chip pills (Cash · Credit · Debit · UPI) plus a
    // "More" overflow that opens a system Menu listing the rest
    // (Bank · Wallet · Other). When the user picks a method from the
    // overflow that isn't one of the 4 main, we still show it as a
    // selected confirmation chip next to the label so they can see
    // their pick without re-opening the menu.

    /// The 3 payment methods shown inline. Cash / Credit / Debit are
    /// the universal trio — every country in every market uses some
    /// combination of these. UPI, Bank, Wallet, Other are region- or
    /// preference-specific so they live behind the "More" menu — keeps
    /// the inline row compact and globally relevant.
    private static let mainPaymentMethods: [PaymentMethod] = [
        .cash, .creditCard, .debitCard,
    ]

    /// Methods that live behind the "More" menu — anything not in the
    /// main 4.
    private static let overflowPaymentMethods: [PaymentMethod] = PaymentMethod.allCases
        .filter { !mainPaymentMethods.contains($0) }

    private var inlinePaymentField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Payment")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                // When the user has picked a method from the overflow
                // menu (Bank / Wallet / Other), surface a small coloured
                // chip next to the label so they can see their pick
                // even when the "More" pill collapses the value.
                if let method = paymentMethod, !Self.mainPaymentMethods.contains(method) {
                    HStack(spacing: 3) {
                        Image(systemName: method.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(method.shortLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(method.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(method.color.opacity(0.14)))
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()
            }
            .padding(.horizontal, 2)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.mainPaymentMethods) { method in
                    compactPaymentPill(method)
                }
                paymentOverflowMenu
            }
        }
    }

    /// A slim, fluid-width pill for one of the main 4 payment methods.
    /// Compact (~28pt tall) so the row fits in one line on every device.
    private func compactPaymentPill(_ method: PaymentMethod) -> some View {
        let isSelected = (method == paymentMethod)

        return Button {
            HapticManager.shared.lightTap()
            withAnimation(Theme.Motion.snappy) {
                paymentMethod = isSelected ? nil : method
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: method.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(method.shortLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(isSelected ? Color.appPrimary : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// "More" overflow — a native Menu that lists the remaining
    /// methods (Bank, Wallet, Other) plus a "None" affordance so the
    /// user can clear their pick. Highlights with the mauve accent
    /// when an overflow method is currently selected.
    private var paymentOverflowMenu: some View {
        let isOverflowSelected = paymentMethod.map { !Self.mainPaymentMethods.contains($0) } ?? false

        return Menu {
            // "None" first so users can always reach the clear action.
            Button {
                HapticManager.shared.lightTap()
                withAnimation(Theme.Motion.snappy) { paymentMethod = nil }
            } label: {
                if paymentMethod == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }

            Divider()

            ForEach(Self.overflowPaymentMethods) { method in
                Button {
                    HapticManager.shared.lightTap()
                    withAnimation(Theme.Motion.snappy) { paymentMethod = method }
                } label: {
                    if paymentMethod == method {
                        Label(method.displayName, systemImage: "checkmark")
                    } else {
                        Label(method.displayName, systemImage: method.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(isOverflowSelected ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 7)
            .frame(minWidth: 54)
            .background(
                Capsule().fill(isOverflowSelected ? Color.appPrimary : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(isOverflowSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .accessibilityLabel("More payment methods")
    }

    // MARK: More options (collapsable)

    /// The disclosure that houses Tags / Note / Receipt. Closed by
    /// default for new entries; auto-opens for editing sessions where
    /// any of these fields are populated.
    private var moreOptionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            moreOptionsToggle

            if moreOptionsExpanded {
                VStack(spacing: 0) {
                    secondaryFieldRow(
                        icon: "tag",
                        label: "Tags",
                        value: tagsSummary,
                        isSet: !tags.isEmpty
                    ) {
                        activeFieldEditor = .tags
                    }

                    rowDivider

                    secondaryFieldRow(
                        icon: "text.alignleft",
                        label: "Note",
                        value: notesSummary,
                        isSet: !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        activeFieldEditor = .notes
                    }

                    rowDivider

                    receiptCompactRow
                }
                .cardSurface()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    /// Slim "More options" disclosure button. Shows a + when closed and
    /// a chevron when open; the label flips to "Less" when expanded so
    /// the affordance to close is obvious.
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
                Text(moreOptionsExpanded ? "Hide tags, note & receipt" : "Add tags, note or receipt")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                // Subtle summary chips on the closed state so the user
                // sees at a glance whether anything is set inside.
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

    /// Tiny icons showing which Tier-2 fields are populated when the
    /// More section is closed. Helps the user remember they already
    /// added a note without expanding.
    @ViewBuilder
    private var moreOptionsSummaryChips: some View {
        let hasTags = !tags.isEmpty
        let hasNote = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasReceipt = receiptImagePath != nil

        if hasTags || hasNote || hasReceipt {
            HStack(spacing: 6) {
                if hasTags {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                if hasNote {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11, weight: .bold))
                }
                if hasReceipt {
                    Image(systemName: "doc.text.image.fill")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundColor(.appPrimary)
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 52)
            .opacity(0.35)
    }

    /// One compact "settings-style" row for a secondary field.
    private func secondaryFieldRow(
        icon: String,
        label: String,
        value: String,
        isSet: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.shared.lightTap()
            focusedField = nil
            action()
        }) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSet ? .appPrimary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill((isSet ? Color.appPrimary : Color.secondary).opacity(0.12)))

                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer(minLength: Theme.Spacing.sm)

                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSet ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.tertiaryLabel)
            }
            .padding(.horizontal, Theme.Spacing.md + 2)
            .padding(.vertical, Theme.Spacing.md - 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Compact receipt row that lives inside `secondaryFieldsList`.
    /// When empty: a tappable "Scan or pick a receipt" prompt. When set:
    /// thumbnail + filename + tap-to-view, with a remove action.
    @ViewBuilder
    private var receiptCompactRow: some View {
        if receiptImagePath != nil {
            // Thumbnail row — reuse the same loading state /
            // viewer / removal hooks the legacy receiptField has.
            Button {
                HapticManager.shared.lightTap()
                if receiptImage != nil { showingReceiptViewer = true }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.appPrimary.opacity(0.10))
                            .frame(width: 36, height: 36)
                        if let img = receiptImage {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: "doc.text.image")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appPrimary)
                        }
                    }

                    Text("Receipt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer(minLength: Theme.Spacing.sm)

                    if isScanningReceipt {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Reading…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("View")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.appPrimary)
                    }

                    Button {
                        HapticManager.shared.warning()
                        removeAttachedReceipt()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.md + 2)
                .padding(.vertical, Theme.Spacing.md - 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // Empty state — opens the source picker (Scan or Library)
            // for Pro users; routes free users to the paywall.
            Button {
                HapticManager.shared.lightTap()
                focusedField = nil
                if proManager.isPro {
                    showingReceiptSourceDialog = true
                } else {
                    showingReceiptPaywall = true
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))

                    Text("Receipt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer(minLength: Theme.Spacing.sm)

                    if !proManager.isPro {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("PRO")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
                    } else {
                        Text("Add")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.tertiaryLabel)
                }
                .padding(.horizontal, Theme.Spacing.md + 2)
                .padding(.vertical, Theme.Spacing.md - 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Secondary field summary helpers

    private var dateSummary: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return Self.monthDayFormatter.string(from: date)
    }

    private var tagsSummary: String {
        if tags.isEmpty { return "Add" }
        if tags.count == 1 { return tags[0] }
        return "\(tags.count) tags"
    }

    private var notesSummary: String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Add" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Field editor sheets

    /// Detents for each editor sheet. Tags and Notes both want a
    /// `.medium` start so users can type without the keyboard fighting
    /// the sheet for space, with `.large` available when there's more
    /// content to manage.
    private func detents(for editor: FieldEditor) -> Set<PresentationDetent> {
        switch editor {
        case .tags: return [.medium, .large]
        case .notes: return [.medium, .large]
        }
    }

    /// Sheet body for a given editor. Reuses the existing field
    /// components inside a NavigationView so each editor gets its own
    /// title bar with a Done button. Closing the sheet via Done is
    /// always non-destructive — the underlying form state was already
    /// updated as the user typed.
    @ViewBuilder
    private func fieldEditorSheet(_ editor: FieldEditor) -> some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch editor {
                    case .tags:    tagsField
                    case .notes:   notesField
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(editorTitle(editor))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { activeFieldEditor = nil }
                        .fontWeight(.semibold)
                        .foregroundColor(.appPrimary)
                }
            }
        }
    }

    private func editorTitle(_ editor: FieldEditor) -> String {
        switch editor {
        case .tags: return "Tags"
        case .notes: return "Note"
        }
    }

    // MARK: - v3 Header Templates Chip
    //
    // Slim "Templates · 3" pill in the header trailing slot. Tapping
    // opens a small popover sheet listing all templates as bare rows;
    // tap a row to fill the form (same applyTemplate(_:) flow as the
    // old chip strip), long-press to delete.

    /// Main scrollable form content. Extracted from `body` so the body
    /// stays inside the Swift type-checker's reasonable-time budget.
    ///
    /// v3.4 spacing pass: bumped section spacing from `.xl` (20pt) to
    /// `.xxxl` (32pt) and added more padding around the hero block.
    /// The empty white below the More-options card on a typical form
    /// is now distributed as breathing room between every section,
    /// so each block reads as its own confident unit instead of a
    /// stacked list.
    private var formScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.xxxl) {
                if showingDraftRestored && !isEditing {
                    draftRestoredBanner
                }

                heroAmountTile
                compactTitleField
                smartCategoryRow
                secondaryFieldsList
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - v3.2 Polished Header
    //
    // Four helpers that build the redesigned header strip. The new
    // header takes ~12pt more vertical space than v3 in exchange for
    // a more "stately" first impression — the form opens with the
    // header looking deliberate rather than crammed against the safe
    // area. All icon buttons share a 36pt material circle so visual
    // weight stays balanced left ↔ right.

    /// Full header strip — extracted from `body` so the body's type
    /// inference stays inside the compiler's reasonable-time budget.
    ///
    /// **Centering**: laid out as a `ZStack` with the title pinned to
    /// the centre and the dismiss/trailing buttons overlaid on the
    /// edges. An HStack with Spacers would let the trailing pill
    /// ("Save preset" / "Templates 2") push the title leftwards
    /// whenever it grows wider than the 36pt dismiss button — the
    /// ZStack approach guarantees true centering regardless of how
    /// wide either side gets.
    private var headerStrip: some View {
        // Shared `SheetHeader` (Components/SheetHeader.swift) — the
        // stacked eyebrow-over-verb title this screen pioneered is
        // now the app-wide sheet header convention. Dismiss cleans
        // up any unsaved receipt and clears the draft for new
        // expenses before dismissing.
        SheetHeader(
            eyebrow: "Expense",
            title: isEditing ? "Editing" : "Add New",
            onClose: {
                if !isEditing { clearDraft() }
                cleanupUnsavedReceipt()
                dismiss()
            }
        ) {
            headerTrailingSlot
        }
        .animation(Theme.Motion.snappy, value: canSaveCurrentAsTemplate)
    }

    /// Trailing header slot — trash button when editing, otherwise
    /// either the Save-preset chip or the Templates chip depending on
    /// form state. Always renders a 36pt-wide placeholder when empty
    /// so the title stays optically centered.
    @ViewBuilder
    private var headerTrailingSlot: some View {
        if isEditing {
            Button {
                HapticManager.shared.lightTap()
                showingDeleteConfirmation = true
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
            .accessibilityLabel("Delete this expense")
        } else if canSaveCurrentAsTemplate {
            saveAsTemplateButton
        } else if !templateStore.templates.isEmpty {
            headerTemplatesChip
        } else {
            // Invisible placeholder keeps the title centered when
            // there's no trailing action.
            SheetHeaderSpacer()
        }
    }

    private var headerTemplatesChip: some View {
        Button {
            HapticManager.shared.lightTap()
            showingTemplatesSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Templates")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(templateStore.templates.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.appPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.appPrimary.opacity(0.18)))
            }
            .foregroundColor(.appPrimary)
            .padding(.horizontal, Theme.Spacing.sm + 2)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.appPrimary.opacity(0.10)))
            .overlay(Capsule().stroke(Color.appPrimary.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(templateStore.templates.count) saved templates")
    }

    // MARK: - v3 Templates Sheet
    //
    // Half-sheet listing every saved template as a bare row inside one
    // elevated white card. Tap to apply (closes the sheet), long-press
    // to delete. Matches the day-group treatment in AllExpensesView so
    // any "list of things" surface in the app reads as one component.

    @ViewBuilder
    private var templatesSheet: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Templates")
                                .font(Theme.Typography.pageTitle)
                                .foregroundColor(.primary)
                            Text("Tap to fill the form. Long-press to delete.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(templateStore.templates.count)/\(ExpenseTemplateStore.maxTemplates)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.appPrimary)
                            .monospacedDigit()
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.appPrimary.opacity(0.12)))
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)

                    if templateStore.templates.isEmpty {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 32, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.tertiary)
                            Text("No templates yet")
                                .font(Theme.Typography.rowTitle)
                                .foregroundColor(.primary)
                            Text("Save any expense as a preset using the chip in the header — perfect for recurring items like coffee or rent.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, Theme.Spacing.xl)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xxxl)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(templateStore.displayOrder.enumerated()), id: \.element.id) { idx, template in
                                Button {
                                    showingTemplatesSheet = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        applyTemplate(template)
                                    }
                                } label: {
                                    templateSheetRow(template)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        showingTemplatesSheet = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            applyTemplate(template)
                                        }
                                    } label: {
                                        Label("Use template", systemImage: "arrow.up.forward")
                                    }
                                    Button(role: .destructive) {
                                        pendingTemplateDeletionId = template.id
                                    } label: {
                                        Label("Delete template", systemImage: "trash")
                                    }
                                }

                                if idx < templateStore.templates.count - 1 {
                                    Divider()
                                        .padding(.leading, Theme.Spacing.xxl + 30)
                                        .opacity(0.4)
                                }
                            }
                        }
                        .cardSurface()
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingTemplatesSheet = false }
                        .fontWeight(.semibold)
                        .foregroundColor(.appPrimary)
                }
            }
        }
    }

    private func templateSheetRow(_ template: ExpenseTemplate) -> some View {
        let accent = templateAccentColor(for: template)
        let icon = templateIcon(for: template)
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(template.trimmedName)
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(template.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.formattedAmount(template.amount))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                if template.isRefund {
                    Text("REFUND")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md + 2)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .contentShape(Rectangle())
    }

    // Legacy big-label titleField removed in v3 — `compactTitleField`
    // (above, near hero amount) is the only entry-point now.

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

    // Legacy small-amount amountField removed in v3 — `heroAmountTile`
    // (above) is the only amount entry-point now.

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
            .presentationBackground(Color(uiColor: .systemBackground))
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

    // Legacy refundToggleRow removed in v3 — the refund flip lives
    // inside `heroAmountTile` as a corner toggle. Pulling it out of the
    // top-of-form spot freed ~70pt of vertical space and stopped the
    // form from interrogating users about a state most never use.

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

    // Legacy templatesChipStrip + templateChip removed in v3 — templates
    // now live behind the slim header `headerTemplatesChip`, which opens
    // a half-sheet (`templatesSheet`) rendering each template as a bare
    // row inside one elevated white card. Saves ~100pt at the top of
    // the form when templates exist, and keeps the entry surface focused
    // on Amount + Title + Category.

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

    // Legacy categoryPickerField removed in v3 — replaced by
    // `smartCategoryRow` (above), which adds a trailing "More" tile and
    // a smaller eyebrow label so the section reads as a real "picker"
    // rather than a labelled scroll view.

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Tags")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)

                Text("(Optional)")
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 12, weight: .medium))
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
        // v3: neutralised pill style. Every method shares the same
        // mauve accent so the picker reads as a single coordinated
        // choice rather than a row of competing Skittles colours.
        // Individual method colours still drive the *summary chip* in
        // the section header (where colour helps you scan-confirm
        // your pick) and the Statistics donut, where colour is the
        // primary differentiator.

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
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                Capsule()
                    .fill(isSelected ? Color.appPrimary : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
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
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 12, weight: .medium))
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
                if isScanningReceipt {
                    // Quiet OCR-in-flight state — replaces the hint
                    // line rather than adding chrome. Fails silently
                    // back to the hint when done.
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.65)
                        Text("Reading receipt…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else {
                    Text("Tap to view full size")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

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
                    // Kick off on-device OCR for auto-fill. Fully
                    // background + silent — the manual path is never
                    // blocked by this.
                    self.runReceiptOCR(on: image)
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

    // MARK: - Receipt OCR (Pro — inherits the capture gate)

    /// Run on-device Vision OCR against a freshly attached receipt and
    /// apply the results. Only ever ADDS to empty fields — a value the
    /// user typed is never overwritten. Fails silently on any error.
    private func runReceiptOCR(on image: UIImage) {
        // Capture is already Pro-gated, but keep an explicit guard so
        // OCR can never leak to free users through a future new
        // attach path.
        guard proManager.isPro else { return }

        receiptOCRTask?.cancel()
        withAnimation(Theme.Motion.snappy) {
            isScanningReceipt = true
        }

        receiptOCRTask = Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                await ReceiptOCRService.extract(from: image)
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.snappy) {
                isScanningReceipt = false
                applyReceiptOCRResult(result)
            }
        }
    }

    /// Fill-empty-fields-only application of an OCR result.
    private func applyReceiptOCRResult(_ result: ReceiptOCRResult) {
        var appliedSomething = false

        if let total = result.totalAmount {
            let currentValue = viewModel.parseAmount(amount) ?? 0
            let amountIsEmpty = amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if amountIsEmpty || currentValue == 0 {
                let filled = formatOCRAmount(total)
                amount = filled
                ocrFilledAmountString = filled
                amountFilledFromReceipt = true
                appliedSomething = true
            }
        }

        if let merchant = result.merchantName,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ocrMerchantSuggestion = merchant
            appliedSomething = true
        }

        if appliedSomething {
            HapticManager.shared.lightTap()
        }
    }

    /// Render an OCR total as a form-field string. Uses the active
    /// currency's fraction digits; drops trailing ".00" so a whole
    /// number reads like a human typed it. Locale-aware so the decimal
    /// separator matches what the user's decimal keyboard produces
    /// ("12,50" in comma-decimal locales, not "12.50") — either form
    /// round-trips through `viewModel.parseAmount`, which tries the
    /// current locale first and both separators as fallbacks.
    private func formatOCRAmount(_ value: Double) -> String {
        let digits = viewModel.selectedCurrency.fractionDigits
        if value == value.rounded() || digits == 0 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.\(digits)f", locale: .current, value)
    }

    /// Undo the receipt auto-fill (chip tap). Clears the amount back
    /// to empty and retires the chip.
    private func undoReceiptAmountFill() {
        HapticManager.shared.lightTap()
        withAnimation(Theme.Motion.snappy) {
            amount = ""
            amountFilledFromReceipt = false
            ocrFilledAmountString = ""
        }
    }

    /// Cancel any in-flight OCR and clear its pending suggestions.
    /// Called when the receipt is removed/replaced or the sheet closes.
    private func cancelReceiptOCR() {
        receiptOCRTask?.cancel()
        receiptOCRTask = nil
        withAnimation(Theme.Motion.snappy) {
            isScanningReceipt = false
            ocrMerchantSuggestion = nil
        }
    }

    /// Remove a receipt before saving the form. If the file was added
    /// during this session (not the pre-edit baseline), delete it from
    /// disk immediately. The pre-edit baseline waits for the save path
    /// to confirm the user actually committed the removal — otherwise
    /// dismissing without saving would lose the original.
    private func removeAttachedReceipt() {
        cancelReceiptOCR()
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
        cancelReceiptOCR()
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
            .background(Color(uiColor: .systemBackground))
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

            SaveConfirmationReporter.report(
                message: "Updated \(viewModel.formattedAmount(amountValue)) · \(savedCategoryDisplayName)"
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
        
        // Confirmation toast rendered on the presenting view (host in
        // MainTabView) so it never delays the sheet's dismissal.
        SaveConfirmationReporter.report(
            message: "Added \(viewModel.formattedAmount(amountValue)) to \(savedCategoryDisplayName)"
        )
        
        // Dismiss the view
        dismiss()
    }
    
    /// User-facing name of the category being saved — resolves custom
    /// categories to their real name instead of the generic "Custom".
    private var savedCategoryDisplayName: String {
        if selectedCategory == .custom,
           let id = selectedCustomCategoryId,
           let custom = categoryViewModel.getCustomCategory(id: id) {
            return custom.name
        }
        return selectedCategory.displayName
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

// MARK: - Receipt Source Picker Modifier
//
// Bundles the receipt-source confirmation dialog and the programmatic
// photo-library picker into a single ViewModifier. Extracted from the
// main `AddExpenseView` body purely as a type-check budget release —
// the body has ~25 chained modifiers and adding these two inline
// pushed the compiler past its "reasonable time" threshold. Behaviour
// is identical to applying both modifiers directly.

private struct ReceiptSourcePickerModifier: ViewModifier {
    @Binding var showingDialog: Bool
    @Binding var showingScanner: Bool
    @Binding var showingPhotoLibrary: Bool
    @Binding var pickedPhotoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showingPhotoLibrary,
                selection: $pickedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .confirmationDialog(
                "Add receipt",
                isPresented: $showingDialog,
                titleVisibility: .visible
            ) {
                if DocumentScannerView.isSupported {
                    Button {
                        HapticManager.shared.lightTap()
                        showingScanner = true
                    } label: {
                        Label("Scan with Camera", systemImage: "camera.viewfinder")
                    }
                }
                Button {
                    HapticManager.shared.lightTap()
                    showingPhotoLibrary = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Save a receipt to this expense — scan a paper bill or pick a photo you already have.")
            }
    }
}

struct AddExpenseView_Previews: PreviewProvider {
    static var previews: some View {
        AddExpenseView(viewModel: ExpenseViewModel())
    }
} 