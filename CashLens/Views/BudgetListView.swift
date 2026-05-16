import SwiftUI

struct BudgetListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager

    @State private var showingAddBudget = false
    @State private var editingBudget: Budget?

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if budgetViewModel.budgets.isEmpty {
                    emptyState
                } else {
                    budgetList
                }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticManager.shared.lightTap()
                        showingAddBudget = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBudget) {
                BudgetSetupView()
                    .environmentObject(budgetViewModel)
                    .environmentObject(expenseViewModel)
                    .environmentObject(categoryViewModel)
                    .environmentObject(proManager)
            }
            .sheet(item: $editingBudget) { budget in
                BudgetSetupView(editingBudget: budget)
                    .environmentObject(budgetViewModel)
                    .environmentObject(expenseViewModel)
                    .environmentObject(categoryViewModel)
                    .environmentObject(proManager)
            }
            .onAppear {
                if !proManager.isPro {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Budget List

    private var budgetList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(budgetViewModel.budgets) { budget in
                    let progress = budgetViewModel.progress(for: budget)
                    BudgetListRow(
                        budget: budget,
                        progress: progress,
                        formattedAmount: expenseViewModel.formattedAmount,
                        onTap: { editingBudget = budget },
                        onToggle: { budgetViewModel.toggleBudgetActive(budget) },
                        onDelete: { budgetViewModel.deleteBudget(budget) }
                    )
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStatePanel(
            icon: "target",
            title: "No Budgets Yet",
            message: "Create a budget to track your spending and get alerts when you're close to the limit."
        ) {
            PrimaryGradientButton(title: "Create Your First Budget", width: .hug) {
                HapticManager.shared.heavyTap()
                showingAddBudget = true
            }
        }
    }
}

// MARK: - Row

private struct BudgetListRow: View {
    let budget: Budget
    let progress: BudgetViewModel.BudgetProgress
    let formattedAmount: (Double) -> String
    let onTap: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var ringColor: Color {
        switch progress.status {
        case .safe:     return .appPrimary
        case .warning:  return .orange
        case .exceeded: return .red
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md + 2) {
                ZStack {
                    Circle()
                        .stroke(ringColor.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(progress.percentage), 1.0))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Image(systemName: budget.categoryFilter.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ringColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.xs + 2) {
                        Text(budget.name)
                            .font(Theme.Typography.rowTitle)
                            .foregroundColor(budget.isActive ? .primary : .secondary)

                        if !budget.isActive {
                            Text("Paused")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, Theme.Spacing.xs + 2)
                                .padding(.vertical, Theme.Spacing.xxs)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.xs, style: .continuous))
                        }
                    }

                    Text("\(formattedAmount(progress.spent)) of \(formattedAmount(progress.limit)) • \(budget.period.rawValue)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(Int(min(progress.percentage * 100, 999)))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(budget.isActive ? ringColor : .secondary)
            }
            .padding(Theme.Spacing.md + 2)
            .cardSurface(radius: Theme.Radius.row)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                HapticManager.shared.selectionChanged()
                onToggle()
            } label: {
                Label(budget.isActive ? "Pause" : "Resume", systemImage: budget.isActive ? "pause.circle" : "play.circle")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Budget?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                HapticManager.shared.success()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
