import SwiftUI

/// Single expense row, used everywhere expenses are displayed
/// (Today, Activity, Calendar day-list, Search results, etc.).
///
/// `ExpenseCard` ships in two visual modes:
///
///   • **`.standalone`** (default) — self-contained elevated white
///     card with its own hairline + soft shadow. Right call when
///     each row is its own tile against a colored page (e.g.
///     Activity's day-group containers, Calendar's day list).
///
///   • **`.bare`** — no background, no border, no shadow. The row
///     is just content. Meant to be embedded inside a parent
///     container that provides one shared surface for a small
///     group of rows (e.g. Today's Recent block uses one container
///     card with three bare rows separated by hairlines, instead of
///     three separately-elevated tiles stacking on top of each
///     other — visually quieter and reads as "this is one cluster
///     of recent activity," not three competing cards).
///
/// Beyond mode, this commit also tightens the visual language:
///   • Smaller icon medallion (44 → was 50) so the row reads as
///     "data first, decoration second."
///   • Title uses `Theme.Typography.rowTitle` (semibold subheadline)
///     instead of raw `.headline` — one of the typography tokens
///     the audit caught the app routinely bypassing.
///   • Amount renders in **monospaced rounded digits** — the
///     "premium finance display" treatment.
///   • Padding shrinks to `Theme.Spacing.md` so the row matches the
///     visual rhythm of other v2 surfaces (Today's hero, week
///     strip, insight card).
struct ExpenseCard: View, Equatable {
    let expense: Expense
    let currencySymbol: String
    let categoryName: String
    let categoryIcon: String
    let categoryColorName: String
    let formattedAmount: String
    let style: Style

    enum Style: Equatable {
        case standalone, bare
    }

    // Equatable conformance for efficient SwiftUI diffing.
    //
    // IMPORTANT: We include `formattedAmount` (and `currencySymbol`) here even
    // though they're derived values. SwiftUI uses `==` together with the
    // `.equatable()` modifier to skip rendering. If we omit these and the user
    // changes their currency in Settings, the underlying `expense.amount`
    // doesn't move — but `viewModel.formattedAmount(...)` returns a new
    // string. Without this guard, the diff returns `true`, the cached row
    // stays on screen with the old "$2.99" and only refreshes after a
    // kill/relaunch. Including these makes the recents list update instantly.
    //
    // Every visible field must be in here. Anything we read in `body` and
    // omit here causes stale UI when only that field changes (e.g. editing
    // a row's notes alone, or recoloring a custom category and not its
    // amount).
    static func == (lhs: ExpenseCard, rhs: ExpenseCard) -> Bool {
        lhs.expense.id == rhs.expense.id &&
        lhs.expense.amount == rhs.expense.amount &&
        lhs.expense.title == rhs.expense.title &&
        lhs.expense.date == rhs.expense.date &&
        lhs.expense.notes == rhs.expense.notes &&
        lhs.categoryName == rhs.categoryName &&
        lhs.categoryIcon == rhs.categoryIcon &&
        lhs.categoryColorName == rhs.categoryColorName &&
        lhs.expense.tags == rhs.expense.tags &&
        lhs.expense.isRefund == rhs.expense.isRefund &&
        lhs.formattedAmount == rhs.formattedAmount &&
        lhs.currencySymbol == rhs.currencySymbol &&
        lhs.style == rhs.style &&
        // Receipt presence drives the paperclip badge — include it in
        // the diff so attaching/detaching a receipt re-renders the row
        // without waiting for a navigation refresh.
        lhs.expense.receiptImagePath == rhs.expense.receiptImagePath
    }

    var body: some View {
        rowContent
            .padding(.horizontal, Theme.Spacing.md + 2)
            .padding(.vertical, Theme.Spacing.md)
            .background(rowBackground)
            .overlay(rowBorder)
            .shadow(color: rowShadowColor, radius: 6, x: 0, y: 2)
            .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.md + 2) {
            categoryIconView

            // Expense details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(expense.title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if expense.isRefund {
                        refundBadge
                    }

