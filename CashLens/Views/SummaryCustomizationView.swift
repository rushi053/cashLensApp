import SwiftUI

/// Lets the user choose which 4 categories appear as Pinned Categories on
/// Home. Redesigned around a single idea: **the selected cards are the
/// preview.** The old large miniature-tile preview section was removed
/// (it competed with the real selection cards below and shrank everything
/// to fit). Instead, a compact "order" chip strip at the top confirms the
/// pin set in order, and the category cards themselves take full canvas to
/// feel premium.
struct SummaryCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    @State private var selectedTokens: [String] = []
    @State private var availableItems: [SummaryCategoryItem] = []

    /// Home's Pinned Categories grid holds up to 4 tiles.
    private let maxSelections = 4

    private struct SummaryCategoryItem: Identifiable, Hashable {
        let token: String
        let title: String
        let icon: String
        let color: Color
        let amount: Double
        let expenseCount: Int

        var id: String { token }
    }

    private var itemsByToken: [String: SummaryCategoryItem] {
        Dictionary(uniqueKeysWithValues: availableItems.map { ($0.token, $0) })
    }

    private var selectedItems: [SummaryCategoryItem] {
        selectedTokens.compactMap { itemsByToken[$0] }
    }

    private var hasChangesFromDefault: Bool {
        let defaults = Set(
            viewModel.getDefaultSummaryCategories().prefix(maxSelections).map { $0.rawValue }
        )
        return Set(selectedTokens) != defaults
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        headerBlock
                        orderStrip
                        pickerBlock
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, 132)
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) { closeRow }
            .overlay(alignment: .bottom) { saveBar }
        }
        .onAppear { setupInitialState() }
    }

    // MARK: - Close row

    private var closeRow: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Customize Home")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Pick up to 4 categories to pin on Home for at-a-glance spending.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xxl + 12)
    }

    // MARK: - Order chip strip

    private var orderStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Home line-up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                Text("\(selectedItems.count) of \(maxSelections)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(selectedItems.count == maxSelections ? .appPrimary : .secondary)
                    .contentTransition(.numericText())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.sm + 2)],
                alignment: .leading,
                spacing: Theme.Spacing.sm + 2
            ) {
                ForEach(0..<maxSelections, id: \.self) { index in
                    if index < selectedItems.count {
                        let item = selectedItems[index]
                        orderChip(for: item, index: index)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        emptyOrderChip(index: index)
                    }
                }
            }
        }
    }

    private func orderChip(for item: SummaryCategoryItem, index: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(item.color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("#\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(item.color)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule()
                .fill(Color.secondarySystemBackground)
        )
        .overlay(
            Capsule()
                .stroke(item.color.opacity(0.25), lineWidth: 1)
        )
    }

    private func emptyOrderChip(index: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 28, height: 28)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Text("Slot \(index + 1)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Capsule()
                .stroke(
                    Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
    }

    // MARK: - Category picker

    private var pickerBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center) {
                Text("Choose categories")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)

                Spacer()

                if hasChangesFromDefault {
                    Button(action: resetToDefaults) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Reset")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.appPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.md),
                GridItem(.flexible(), spacing: Theme.Spacing.md)
            ], spacing: Theme.Spacing.md) {
                ForEach(availableItems) { item in
                    CategorySelectionCard(
                        title: item.title,
                        icon: item.icon,
                        color: item.color,
                        amount: viewModel.formattedAmount(item.amount),
                        expenseCount: item.expenseCount,
                        isSelected: selectedTokens.contains(item.token),
                        isDisabled: !selectedTokens.contains(item.token) && selectedTokens.count >= maxSelections,
                        onTap: { toggleToken(item.token) }
                    )
                }
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            // Hairline divider replaces fade-to-background gradient.
            Divider().opacity(0.35)

            Button(action: saveAndDismiss) {
                Text("Save Changes")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .primaryGlow(strength: 0.35)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl + 8)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Logic

    private func setupInitialState() {
        let defaultItems: [SummaryCategoryItem] = viewModel
            .getAvailableDefaultCategories()
            .filter { $0 != .custom && $0 != .other }
            .map { category in
                SummaryCategoryItem(
                    token: category.rawValue,
                    title: category.displayName,
                    icon: category.icon,
                    color: Color.forCategory(category.color),
                    amount: viewModel.totalExpenses(for: category),
                    expenseCount: viewModel.expenseCount(for: category)
                )
            }

        let customItems: [SummaryCategoryItem] = categoryViewModel
            .customCategories
            .map { custom in
                SummaryCategoryItem(
                    token: "custom:\(custom.id.uuidString)",
                    title: custom.name,
                    icon: custom.icon,
                    color: Color.forCategory(custom.colorName),
                    amount: viewModel.totalExpenses(forCustomCategoryId: custom.id),
                    expenseCount: viewModel.expenseCount(forCustomCategoryId: custom.id)
                )
            }

        availableItems = defaultItems + customItems

        selectedTokens = Array(viewModel.preferredSummaryCategoryTokens.prefix(maxSelections))
        selectedTokens = selectedTokens.filter { itemsByToken[$0] != nil }

        if selectedTokens.isEmpty {
            selectedTokens = Array(viewModel.getDefaultSummaryCategories().prefix(maxSelections)).map { $0.rawValue }
        }
    }

    private func toggleToken(_ token: String) {
        HapticManager.shared.impact(style: .light)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            if selectedTokens.contains(token) {
                selectedTokens.removeAll { $0 == token }
            } else if selectedTokens.count < maxSelections {
                selectedTokens.append(token)
            }
        }
    }

    private func resetToDefaults() {
        HapticManager.shared.impact(style: .medium)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            selectedTokens = Array(viewModel.getDefaultSummaryCategories().prefix(maxSelections)).map { $0.rawValue }
        }
    }

    private func saveAndDismiss() {
        HapticManager.shared.impact(style: .medium)
        viewModel.updateSummaryCategoryTokens(selectedTokens)
        dismiss()
    }
}

