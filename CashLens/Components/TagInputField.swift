import SwiftUI

/// The tag input control used on Add / Edit Expense.
///
/// Design goals:
/// - **Glanceable state**: always-visible field card with committed tags as chips.
/// - **Fast entry**: single text field, commit on space / comma / return / tap suggestion.
/// - **Addictive**: live autocomplete, "popular" suggestions below when idle, smooth
///   spring animations on commit, haptics on every action.
/// - **Safe**: silently drops invalid/oversize input via `Tag.normalize`.
struct TagInputField: View {
    @Binding var tags: [String]
    let suggestionStats: TagSuggestionProvider.Stats

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    /// Animation trigger for the newly committed chip.
    @State private var lastCommittedTag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            inputCard
            suggestionOrPopular
        }
    }

    // MARK: - Card (chips + text field)

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            chipFlow
            textField
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md + 2)
        .fieldCard(isFocused: isFocused)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    @ViewBuilder
    private var chipFlow: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            TagFlowLayout(spacing: Theme.Spacing.xs + 2) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(
                        tag,
                        style: .editable,
                        onRemove: { removeTag(tag) }
                    )
                    .transition(.scale.combined(with: .opacity))
                    .matchedGeometryEffect(id: tag, in: chipNamespace)
                }
            }
            .animation(Theme.Motion.tap, value: tags)
        }
    }

    @Namespace private var chipNamespace

    private var textField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "number")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isFocused ? .appPrimary : .secondary)

            TextField(
                tags.isEmpty ? "Add tags — e.g. tokyo-2026, work" : "Add another",
                text: $draft
            )
            .font(.system(size: 15, weight: .medium))
            .focused($isFocused)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .onChange(of: draft) { _, newValue in
                handleDraftChange(newValue)
            }
            .onSubmit { commitDraft() }

            if !draft.isEmpty {
                Button {
                    commitDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Suggestions / Popular row

    @ViewBuilder
    private var suggestionOrPopular: some View {
        let query = Tag.normalize(draft) ?? ""
        let activeSuggestions = TagSuggestionProvider.suggestions(
            for: query,
            allTags: suggestionStats.usageCounts,
            excluding: Set(tags)
        )

        if !activeSuggestions.isEmpty {
            suggestionList(title: "Matches", tags: activeSuggestions, highlight: query)
        } else if isFocused || !tags.isEmpty {
            let recent = suggestionStats.recentTags
                .filter { !tags.contains($0) }
                .prefix(5)
            let popular = suggestionStats.popularTags
                .filter { !tags.contains($0) && !recent.contains($0) }
                .prefix(5)

            if !recent.isEmpty {
                suggestionList(title: "Recent", tags: Array(recent), highlight: nil)
            }
            if !popular.isEmpty {
                suggestionList(title: "Popular", tags: Array(popular), highlight: nil)
            }
        }
    }

    private func suggestionList(title: String, tags: [String], highlight: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(
                            tag,
                            style: .standard,
                            count: suggestionStats.usageCounts[tag],
                            onTap: { commit(tag) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func handleDraftChange(_ newValue: String) {
        guard !newValue.isEmpty else { return }
        // Commit on space or comma to feel chat-like.
        if let last = newValue.last, last == " " || last == "," {
            commitDraft()
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        draft = ""
        guard let normalized = Tag.normalize(trimmed) else { return }
        commit(normalized)
    }

    private func commit(_ tag: String) {
        guard !tags.contains(tag) else {
            HapticManager.shared.warning()
            return
        }
        guard tags.count < Tag.maxPerExpense else {
            HapticManager.shared.warning()
            return
        }

        withAnimation(Theme.Motion.tap) {
            tags.append(tag)
        }
        lastCommittedTag = tag
        HapticManager.shared.lightTap()
        draft = ""
    }

    private func removeTag(_ tag: String) {
        withAnimation(Theme.Motion.tap) {
            tags.removeAll { $0 == tag }
        }
    }
}

// MARK: - Flow Layout

/// Minimal flow layout used by the input card to wrap chips onto multiple lines.
/// Uses SwiftUI's `Layout` (iOS 16+; matches the app's deployment target since
/// other views already use SwiftUI features from that era).
private struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        let result = arrange(subviews: subviews, maxWidth: maxWidth)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Arrangement {
        let frames: [CGRect]
        let size: CGSize
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        var frames: [CGRect] = []
        var rowY: CGFloat = 0
        var rowX: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > maxWidth && rowX > 0 {
                rowY += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: rowX, y: rowY), size: size))
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let totalHeight = rowY + rowHeight
        let usedWidth = frames.map { $0.maxX }.max() ?? 0
        return Arrangement(
            frames: frames,
            size: CGSize(width: usedWidth, height: totalHeight)
        )
    }
}
