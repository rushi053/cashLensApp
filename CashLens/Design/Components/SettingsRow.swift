import SwiftUI

/// Canonical settings / menu row.
///
/// Ships in two visual modes:
///
///   • **`.standalone`** (default) — self-contained card with its
///     own `.cardSurface()` background. Right call when the row is
///     by itself (e.g. the lone "Clear All Data" row in About).
///
///   • **`.bare`** — no background. Meant to be embedded inside a
///     `SettingsGroup` that provides one shared container for a
///     small cluster of rows, separated by hairlines — the iOS
///     Settings-app grouping pattern, instead of N visually-
///     elevated tiles stacking on each other.
///
/// The row itself is not a Button — tap handling is up to the caller
/// so it plays nicely with `.onTapGesture`, `NavigationLink`, or sheet
/// triggers.
struct SettingsRow<Trailing: View>: View {
    let icon: String
    var iconTint: Color = .appPrimary
    let title: String
    var subtitle: String? = nil
    var showsChevron: Bool = true
    var style: Style = .standalone
    @ViewBuilder var trailing: () -> Trailing

    enum Style: Equatable {
        case standalone, bare
    }

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
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, style == .bare ? Theme.Spacing.md : Theme.Spacing.lg)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowBackground: some View {
        if style == .standalone {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        } else {
            Color.clear
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        icon: String,
        iconTint: Color = .appPrimary,
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true,
        style: Style = .standalone
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.style = style
        self.trailing = { EmptyView() }
    }
}

/// Container that wraps a small cluster of `.bare`-style settings
/// rows in one elevated card with leading-inset hairlines between
/// them. Optional `title` is rendered above the group as a small
/// section eyebrow — the iOS-native settings grouping treatment.
///
/// Usage:
/// ```
/// SettingsGroup(title: "Preferences") {
///     SettingsRow(icon: "globe", title: "Currency", style: .bare) {
///         SettingsRowValue(text: "USD")
///     }
///     SettingsRow(icon: "moon", title: "Appearance", style: .bare) {
///         SettingsRowValue(text: "System")
///     }
/// }
/// ```
struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundColor(.secondary)
                    .padding(.leading, Theme.Spacing.md)
            }
            VStack(spacing: 0) {
                _VariadicView.Tree(SettingsGroupLayout()) {
                    content()
                }
            }
            .cardSurface()
        }
    }
}

/// Variadic layout that draws a leading-inset divider between
/// each child row. Uses SwiftUI's underscored variadic API — the
/// standard way to inject a separator pattern between an unknown
/// number of children (the same primitive `_VStackLayout` and
/// `ForEach` use internally).
private struct SettingsGroupLayout: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let array = Array(children)
        ForEach(Array(array.enumerated()), id: \.element.id) { idx, child in
            child
            if idx < array.count - 1 {
                Divider()
                    .padding(.leading, Theme.Spacing.lg + 30 + Theme.Spacing.md)
            }
        }
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
    var style: SettingsRow<EmptyView>.Style = .standalone

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
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, style == .bare ? Theme.Spacing.md : Theme.Spacing.lg)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowBackground: some View {
        if style == .standalone {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        } else {
            Color.clear
        }
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
