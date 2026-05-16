import SwiftUI
import Foundation

/// Modern, modal currency picker matching the design language of
/// `ManageCategoriesView` / `BudgetSetupView`:
///
///   • Custom header (X close · "Currency" title · Done)
///   • Live preview tile that re-formats `1,234.56` in the currently-selected
///     currency so the user can sanity-check what their amounts will look
///     like before committing.
///   • "Recently Used" shortcut row (top three, persisted in `UserDefaults`)
///   • "Use Device Default" quick action that re-syncs to whatever currency
///     iOS reports for `Locale.current`.
///   • Region pills (All / Americas / Europe / …) for fast filtering.
///   • Country flag emojis on every row, derived from the ISO 4217 code's
///     two-letter prefix (USD → 🇺🇸, INR → 🇮🇳, EUR → 🇪🇺). Falls back to
///     a globe glyph for supranational codes.
///
/// Selecting a currency updates `viewModel.selectedCurrency` immediately so
/// the live preview reflects the change without a network round-trip; the
/// user can keep auditioning rows or tap Done. We **only** record into
/// `RecentCurrenciesStore` on a user-initiated tap so silent reassignments
/// (locale auto-pick, backup restore) never pollute the recents.
struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExpenseViewModel
    var isInitialSetup: Bool = false

    @State private var searchText = ""
    @State private var selectedRegion: CurrencyRegion = .all
    @State private var recentCurrencies: [Expense.Currency] = []
    @FocusState private var searchFocused: Bool

    /// User's pending currency pick, awaiting confirmation in the
    /// disclosure alert. Non-nil → alert is presented.
    ///
    /// We hold the pick out-of-band rather than mutating
    /// `viewModel.selectedCurrency` immediately because the model
    /// setter triggers `updateAllExpensesToCurrentCurrency()` —
    /// which is the very thing we're trying to ask the user about
    /// before it happens. Committing to the model is intentionally
    /// the last step in the confirm path.
    @State private var pendingCurrency: Expense.Currency? = nil

    // The "live preview" tile always formats the same fictional number so
    // the user can compare how each currency will render. 1,234.56 is the
    // canonical example because it exercises the grouping separator and
    // the decimal separator at the same time.
    private let previewAmount: Double = 1_234.56

    // MARK: - Filtering

    /// Currencies in the currently-selected region, deduped, alphabetised
    /// by ISO code, then narrowed by the search query (matches code or
    /// human-readable name, case insensitive).
    private var filteredCurrencies: [Expense.Currency] {
        let regionCurrencies = selectedRegion.currencies
        let unique = Array(Set(regionCurrencies)).sorted { $0.rawValue < $1.rawValue }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return unique }
        return unique.filter { c in
            c.rawValue.localizedCaseInsensitiveContains(q) ||
            c.name.localizedCaseInsensitiveContains(q)
        }
    }

    /// Whether the current filter (region + search) yields any matches —
    /// drives the "no results" empty state.
    private var hasResults: Bool { !filteredCurrencies.isEmpty }

    /// Whether to show the "Recently Used" section. We hide it during
    /// active search to avoid noise.
    private var showsRecents: Bool {
        !recentCurrencies.isEmpty &&
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchField
                regionPills

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        previewCard

                        if showsRecents {
                            recentsSection
                        }

                        currencyListSection
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .interactiveDismissDisabled(isInitialSetup)
        .onAppear { recentCurrencies = RecentCurrenciesStore.load() }
        // Disclosure alert before silently relabeling existing
        // money. Only presented when the user has data that will be
        // affected — first-run / empty-store flows skip it entirely
        // so onboarding is still one tap.
        .alert(
            pendingCurrencyAlertTitle,
            isPresented: Binding(
                get: { pendingCurrency != nil },
                set: { if !$0 { pendingCurrency = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                // Dismiss-only — the binding's setter clears
                // `pendingCurrency` on its own when isPresented
                // flips to false.
                HapticManager.shared.lightTap()
            }
            Button("Change Display") {
                if let pending = pendingCurrency {
                    commitCurrency(pending)
                }
            }
        } message: {
            Text(pendingCurrencyAlertMessage)
        }
    }

    // MARK: - Pending currency alert copy
    //
    // Both strings derive from `pendingCurrency` + the live
    // `viewModel.selectedCurrency`, so the wording always matches
    // the actual swap the user is about to authorise.

    private var pendingCurrencyAlertTitle: String {
        guard let pending = pendingCurrency else { return "" }
        return "Change to \(pending.flag) \(pending.rawValue)?"
    }

    private var pendingCurrencyAlertMessage: String {
        guard let pending = pendingCurrency else { return "" }
        let from = viewModel.selectedCurrency.symbol
        let to = pending.symbol
        // Concrete worked example — the audit's exact failure mode
        // (\($)100 silently becoming \(₹)100) is the most legible
        // way to explain the relabel-not-convert distinction in one
        // sentence. Keep this concrete; abstract phrasing didn't
        // land in user testing of similar disclosures.
        return "Your existing entries will be relabeled — only the symbol changes, not the numbers. \(from)100 will display as \(to)100. CashLens does not convert amounts using exchange rates."
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            // X close (hidden during initial setup so the user can't escape
            // before picking a currency — they have a Continue button instead).
            if !isInitialSetup {
                Button {
                    HapticManager.shared.lightTap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondarySystemBackground)
                        .clipShape(Circle())
                }
            } else {
                Color.clear.frame(width: 32, height: 32)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(isInitialSetup ? "Choose Your Currency" : "Currency")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                if isInitialSetup {
                    Text("You can change this anytime in Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                HapticManager.shared.mediumTap()
                dismiss()
            } label: {
                Text(isInitialSetup ? "Continue" : "Done")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 8)
                    .background(Color.appPrimary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.md)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)

            TextField("Search currencies or codes…", text: $searchText)
                .focused($searchFocused)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)

            if !searchText.isEmpty {
                Button {
                    HapticManager.shared.lightTap()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Region pills

    private var regionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CurrencyRegion.allCases, id: \.self) { region in
                    let isOn = selectedRegion == region
                    Button {
                        HapticManager.shared.selectionChanged()
                        withAnimation(Theme.Motion.tap) {
                            selectedRegion = region
                        }
                    } label: {
                        Text(region.rawValue)
                            .font(.system(size: 13, weight: isOn ? .bold : .semibold, design: .rounded))
                            .foregroundColor(isOn ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isOn ? Color.appPrimary : Color.secondarySystemBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Live preview tile

    /// Shows what `1,234.56` looks like in the currently-selected currency,
    /// so the user can sanity-check the symbol position, decimal count, and
    /// grouping before committing.
    private var previewCard: some View {
        let currency = viewModel.selectedCurrency

        return VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Text(currency.flag)
                    .font(.system(size: 32))
                    .frame(width: 48, height: 48)
                    .background(Color.appPrimary.opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(currency.rawValue) · \(currency.symbol)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider().opacity(0.4)

            HStack {
                Text("Preview")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                Text(viewModel.formattedAmount(previewAmount))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.tap, value: viewModel.selectedCurrency)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
    }

    // MARK: - Recently Used section

    @ViewBuilder
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text("Recently Used")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(recentCurrencies.enumerated()), id: \.element) { idx, currency in
                    currencyRow(currency: currency, isFirst: idx == 0, isLast: idx == recentCurrencies.count - 1)
                    if idx < recentCurrencies.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(Color.secondarySystemBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))

            // Use-device-default shortcut sits with the recents because both
            // are zero-thought "fast paths" the user is most likely to want.
            useDeviceDefaultButton
        }
    }

    private var useDeviceDefaultButton: some View {
        Button {
            guard let code = Locale.current.currency?.identifier.uppercased(),
                  let currency = Expense.Currency(rawValue: code) else {
                HapticManager.shared.warning()
                return
            }
            applyCurrency(currency)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Use Device Default")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                if let code = Locale.current.currency?.identifier.uppercased(),
                   let curr = Expense.Currency(rawValue: code) {
                    Text("· \(curr.flag) \(curr.rawValue)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.appPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 12)
            .background(Color.appPrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main currency list

    @ViewBuilder
    private var currencyListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Text(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "All Currencies"
                     : "Search Results")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                if hasResults {
                    Text("\(filteredCurrencies.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 4)

            if hasResults {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredCurrencies.enumerated()), id: \.element.rawValue) { idx, currency in
                        currencyRow(currency: currency, isFirst: idx == 0, isLast: idx == filteredCurrencies.count - 1)
                        if idx < filteredCurrencies.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Color.secondarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
            } else {
                emptyState
            }
        }
    }

    /// One row in either the "Recently Used" list or the main list. Same
    /// shape both places so the picker reads as a single coherent grid.
    private func currencyRow(currency: Expense.Currency, isFirst: Bool, isLast: Bool) -> some View {
        let isSelected = viewModel.selectedCurrency == currency
        return Button {
            applyCurrency(currency)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Text(currency.flag)
                    .font(.system(size: 26))
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(currency.rawValue)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(currency.symbol)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.tertiarySystemBackground)
                            .clipShape(Capsule())
                    }
                    Text(currency.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.appPrimary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text("No matches")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text("Try a different region, code, or country name.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
    }

    // MARK: - Selection

    /// Apply a user-initiated currency pick. For first-run or
    /// empty-store flows the change commits immediately; otherwise
    /// we stash the pick and present a disclosure alert before the
    /// silent relabel happens.
    ///
    /// **Why disclose first.** Setting `selectedCurrency` triggers
    /// `updateAllExpensesToCurrentCurrency()`, which rewrites every
    /// stored expense's `currency` field to the new selection
    /// without converting the numeric `amount`. So $100 becomes
    /// ₹100 (~$1.20 at real rates) — a money-trust break the
    /// audit flagged as a launch blocker. Explicit consent here
    /// closes that gap without requiring real FX conversion (which
    /// is on the v2.x roadmap).
    private func applyCurrency(_ currency: Expense.Currency) {
        guard viewModel.selectedCurrency != currency else {
            HapticManager.shared.lightTap()
            return
        }

        // Skip the disclosure when there's nothing to mislabel:
        //
        // 1. `isInitialSetup` — first-run currency picker flows from
        //    onboarding. The user has zero data; the picker is just
        //    setting the default for their first entry.
        // 2. Empty store — long-running install with all data wiped,
        //    or a brand-new install where the user opens Settings →
        //    Currency before logging anything.
        //
        // Both cases would only confuse the user with an alert about
        // entries that don't exist.
        if isInitialSetup || viewModel.expenses.isEmpty {
            commitCurrency(currency)
            return
        }

        // Has data → require explicit consent. Soft haptic to ack
        // the tap; the alert itself is the visible confirmation.
        HapticManager.shared.lightTap()
        pendingCurrency = currency
    }

    /// Commit a currency change to the model + recents store.
    /// Called either directly (no-data path) or from the alert's
    /// "Change Display" button (has-data path). Recents are only
    /// updated on commit so cancelled picks don't pollute the
    /// quick-pick list at the top of the picker.
    private func commitCurrency(_ currency: Expense.Currency) {
        HapticManager.shared.selectionChanged()
        withAnimation(Theme.Motion.snappy) {
            viewModel.selectedCurrency = currency
        }
        RecentCurrenciesStore.record(currency)
        recentCurrencies = RecentCurrenciesStore.load()
    }
}

// MARK: - Preview

struct CurrencyPickerView_Previews: PreviewProvider {
    static var previews: some View {
        CurrencyPickerView(viewModel: ExpenseViewModel())
    }
}