// MARK: - Category selection card

/// Premium picker card that mirrors the real `PinnedCategoryCard` idiom at
/// a slightly reduced scale so "selecting" a card literally shows the user
/// what it'll look like on Home. Full-bleed typography, confident rhythm —
/// no placeholder bars, no ghosted states.
private struct CategorySelectionCard: View {
    let title: String
    let icon: String
    let color: Color
    let amount: String
    let expenseCount: Int
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    private var cardHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 158 : 144
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Spacer(minLength: 10)
                contentBlock
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: cardHeight, alignment: .topLeading)
            .background(backgroundFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(borderOverlay)
            .shadow(
                color: isSelected ? color.opacity(0.18) : Theme.Shadow.cardColor,
                radius: isSelected ? 10 : Theme.Shadow.cardRadius,
                x: 0,
                y: isSelected ? 4 : Theme.Shadow.cardY
            )
            .opacity(isDisabled ? 0.62 : 1.0)
            .animation(Theme.Motion.snappy, value: isSelected)
        }
        .disabled(isDisabled)
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Sub-views

    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            iconMedallion
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 40)
    }

    private var iconMedallion: some View {
        ZStack {
            Circle()
                .fill(isSelected ? color.opacity(0.28) : Color(.systemGray6))
                .frame(width: 40, height: 40)
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isSelected ? color : .secondary)
        }
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(amount)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .padding(.top, 1)

            Text(expenseCount == 1 ? "1 expense" : "\(expenseCount) expenses")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.top, 1)
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        if isSelected {
            color.opacity(0.10)
        } else {
            Color.secondarySystemBackground
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(color, lineWidth: 1.5)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: Theme.Stroke.hairline)
        }
    }
}

#if DEBUG
struct SummaryCustomizationView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryCustomizationView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(CategoryViewModel())
    }
}
#endif
