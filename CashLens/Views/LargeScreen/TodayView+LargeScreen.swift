import SwiftUI

// MARK: - Today on regular width (iPad, iPhone Duo inner display)
//
// The iPhone Today is one column: header → verdict → the user's ordered
// sections. On a big screen that column either stretches into 1000pt
// cards or (Phase A) sits in a 680pt readable strip with empty margins —
// a "blown-up iPhone" either way. This dashboard uses the width:
//
//   ┌ header ─────────────── [+ Log expense] [customize] ┐
//   │ recap card (when present)                          │
//   │ ┌ verdict / budgets ┐  ┌ summary ─────────────────┐ │
//   │ │                   │  │ week strip               │ │
//   │ └───────────────────┘  │ upcoming subscriptions   │ │
//   │ ┌ recent (6 rows) ──┐  │ insight                  │ │
//   │ └───────────────────┘  └──────────────────────────┘ │
//
// Rules (see docs/LARGE_SCREEN_DESIGN.md):
//   • The verdict stays the first pixel, top-leading.
//   • The user's Customize Today order still decides what appears and
//     in which sequence; Recent (the tall list) is kept under the
//     verdict, everything else fills the trailing column in order. With
//     Recent hidden the sections are dealt alternately instead.
//   • Below `LargeScreenLayout.twoColumnMinimumWidth` (Duo inner
//     portrait, 11" iPad at 50/50) or at accessibility Dynamic Type the
//     two columns stack — same order as the iPhone, wider cards.
//   • The primary action is a placed "Log expense" pill in the header;
//     `MainTabView` hides the floating "+" on regular width.
//
// Only reached from `TodayView.body` when `horizontalSizeClass ==
// .regular`. All state lives on `TodayView`, so folding a Duo or
// dragging a Split View divider only re-arranges the same sections.
extension TodayView {

    private var usesTwoColumns: Bool {
        // Trust regular width before the first measurement so an iPad
        // never flashes one column for a frame.
        guard largeScreenMeasuredWidth > 0 else { return true }
        return largeScreenMeasuredWidth >= LargeScreenLayout.twoColumnMinimumWidth
    }

    /// Sections for the leading column (under the verdict) and the
    /// trailing column, derived from the user's visible order.
    private var dealtSections: (leading: [TodaySectionID], trailing: [TodaySectionID]) {
        let visible = visibleSections
        if visible.contains(.recent) {
            return (
                leading: visible.filter { $0 == .recent },
                trailing: visible.filter { $0 != .recent }
            )
        }
        var leading: [TodaySectionID] = []
        var trailing: [TodaySectionID] = []
        for (index, section) in visible.enumerated() {
            if index % 2 == 0 {
                trailing.append(section)
            } else {
                leading.append(section)
            }
        }
        return (leading, trailing)
    }

    private var leadingSections: [TodaySectionID] { dealtSections.leading }
    private var trailingSections: [TodaySectionID] { dealtSections.trailing }

    /// Recent shows six rows here (three on iPhone) — the point of the
    /// extra height is fewer trips to Activity to check "did I log that?".
    private static let largeScreenRecentLimit = 6

    var largeScreenContent: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            largeScreenHeader
                .modifier(SectionEntrance(order: 0, animate: animateSections))

            if let recapMonth {
                recapReadyCard(for: recapMonth)
                    .modifier(SectionEntrance(order: 1, animate: animateSections))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if viewModel.expenses.isEmpty {
                // Cold start: the first-run hero (rendered by
                // `budgetsSection`) is the only content. Centre it in a
                // form-width column rather than stretching a welcome
                // card across an iPad.
                budgetsSection
                    .frame(maxWidth: LargeScreenLayout.formMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xxxl)
                    .modifier(SectionEntrance(order: 1, animate: animateSections))
            } else {
                LargeScreenColumns(twoColumns: usesTwoColumns) {
                    VStack(spacing: Theme.Spacing.xxl) {
                        budgetsSection
                            .modifier(SectionEntrance(order: 1, animate: animateSections))
                            .sectionScrollTransition()

                        ForEach(Array(leadingSections.enumerated()), id: \.element) { index, section in
                            largeScreenSection(for: section)
                                .modifier(SectionEntrance(order: index + 2, animate: animateSections))
                                .sectionScrollTransition()
                        }
                    }
                } trailing: {
                    VStack(spacing: Theme.Spacing.xxl) {
                        ForEach(Array(trailingSections.enumerated()), id: \.element) { index, section in
                            largeScreenSection(for: section)
                                .modifier(SectionEntrance(order: index + 2, animate: animateSections))
                                .sectionScrollTransition()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, LargeScreenLayout.horizontalPadding(for: largeScreenMeasuredWidth))
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.scrollBottomClearance)
        .frame(maxWidth: LargeScreenLayout.dashboardMaxWidth)
        .frame(maxWidth: .infinity)
        .measureLayoutWidth($largeScreenMeasuredWidth)
        // Same live-edit motion as the compact column when the
        // Customize sheet reorders or hides sections.
        .animation(Theme.Motion.emphasized, value: sectionOrder)
        .animation(Theme.Motion.emphasized, value: hiddenSections)
    }

    // MARK: Header

    /// Greeting + name on the leading edge; the placed primary action
    /// and the Customize disc on the trailing edge. Both controls sit
    /// inside the safe area, so a Duo vertical bar never overlaps them.
    private var largeScreenHeader: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(viewModel.userName)
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hidden on a cold start — the first-run hero already
            // carries the one CTA that moment should have.
            if !viewModel.expenses.isEmpty {
                LargeScreenAddButton(style: .pill, action: onRequestAddExpense)
            }

            Button {
                HapticManager.shared.lightTap()
                showingCustomizeSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Customize Today")
        }
    }

    // MARK: Sections

    /// Same builders as the compact column, except Recent, which shows
    /// more rows here.
    @ViewBuilder
    private func largeScreenSection(for section: TodaySectionID) -> some View {
        if section == .recent {
            largeScreenRecentSection
        } else {
            sectionView(for: section)
        }
    }

    private var largeScreenRecentSection: some View {
        let recent = Array(viewModel.expenses.prefix(Self.largeScreenRecentLimit))
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Recent")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    HapticManager.shared.lightTap()
                    onSeeAllActivity()
                }) {
                    HStack(spacing: 2) {
                        Text("See all")
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(Theme.Typography.caption.weight(.medium))
                    .foregroundColor(.appPrimary)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }

            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { idx, expense in
                    ExpenseCard(
                        expense: expense,
                        viewModel: viewModel,
                        categoryViewModel: categoryViewModel,
                        style: .bare
                    )
                    .equatable()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.lightTap()
                        editingExpense = expense
                    }
                    if idx < recent.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .cardSurface()
        }
    }
}
