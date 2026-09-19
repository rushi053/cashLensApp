import SwiftUI

// MARK: - You on regular width (iPad, iPhone Duo inner display)
//
// The iPhone You tab is ten grouped cards in one column. Phase A kept
// that column at 680pt on iPad, which left a third of the screen empty
// and still needed a long scroll. Here the same groups split by job:
//
//   ┌ You ──────────────────────────────────────────────────┐
//   │ ┌ identity & status ─────┐  ┌ preferences ──────────┐ │
//   │ │ profile header         │  │ General               │ │
//   │ │ Pro card               │  │ Privacy & Security    │ │
//   │ │ backup banner (if any) │  │ Personalization       │ │
//   │ │ Manage (budgets, …)    │  │ Notifications         │ │
//   │ │ About                  │  │ Data (backup health…) │ │
//   │ │ Developer (DEBUG)      │  │                       │ │
//   │ └────────────────────────┘  └───────────────────────┘ │
//   │ version footer                                        │
//
// Leading column: who you are, what you have, what you manage. Trailing
// column: values you set once. Both columns stay ≤ ~520pt so rows keep
// the measure the iPhone design was tuned for.
//
// Why not a sidebar + detail pane: every sub-screen (Budgets,
// Subscriptions, Categories, Export, Import, About, Notifications,
// Privacy, Appearance, App Icon) owns a `SheetHeader` with a close
// button and calls `dismiss()`. Hosting them inline would need the
// `onDismissRequest` treatment `AddExpenseView` has. Until then they are
// form-sized cards on regular width (see the `.largeScreenFormSheet`
// calls in `ProfileView`), which already reads as "settings on iPad"
// rather than a full-height phone sheet.
//
// Only reached from `ProfileView.body` when `horizontalSizeClass ==
// .regular`. Sheets, alerts and caches are unchanged and shared.
extension ProfileView {

    private var usesTwoColumns: Bool {
        guard largeScreenMeasuredWidth > 0 else { return true }
        return largeScreenMeasuredWidth >= LargeScreenLayout.twoColumnMinimumWidth
    }

    /// Two 520pt columns plus the gutter; anything wider is margin.
    private static let contentMaxWidth: CGFloat = 520 * 2 + LargeScreenLayout.columnSpacing

    var largeScreenContent: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            HStack {
                Text("You")
                    .font(Theme.Typography.pageTitle)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.top, Theme.Spacing.sm)

            LargeScreenColumns(twoColumns: usesTwoColumns) {
                VStack(spacing: Theme.Spacing.xxl) {
                    profileHeader
                    proSection
                    backupBanner
                    manageSection
                    aboutSection
                    #if DEBUG
                    developerSection
                    #endif
                }
            } trailing: {
                VStack(spacing: Theme.Spacing.xxl) {
                    generalSection
                    privacySection
                    personalizationSection
                    notificationsSection
                    dataSection
                }
            }

            versionFooter
        }
        .padding(.horizontal, LargeScreenLayout.horizontalPadding)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: Self.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .measureLayoutWidth($largeScreenMeasuredWidth)
    }
}
