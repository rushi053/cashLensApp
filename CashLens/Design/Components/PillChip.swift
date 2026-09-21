import SwiftUI

/// Canonical filter / selection chip.
///
/// Unifies the various chip variants currently scattered across Home, All Expenses,
/// Statistics, and Subscriptions. Two shapes:
/// - `.capsule` — filter chips, time frame selectors.
/// - `.rounded` — selection pickers, picker segments.
struct PillChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    var shape: Shape = .capsule
    var fullWidth: Bool = false
    let action: () -> Void

    enum Shape {
        case capsule
        case rounded
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs + 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: Theme.Icon.chip, weight: .medium))
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.lg - 2)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundColor(isSelected ? .white : .primary)
            .background(background)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch shape {
        case .capsule:
            if isSelected {
                Capsule().fill(Color.appPrimary)
            } else {
                Capsule().fill(Color.secondarySystemBackground)
            }
        case .rounded:
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Color.appPrimary)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Color.secondarySystemBackground)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        HStack {
            PillChip(title: "All", isSelected: true) {}
            PillChip(title: "Week", isSelected: false) {}
            PillChip(title: "Month", icon: "calendar", isSelected: false) {}
        }

        HStack {
            PillChip(title: "Weekly", icon: "calendar.badge.clock", isSelected: true, shape: .rounded, fullWidth: true) {}
            PillChip(title: "Monthly", icon: "calendar", isSelected: false, shape: .rounded, fullWidth: true) {}
        }
        .padding(.horizontal)
    }
    .padding()
}
