import SwiftUI

/// Canonical in-page section header. Replaces the handful of one-off header
/// HStacks scattered across `HomeView`, `ProfileView`, etc.
///
/// Use `.section` for primary in-page sections ("Summary", "Recent Expenses"),
/// `.subsection` for grouped subsections ("Due Soon"), and `.page` only for
/// tab-level screen titles inside scroll content.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var style: Style = .section
    var trailing: () -> Trailing

    enum Style {
        case page
        case section
        case subsection

        var font: Font {
            switch self {
            case .page:       return Theme.Typography.pageTitle
            case .section:    return Theme.Typography.sectionTitle
            case .subsection: return Theme.Typography.subsectionTitle
            }
        }
    }

    init(
        _ title: String,
        style: Style = .section,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.style = style
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(style.font)
                .foregroundColor(.primary)

            Spacer()

            trailing()
        }
    }
}

// MARK: - Convenience initializers

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, style: Style = .section) {
        self.init(title, style: style, trailing: { EmptyView() })
    }
}

// MARK: - Trailing link helper

/// Compact "See All" / "Customize" style button used in the trailing slot.
struct SectionHeaderLink: View {
    let title: String
    var icon: String = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: icon)
                    .font(.caption)
            }
            .foregroundColor(.appPrimary)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        SectionHeader("Summary")
        SectionHeader("Categories") {
            SectionHeaderLink(title: "See All") {}
        }
        SectionHeader("Statistics", style: .page)
        SectionHeader("Due Soon", style: .subsection)
    }
    .padding()
}
