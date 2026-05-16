import SwiftUI

/// Canonical settings / menu row.
///
/// Replaces the many variants of `HStack { Image … Text … Spacer … Image(chevron) }`
/// rows spread across `ProfileView`, `ExportDataView`, `ImportDataView`, etc.
/// The row itself is not a Button — tap handling is up to the caller so it plays
/// nicely with `.onTapGesture`, `NavigationLink`, or sheet triggers.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    var iconTint: Color = .appPrimary
    let title: String
    var subtitle: String? = nil
    var showsChevron: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Theme.Icon.heroRow, weight: .regular))
                .foregroundColor(iconTint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            trailing()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .cardSurface(radius: Theme.Radius.row)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        icon: String,
        iconTint: Color = .appPrimary,
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.trailing = { EmptyView() }
    }
}

/// Compact value label for the `trailing` slot (e.g. "USD", "System", "Monthly").
struct SettingsRowValue: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Destructive variant — red icon + red title, no chevron by default.
struct SettingsRowDestructive: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Theme.Icon.heroRow, weight: .regular))
                .foregroundColor(.red)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.red)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .cardSurface(radius: Theme.Radius.row)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SettingsRow(icon: "dollarsign.circle.fill", title: "Default Currency") {
            SettingsRowValue(text: "$ USD")
        }

        SettingsRow(
            icon: "bell.badge.fill",
            title: "Weekly Digest",
            subtitle: "A weekly spending summary. Tap to open your expenses for that week.",
            showsChevron: false
        ) {
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .tint(.appPrimary)
        }

        SettingsRowDestructive(icon: "trash.fill", title: "Clear All Data")
    }
    .padding()
}