                    if expense.receiptImagePath != nil {
                        receiptBadge
                    }
                }

                HStack(spacing: 6) {
                    Text(categoryName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let notes = expense.notes, !notes.isEmpty {
                        // Inline bullet between category and notes so we
                        // stop wasting a whole row on a 1-word note like
                        // "client" or "wife".
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if let tags = expense.tags, !tags.isEmpty {
                    tagsRow(tags: tags)
                }
            }

            Spacer(minLength: 8)

            // Amount + date
            VStack(alignment: .trailing, spacing: 3) {
                Text(expense.isRefund ? "−\(formattedAmount)" : formattedAmount)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(expense.isRefund ? .green : .primary)
                    .lineLimit(1)

                Text(expense.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if style == .standalone {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        if style == .standalone {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        } else {
            EmptyView()
        }
    }

    private var rowShadowColor: Color {
        style == .standalone ? Color.black.opacity(0.04) : Color.clear
    }

    /// Compact paperclip glyph shown only when this expense has an
    /// attached receipt. Tinted to the brand color so it reads as a
    /// "premium" affordance — Pro users get extra signal that their
    /// receipts are tracked. Tapping the row already opens the edit
    /// sheet which now includes the in-form viewer; we deliberately
    /// don't make this glyph itself tappable to keep the row's hit
    /// target unambiguous.
    private var receiptBadge: some View {
        Image(systemName: "paperclip")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Color.appPrimary)
            .padding(3)
            .background(Circle().fill(Color.appPrimary.opacity(0.13)))
            .accessibilityLabel("Has receipt")
    }

    /// Compact, accessible "Refund" pill. Shown only on refund rows.
    private var refundBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 8, weight: .bold))
            Text("Refund")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.3)
        }
        .foregroundColor(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.14)))
        .accessibilityLabel("Refund")
    }

    @ViewBuilder
    private func tagsRow(tags: [String]) -> some View {
        let visible = tags.prefix(3)
        let overflow = max(0, tags.count - visible.count)
        HStack(spacing: 4) {
            ForEach(visible, id: \.self) { tag in
                TagChip(tag, style: .inline)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var categoryIconView: some View {
        // NOTE: `.drawingGroup()` was previously applied here "for better
        // scroll performance" — that's a common SwiftUI footgun. It forces
        // an **offscreen render pass per cell on every frame** while
        // scrolling. With hundreds of expenses + a 120 Hz display you pay
        // that pass × N visible cells × 120/s and the scroll drops below
        // the ProMotion fast path. The icon (one Circle + one SF Symbol)
        // composites fine without it.
        ZStack {
            Circle()
                .fill(Color.forCategory(categoryColorName).opacity(0.18))
                .frame(width: 42, height: 42)

            Image(systemName: categoryIcon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.forCategory(categoryColorName))
        }
    }
}

// MARK: - Convenience Initializer with EnvironmentObjects
extension ExpenseCard {
    /// Convenience initializer that extracts data from view models
    /// This creates a self-contained card that won't re-render on unrelated viewModel changes
    init(expense: Expense, viewModel: ExpenseViewModel, categoryViewModel: CategoryViewModel, style: Style = .standalone) {
        self.expense = expense
        self.currencySymbol = viewModel.currencySymbol
        self.formattedAmount = viewModel.formattedAmount(expense.amount)
        self.style = style

        // Pre-compute category info to avoid lookups during render
        if expense.category == .custom, let customId = expense.customCategoryId,
           let custom = categoryViewModel.customCategories.first(where: { $0.id == customId }) {
            self.categoryName = custom.name
            self.categoryIcon = custom.icon
            self.categoryColorName = custom.colorName
        } else {
            self.categoryName = expense.category.rawValue
            self.categoryIcon = expense.category.icon
            self.categoryColorName = expense.category.color
        }
    }
}

// MARK: - Legacy Initializer (for backward compatibility)
extension ExpenseCard {
    @ViewBuilder
    static func withEnvironment(expense: Expense) -> some View {
        ExpenseCardWrapper(expense: expense)
    }
}

/// Wrapper that uses environment objects for backward compatibility
private struct ExpenseCardWrapper: View {
    let expense: Expense
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    var body: some View {
        ExpenseCard(expense: expense, viewModel: viewModel, categoryViewModel: categoryViewModel)
    }
}

struct ExpenseCard_Previews: PreviewProvider {
    static var previews: some View {
        let sample = Expense.sampleData[0]
        VStack(spacing: 16) {
            ExpenseCard(
                expense: sample,
                currencySymbol: "$",
                categoryName: sample.category.rawValue,
                categoryIcon: sample.category.icon,
                categoryColorName: sample.category.color,
                formattedAmount: "$49.99",
                style: .standalone
            )
            VStack(spacing: 0) {
                ExpenseCard(
                    expense: sample,
                    currencySymbol: "$",
                    categoryName: sample.category.rawValue,
                    categoryIcon: sample.category.icon,
                    categoryColorName: sample.category.color,
                    formattedAmount: "$49.99",
                    style: .bare
                )
                Divider().padding(.leading, 60)
                ExpenseCard(
                    expense: sample,
                    currencySymbol: "$",
                    categoryName: sample.category.rawValue,
                    categoryIcon: sample.category.icon,
                    categoryColorName: sample.category.color,
                    formattedAmount: "$49.99",
                    style: .bare
                )
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
