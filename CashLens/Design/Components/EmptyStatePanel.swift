import SwiftUI

/// Canonical empty-state layout: large icon in a tinted circle, title, message, optional CTA.
///
/// Replaces the ~6 hand-rolled empty states across Home, All Expenses, Budgets,
/// Subscriptions, Statistics, and Quick Search.
struct EmptyStatePanel<Action: View>: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = .appPrimary
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundColor(tint)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xxl)

            action()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

extension EmptyStatePanel where Action == EmptyView {
    init(
        icon: String,
        title: String,
        message: String,
        tint: Color = .appPrimary
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.tint = tint
        self.action = { EmptyView() }
    }
}

// MARK: - Compact variant (used inline inside lists, not as a full screen)

struct InlineEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Theme.Icon.emptyState, weight: .regular))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        EmptyStatePanel(
            icon: "target",
            title: "No Budgets Yet",
            message: "Create a budget to track your spending and get alerts when you're close to the limit."
        ) {
            PrimaryGradientButton(title: "Create Your First Budget", width: .hug) {}
        }

        Divider().padding(.vertical)

        InlineEmptyState(
            icon: "doc.text.magnifyingglass",
            title: "No expenses found",
            message: "Add your first expense by tapping the + button"
        )
    }
    .padding()
}
