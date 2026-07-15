import SwiftUI

/// Canonical empty-state layout, in the restrained system style
/// (`ContentUnavailableView` language): a large hierarchical symbol,
/// quiet typography, optional CTA.
///
/// Deliberately NO tinted circle bubble behind the icon — that
/// treatment reads as template/stock. Hierarchical rendering gives
/// the glyph built-in depth (multi-tone from one color) and matches
/// how Apple's own apps draw empty screens.
///
/// Icon guidance for call sites: prefer OUTLINE variants over `.fill`
/// (fills at 40pt+ look heavy), and pick a glyph that describes the
/// *content that will appear*, not a generic placeholder.
struct EmptyStatePanel<Action: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var action: () -> Action

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
                .padding(.bottom, Theme.Spacing.lg)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Spacing.sm)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                // Cap the measure so long copy wraps into a tidy block
                // instead of two edge-to-edge lines.
                .frame(maxWidth: 300)

            action()
                .padding(.top, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xxxl)
        .onAppear { appeared = true }
    }
}

extension EmptyStatePanel where Action == EmptyView {
    init(
        icon: String,
        title: String,
        message: String
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = { EmptyView() }
    }
}

// MARK: - Compact variant (used inline inside lists/cards, not as a full screen)

struct InlineEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
                .padding(.bottom, Theme.Spacing.xs)

            Text(title)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
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
            icon: "gauge.with.needle",
            title: "Give Your Money a Plan",
            message: "Set a weekly or monthly cap and CashLens will track your pace before you overshoot."
        ) {
            PrimaryGradientButton(title: "Create Your First Budget", width: .hug) {}
        }

        Divider().padding(.vertical)

        InlineEmptyState(
            icon: "tray",
            title: "No expenses yet",
            message: "Tap + to log your first one."
        )
    }
    .padding()
}
