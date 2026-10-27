//
//  LogExpenseIntent.swift
//  CashLens (main app target — NOT the widget extension)
//
//  "Log ₹450 for coffee" via Siri / Shortcuts / Spotlight.
//
//  Defined in the APP target on purpose: the Core Data store lives in
//  the app container (not the App Group), so the intent must execute
//  in the app's process. App Intents in the app target run the app in
//  the background — no scene required — and `QuickLogService` handles
//  the headless write + widget refresh.
//
//  Free feature: capture is always free (PRO_FEATURES.md philosophy) —
//  no Pro gate here.
//
import AppIntents
import SwiftUI
import os

struct LogExpenseIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription(
        "Add an expense to CashLens without opening the app.",
        categoryName: "Logging"
    )
    /// Runs headless in the background — logging should never yank the
    /// user into the app.
    static var openAppWhenRun: Bool = false

    // IntentCurrencyAmount, NOT Double: with a bare Double, Siri's
    // speech layer mangles money phrases — "250 rupees" resolved to
    // 100.0 in device testing (verified via the diagnostic trail),
    // because the currency word sends it down a money-parsing path
    // that can't land on a unitless number. The currency-aware type
    // makes "250", "250 rupees", and "₹250" all resolve correctly.
    @Parameter(
        title: "Amount",
        requestValueDialog: "How much did you spend?"
    )
    var amount: IntentCurrencyAmount

    // Required on purpose: without it every Siri log lands as a bare
    // "Other" row, which users read as the intent not listening. Siri
    // asks "What was it for?" and the answer doubles as the category
    // inference input below.
    @Parameter(
        title: "Title",
        requestValueDialog: "What was it for?"
    )
    var title: String

    @Parameter(
        title: "Category",
        optionsProvider: ExpenseCategoryOptionsProvider()
    )
    var category: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) for \(\.$title)") {
            \.$category
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Diagnostic trail for the Siri flow — shows exactly what the
        // system resolved from speech before we act on it.
        QuickLogService.diagTrail("LogExpenseIntent.perform amount=\(amount.amount) code=\(amount.currencyCode) title=\(title) category=\(category ?? "<nil>")")

        // The spoken currency code is intentionally ignored for storage:
        // CashLens logs in the user's selected app currency, and we take
        // the NUMBER the user said ("250 rupees" → 250 in app currency).
        // Cross-currency conversion is explicitly out of scope (no rates,
        // no network — privacy-first).
        let numericAmount = (amount.amount as NSDecimalNumber).doubleValue

        // Never log an amount the user didn't state. `amount` is required
        // with NO default, so the system asks "How much did you spend?"
        // before perform() runs. If what arrives is still unusable (zero,
        // negative, NaN — e.g. a blank field in a Shortcuts flow or a
        // garbled voice resolution), throw the parameter's needsValueError
        // so Siri RE-ASKS and re-performs, instead of a generic error that
        // ends the conversation.
        guard numericAmount.isFinite, numericAmount > 0 else {
            throw $amount.needsValueError("How much did you spend?")
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Category: explicit pick wins; otherwise infer from the spoken
        // title ("coffee" → Food, "uber" → Transportation) instead of
        // dumping everything into Other. In the Siri flow the category
        // parameter is never asked for, so inference is the common path.
        var resolved = QuickLogService.resolveCategory(named: category)
        if (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved = QuickLogService.inferCategory(fromTitle: trimmedTitle)
        }
        let categoryName = QuickLogService.displayName(
            for: resolved.category,
            customCategoryId: resolved.customCategoryId
        )
        // An empty title renders awkwardly in every list row, so fall
        // back to the category name — same convention the widget
        // quick-log path uses.
        let effectiveTitle = trimmedTitle.isEmpty ? categoryName : trimmedTitle

        let expense = try QuickLogService.logExpense(
            amount: numericAmount,
            title: effectiveTitle,
            category: resolved.category,
            customCategoryId: resolved.customCategoryId
        )

        // Push a fresh snapshot so Home Screen widgets show the new
        // total immediately — the coordinator may not be bootstrapped
        // when the intent ran headless.
        QuickLogService.rebuildWidgetSnapshotFromStore()

        let currency = QuickLogService.selectedCurrency()
        let formatted = QuickLogService.formatAmount(expense.amount, currency: currency)
        let dialog = IntentDialog("Added \(formatted) for \(effectiveTitle)")

        return .result(
            dialog: dialog,
            view: LogExpenseSnippetView(
                amountText: formatted,
                title: effectiveTitle,
                categoryName: categoryName,
                categorySymbol: resolved.category == .custom ? "tag.fill" : resolved.category.icon
            )
        )
    }
}

// MARK: - Category options

/// Dynamic options: available default categories (respecting user
/// deletions) + custom categories, fetched straight from the store.
struct ExpenseCategoryOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        QuickLogService.availableCategoryNames()
    }
}

// MARK: - Snippet view

/// Compact confirmation card shown under Siri's dialog. Deliberately
/// self-contained (no Theme dependency) — snippet rendering happens in
/// a system-hosted context where we keep the view tree trivial.
struct LogExpenseSnippetView: View {
    let amountText: String
    let title: String
    let categoryName: String
    let categorySymbol: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: categorySymbol)
                        .font(.system(size: 10, weight: .semibold))
                    Text(categoryName)
                        .font(.system(.caption, design: .rounded))
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
    }
}
