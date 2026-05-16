import SwiftUI

/// Presentation-only tag chip. Used on expense cards, in pickers, and in the
/// filter strip. Keeps a single source of truth for tag typography and tinting
/// so every tag in the app reads the same.
struct TagChip: View {
    enum Style {
        /// Tiny inline chip used on `ExpenseCard`.
        case inline
        /// Full-size chip used in filter strips and pickers.
        case standard
        /// Prominent tint used when the chip represents the active filter.
        case selected
        /// Chip inside the tag input field, with a trailing remove button.
        case editable
    }

    let text: String
    let style: Style
    let count: Int?
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?

    init(
        _ text: String,
        style: Style = .standard,
        count: Int? = nil,
        onRemove: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.text = text
        self.style = style
        self.count = count
        self.onRemove = onRemove
        self.onTap = onTap
    }

    var body: some View {
        let (font, hPad, vPad, corner, fg, bg, borderColor, borderWidth) = styleTokens

        let content = HStack(spacing: style == .inline ? 3 : 5) {
            Text(Tag.displayForm(text))
                .font(font)
                .foregroundColor(fg)
                .lineLimit(1)

            if let count, style != .inline, style != .editable {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(fg.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(fg.opacity(0.12))
                    )
            }

            if style == .editable, onRemove != nil {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(fg.opacity(0.75))
                    .padding(.leading, 1)
            }
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )

        if let onRemove, style == .editable {
            Button {
                HapticManager.shared.lightTap()
                onRemove()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else if let onTap {
            Button {
                HapticManager.shared.selectionChanged()
                onTap()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Tokens

    private var styleTokens: (Font, CGFloat, CGFloat, CGFloat, Color, Color, Color, CGFloat) {
        switch style {
        case .inline:
            return (
                .system(size: 10.5, weight: .semibold, design: .rounded),
                6, 2, 6,
                .appPrimary,
                Color.appPrimary.opacity(0.10),
                .clear, 0
            )
        case .standard:
            return (
                .system(size: 13, weight: .semibold, design: .rounded),
                Theme.Spacing.md - 2, Theme.Spacing.xs + 2, Theme.Radius.chip,
                .primary,
                Color.secondarySystemBackground,
                Color.primary.opacity(0.07), Theme.Stroke.thin
            )
        case .selected:
            return (
                .system(size: 13, weight: .semibold, design: .rounded),
                Theme.Spacing.md - 2, Theme.Spacing.xs + 2, Theme.Radius.chip,
                .white,
                Color.appPrimary,
                .clear, 0
            )
        case .editable:
            return (
                .system(size: 13, weight: .semibold, design: .rounded),
                Theme.Spacing.md - 2, Theme.Spacing.xs + 2, Theme.Radius.chip,
                .appPrimary,
                Color.appPrimary.opacity(0.12),
                Color.appPrimary.opacity(0.25), Theme.Stroke.thin
            )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack {
            TagChip("tokyo-2026", style: .inline)
            TagChip("work", style: .inline)
            TagChip("gift", style: .inline)
        }

        HStack {
            TagChip("coffee", style: .standard, count: 34)
            TagChip("commute", style: .standard, count: 12)
        }

        HStack {
            TagChip("tokyo-2026", style: .selected, count: 23)
            TagChip("reimbursable", style: .selected, count: 8)
        }

        HStack {
            TagChip("work", style: .editable, onRemove: {})
            TagChip("lunch", style: .editable, onRemove: {})
        }
    }
    .padding()
}
