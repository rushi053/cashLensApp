import SwiftUI
import Foundation
import StoreKit
import UserNotifications

/// Profile / Settings hub — the **You** tab root.
///
/// **Information architecture (top → bottom):**
///   1. Compact profile header (avatar + tap-to-edit name).
///   2. Pro card (active or upgrade).
///   3. **Backup warning banner** — only shown when backup health is not `.good`.
///   4. **General** — pure preferences (Currency / Default Time Frame / Siri).
///   5. **Privacy & Security** — App Lock toggle + grace window + Privacy dashboard.
///   6. **Personalization** — Theme & Appearance studio + App Icon (Pro).
///   7. **Manage** — navigation rows to dedicated managers (Budgets / Categories /
///      Subscriptions), each with a live count badge. Split off from General
///      because these are screens-of-data, not set-and-forget values.
///   8. **Notifications** — a single row presenting `NotificationsSettingsView` as a sheet.
///   9. **Data** — Backup Health card + Export / Import / Clear.
///  10. **About** — Support / Rate / Restore Purchases (free users) / About +
///      community icon row + version footer.
///
/// **Design intent:** Each section has a single purpose so the page scans
/// top-to-bottom in calm groups instead of 10+ rows of mixed concerns.
/// Pickers use `Menu` rather than inline accordions for native, glitch-free
/// dropdowns.
///
/// NOTE: no root `NavigationView`/`NavigationStack` — Privacy and
/// Notifications are sheets (same as Budgets / Categories). A root
/// nav controller under TabView caused permanent tab-switch stutter
/// after the first visit to You.
struct ProfileView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var subscriptionViewModel: SubscriptionViewModel
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var appIconStore: AppIconStore
    /// App Lock is app-global state (the overlay mounts in
    /// `CashLensApp`), so Profile observes the shared manager rather
    /// than owning any lock state itself.
    @ObservedObject private var appLockManager = AppLockManager.shared

    @State private var isEditingName = false
    @FocusState private var nameFieldFocused: Bool
    @State private var tempUserName = ""

    @State private var showingPaywall = false
    @State private var showingBudgetList = false
    @State private var showingSubscriptions = false
    @State private var showingCategories = false
    @State private var showingCurrencyPicker = false
    @State private var showingAboutSheet = false
    @State private var showingExportSheet = false
    @State private var showingDonationSheet = false
    @State private var showingImportSheet = false
    @State private var showingThemePicker = false
    @State private var showingAppIconPicker = false
    @State private var showingSiriTips = false
    @State private var showingPrivacy = false
    @State private var showingNotifications = false

    /// Shown when enabling App Lock fails its required authentication
    /// (no passcode set, or the user cancelled the prompt).
    @State private var showingAppLockEnableFailed = false

    /// Cached badge / backup-card numbers. PERF: reading
    /// `viewModel.expenses.count` / filtering budgets & subscriptions
    /// inside `body` re-walked those arrays on every EnvironmentObject
    /// invalidation — including while You was off-screen after the
    /// first visit. Refresh only on appear + targeted publishes.
    @State private var cachedExpenseCount: Int = 0
    @State private var cachedActiveBudgetCount: Int = 0
    @State private var cachedActiveSubCount: Int = 0
    @State private var cachedCustomCategoryCount: Int = 0
    /// Gates badge-cache refreshes while this view is on screen.
    /// MainTabView also unmounts Profile when You isn't selected —
    /// this is a second line of defense for sheet presentations.
    @State private var isYouVisible = false

    /// Restore Purchases (About section, free users only). The row is
    /// the standard escape hatch for "I paid on my old phone" — it
    /// used to exist only inside the paywall, which is exactly the
    /// screen a previous purchaser doesn't want to open.
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String? = nil

    // Reminder + Smart Insights state lives in `NotificationsSettingsView`
    // (the pushed sub-page). We only need the four boolean toggles here
    // to render the live "N active" badge on the Notifications row;
    // `@AppStorage` keeps these values in sync with the sub-page via
    // UserDefaults, so the badge updates the moment a toggle is flipped.
    @AppStorage(UserDefaultsKeys.weeklySummaryEnabled) private var weeklySummaryEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.monthlyDigestEnabled) private var monthlyDigestEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.backupReminderEnabled) private var backupReminderEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.smartInsightsEnabled) private var smartInsightsEnabled: Bool = false

    /// Backup metadata is held in `@State` (not read inline from UserDefaults)
    /// so SwiftUI knows to re-render the backup banner + Backup Health card
    /// the moment a successful export writes new values. The two reload
    /// triggers wired up in `body` (`.onChange(of: showingExportSheet)` and
    /// `UserDefaults.didChangeNotification`) keep this in sync without
    /// requiring the user to leave and re-enter Profile.
    @State private var lastBackupDate: Date? = nil
    @State private var totalBackupCount: Int = 0

    private enum ActiveAlert: Identifiable {
        case clearAllData

        var id: String {
            switch self {
            case .clearAllData: return "clearAllData"
            }
        }
    }

    @State private var activeAlert: ActiveAlert?

    /// Static — the bundle version can't change while the app runs, so
    /// there's no reason to re-read the info dictionary on every redraw.
    private static let versionString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }()

    // MARK: - Body

    var body: some View {
        // PERF: NO root `NavigationView` / `NavigationStack`.
        // TabView keeps visited tabs mounted for the session. A root
        // nav controller on You stayed alive after the first visit and
        // re-laid out on every later tab switch — the exact "smooth
        // until I open You, then everything stutters" report. Privacy
        // and Notifications are sheets (same pattern as Budgets /
        // Categories / Subscriptions), so no UINavigationController
        // lives under the tab bar. Matches Insights, which never had
        // a nav wrapper for the same reason.
        ScrollView {
            VStack(spacing: Theme.Spacing.xxl) {
                HStack {
                    Text("You")
                        .font(Theme.Typography.pageTitle)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.top, Theme.Spacing.sm)

                profileHeader
                proSection
                backupBanner
                generalSection
                privacySection
                personalizationSection
                manageSection
                notificationsSection
                dataSection
                aboutSection
                versionFooter
            }
            .padding()
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Color.systemBackground)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .clearAllData:
                return Alert(
                    title: Text("Clear All Data"),
                    message: Text("Are you sure you want to delete ALL your data? This includes expenses, subscriptions, custom categories, and deleted category preferences. This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete All")) {
                        withAnimation {
                            viewModel.clearAllData()
                        }
                        HapticManager.shared.heavyTap()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear {
            isYouVisible = true
            tempUserName = viewModel.userName
            reloadBackupMetadata()
            refreshBadgeCaches()
        }
        .onDisappear {
            isYouVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .backupMetadataDidChange)) { _ in
            reloadBackupMetadata()
        }
        // Keep Manage-row badges current without walking arrays inside
        // `body`. Skip while You is off-screen so a save on Today
        // doesn't re-diff the entire settings tree mid tab-switch.
        .onReceive(viewModel.$expenses) { expenses in
            guard isYouVisible else { return }
            let count = expenses.count
            if count != cachedExpenseCount { cachedExpenseCount = count }
        }
        .onReceive(budgetViewModel.$budgets) { _ in
            guard isYouVisible else { return }
            let count = budgetViewModel.activeBudgets.count
            if count != cachedActiveBudgetCount { cachedActiveBudgetCount = count }
        }
        .onReceive(subscriptionViewModel.$subscriptions) { _ in
            guard isYouVisible else { return }
            let count = subscriptionViewModel.activeSubscriptionsCount
            if count != cachedActiveSubCount { cachedActiveSubCount = count }
        }
        .onReceive(categoryViewModel.$customCategories) { cats in
            guard isYouVisible else { return }
            let count = cats.count
            if count != cachedCustomCategoryCount { cachedCustomCategoryCount = count }
        }
        .sheet(isPresented: $showingCurrencyPicker) {
            CurrencyPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingThemePicker) {
            AppearanceStudioView()
                .environmentObject(themeStore)
                .environmentObject(proManager)
                .environmentObject(appIconStore)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingAppIconPicker) {
            AppIconPickerView()
                .environmentObject(appIconStore)
                .environmentObject(proManager)
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyDashboardView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationsSettingsView()
                .environmentObject(viewModel)
                .environmentObject(proManager)
        }
    }

    private func refreshBadgeCaches() {
        cachedExpenseCount = viewModel.expenses.count
        cachedActiveBudgetCount = budgetViewModel.activeBudgets.count
        cachedActiveSubCount = subscriptionViewModel.activeSubscriptionsCount
        cachedCustomCategoryCount = categoryViewModel.customCategories.count
    }

    /// Pulls the latest backup metadata into `@State` so the banner + Backup
    /// Health card re-render. Called from `.onAppear` and whenever
    /// `.backupMetadataDidChange` fires (posted by the backup exporter /
    /// importer). Updates are gated to avoid a no-op state assignment that
    /// would still invalidate the view tree.
    private func reloadBackupMetadata() {
        let newDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastBackupDate) as? Date
        let newCount = UserDefaults.standard.integer(forKey: UserDefaultsKeys.totalBackupCount)
        let priorCount = totalBackupCount
        let dateChanged = newDate != lastBackupDate
        let countChanged = newCount != totalBackupCount
        guard dateChanged || countChanged else { return }
        withAnimation(Theme.Motion.snappy) {
            if dateChanged { lastBackupDate = newDate }
            if countChanged { totalBackupCount = newCount }
        }
        if newCount > priorCount {
            HapticManager.shared.success()
        }
    }

    // MARK: - Profile Header

    /// Compact header: 72 pt avatar, tappable name with inline pencil chip.
    /// In-place edit uses `@FocusState` so the keyboard auto-presents and a Done
    /// chip replaces the pencil. No more "Edit Profile" pill — the name itself is
    /// the affordance.
    private var profileHeader: some View {
        // Compact horizontal treatment for the tab-root presentation
        // — avatar left, name right. The old vertical "centered hero"
        // shape was right when Profile was a sheet you opened
        // intentionally; as a permanent tab you want fast scanning,
        // not a portrait.
        HStack(spacing: Theme.Spacing.md + 2) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 54, height: 54)
                Text(String(viewModel.userName.prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            if isEditingName {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Your Name", text: $tempUserName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm + 2)
                        .background(Color.secondarySystemBackground)
                        .clipShape(Capsule())
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { saveName() }

                    Button(action: saveName) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.appPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                // Pencil glyph beside the name instead of the old
                // "Tap to edit" caption line — the review called the
                // caption noisy for a once-in-a-lifetime action; the
                // glyph carries the affordance quietly.
                Button(action: beginEditingName) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(viewModel.userName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Edit name")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.snappy, value: isEditingName)
    }

    private func beginEditingName() {
        HapticManager.shared.lightTap()
        tempUserName = viewModel.userName
        isEditingName = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            nameFieldFocused = true
        }
    }

    private func saveName() {
        let trimmed = tempUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            viewModel.userName = trimmed
        } else {
            tempUserName = viewModel.userName
        }
        nameFieldFocused = false
        isEditingName = false
        HapticManager.shared.mediumTap()
    }

    // MARK: - Pro Section

    @ViewBuilder
    private var proSection: some View {
        if proManager.isPro {
            proActiveCard
        } else {
            proUpgradeCard
        }
    }

    private var proActiveCard: some View {
        HStack(spacing: Theme.Spacing.md + 2) {
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("CashLens Pro")
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Text("All features unlocked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Active")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs + 2)
                .background(Color.appPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding()
        .cardSurface(radius: Theme.Radius.hero)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(Color.appPrimary.opacity(0.30), lineWidth: 1)
        )
    }

    private var proUpgradeCard: some View {
        Button {
            HapticManager.shared.mediumTap()
            showingPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.md + 2) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.appPrimary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Upgrade to Pro")
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(.primary)
                    Text("Unlimited budgets, receipts, PDF reports & more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appPrimary)
            }
            .padding()
            .cardSurface(
                radius: Theme.Radius.hero,
                fill: Color.appPrimary.opacity(0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .stroke(Color.appPrimary.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Backup warning banner

    /// Slim contextual banner shown only when backup health is not `.good`.
    /// Surfaces the most critical signal at the top of Settings instead of
    /// burying it at the bottom; tap → opens the export sheet directly.
    @ViewBuilder
    private var backupBanner: some View {
        let status = backupHealthStatus
        if status != .good {
            Button(action: {
                HapticManager.shared.mediumTap()
                showingExportSheet = true
            }) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(status.color.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: status.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(status.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(status.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text("Backup")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(status.color)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(status.color.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .stroke(status.color.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - General

    /// Pure preferences only — values the user sets once and the rest
    /// of the app reads. Navigation-style rows (managers, sub-pages)
    /// live in the dedicated `manageSection` below so this group
    /// stays scannable.
    private var generalSection: some View {
        // v2 polish: each settings section is now ONE elevated card
        // with hairline-separated bare rows (the iOS Settings-app
        // grouping). The old "every row is its own card" treatment
        // produced ~12 stacked cards on the You tab — visually noisy
        // and inconsistent with the rest of iOS.
        SettingsGroup(title: "General") {
            currencyRow
            timeFrameMenuRow
            siriShortcutsRow
        }
        .sheet(isPresented: $showingSiriTips) {
            SiriShortcutsTipsView()
        }
    }

    /// Discovery row for the zero-setup Siri phrases (`CashLensShortcuts`).
    /// Free feature — capture is never paywalled.
    private var siriShortcutsRow: some View {
        SettingsRow(
            icon: "waveform",
            title: "Siri & Shortcuts",
            subtitle: "\u{201C}Log an expense in CashLens\u{201D}",
            style: .bare
        )
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingSiriTips = true
        }
    }

    // MARK: - Privacy & Security

    /// App Lock (free — privacy features are a brand statement, not a
    /// paywall) + the privacy dashboard. Sits right under General so
    /// the app's core promise is visible without scrolling past the
    /// feature managers.
    private var privacySection: some View {
        SettingsGroup(title: "Privacy & Security") {
            appLockToggleRow
            if appLockManager.isEnabled {
                appLockGraceRow
            }
            privacyDashboardRow
        }
        // Attached here (not on the ScrollView) so it can't collide
        // with the `alert(item:)` that owns the clear-all-data flow.
        .alert("Couldn't Turn On App Lock", isPresented: $showingAppLockEnableFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("CashLens needs \(AppLockManager.unlockMethodName) or a device passcode to lock the app. Verify once to turn it on.")
        }
        .animation(Theme.Motion.snappy, value: appLockManager.isEnabled)
    }

    /// Face ID / Touch ID / Optic ID naming is resolved from the
    /// device's actual biometry; devices with no biometrics read
    /// "Passcode". Enabling requires one successful authentication
    /// first so nobody can lock themselves out.
    private var appLockToggleRow: some View {
        SettingsRow(
            icon: AppLockManager.unlockMethodSymbol,
            title: "App Lock",
            subtitle: "Require \(AppLockManager.unlockMethodName) when you open CashLens.",
            showsChevron: false,
            style: .bare
        ) {
            Toggle("", isOn: Binding(
                get: { appLockManager.isEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    if newValue {
                        Task {
                            let ok = await appLockManager.enableAfterAuthentication()
                            if !ok { showingAppLockEnableFailed = true }
                        }
                    } else {
                        appLockManager.disable()
                    }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    /// Grace window picker — how long a backgrounded app stays
    /// unlocked. `Menu` for the native dropdown, same as Appearance.
    private var appLockGraceRow: some View {
        Menu {
            ForEach(AppLockManager.GracePeriod.allCases) { period in
                Button {
                    HapticManager.shared.lightTap()
                    appLockManager.gracePeriod = period
                } label: {
                    if appLockManager.gracePeriod == period {
                        Label(period.displayName, systemImage: "checkmark")
                    } else {
                        Text(period.displayName)
                    }
                }
            }
        } label: {
            SettingsRow(icon: "clock.fill", title: "Require After", showsChevron: false, style: .bare) {
                HStack(spacing: 4) {
                    SettingsRowValue(text: appLockManager.gracePeriod.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var privacyDashboardRow: some View {
        SettingsRow(
            icon: "hand.raised.fill",
            title: "Privacy",
            showsChevron: true,
            style: .bare
        ) {
            SettingsRowValue(text: "On-device")
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingPrivacy = true
        }
    }

    // MARK: - Manage

    /// Navigation-style rows that open dedicated managers for the
    /// app's three first-class collections. Surfacing `Manage
    /// Categories` here closes a real discoverability gap — it used
    /// to be reachable only by drilling into the category picker
    /// inside Add Expense.
    private var manageSection: some View {
        SettingsGroup(title: "Manage") {
            budgetManagementRow
            categoriesRow
            subscriptionsRow
        }
        .sheet(isPresented: $showingBudgetList) {
            BudgetListView()
                .environmentObject(budgetViewModel)
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(proManager)
        }
        .sheet(isPresented: $showingCategories) {
            ManageCategoriesView()
                .environmentObject(categoryViewModel)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingSubscriptions) {
            // No NavigationView wrapper — `SubscriptionsView` ships
            // its own custom page header and presents its own
            // Add/Edit sheets internally. Wrapping it would just
            // stack an empty nav-bar shelf above the title.
            SubscriptionsView()
                .presentationDragIndicator(.visible)
        }
    }

    /// v2: Subscriptions used to be a top-level tab. After the IA
    /// audit it's been demoted — most users glance at recurring bills
    /// weekly, not daily, so it doesn't earn 25% of the tab bar.
    /// It now lives under "You → Subscriptions" (manage list) and
    /// is also reachable as a filter chip inside the Activity tab.
    private var subscriptionsRow: some View {
        SettingsRow(icon: "creditcard.and.123", title: "Subscriptions", style: .bare) {
            // Live count badge — matches the Budgets ("N active") and
            // Categories ("N custom") rows so all three Manage rows
            // answer "is there anything in here?" without a tap.
            if cachedActiveSubCount > 0 {
                Text("\(cachedActiveSubCount) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingSubscriptions = true
        }
    }

    /// Categories management — newly surfaced from Settings (the screen
    /// itself has always existed; it was just buried inside the Add
    /// Expense category picker). Default + custom categories, with the
    /// existing swipe-to-delete + restore flow.
    private var categoriesRow: some View {
        SettingsRow(icon: "square.grid.2x2.fill", title: "Categories", style: .bare) {
            if cachedCustomCategoryCount > 0 {
                Text("\(cachedCustomCategoryCount) custom")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingCategories = true
        }
    }

    private var currencyRow: some View {
        SettingsRow(icon: "dollarsign.circle.fill", title: "Default Currency", style: .bare) {
            SettingsRowValue(text: "\(viewModel.selectedCurrency.symbol) \(viewModel.selectedCurrency.rawValue)")
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingCurrencyPicker.toggle()
        }
    }

    /// Default time frame picker via `Menu` so iOS owns the dropdown.
    private var timeFrameMenuRow: some View {
        Menu {
            ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                Button {
                    HapticManager.shared.lightTap()
                    viewModel.defaultHomeTimeFrame = timeFrame
                } label: {
                    if viewModel.defaultHomeTimeFrame == timeFrame {
                        Label(timeFrame.rawValue, systemImage: "checkmark")
                    } else {
                        Text(timeFrame.rawValue)
                    }
                }
            }
        } label: {
            SettingsRow(icon: "calendar.badge.clock", title: "Default Time Frame", showsChevron: false, style: .bare) {
                HStack(spacing: 4) {
                    SettingsRowValue(text: viewModel.defaultHomeTimeFrame.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var budgetManagementRow: some View {
        SettingsRow(icon: "target", title: "Manage Budgets", style: .bare) {
            if cachedActiveBudgetCount > 0 {
                Text("\(cachedActiveBudgetCount) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            // One overall budget is free — the list itself handles
            // the "add another" Pro lock, so everyone gets in.
            showingBudgetList = true
        }
    }

    // MARK: - Personalization

    /// Personalization controls. The Theme & Appearance row opens the
    /// unified Appearance studio (mode + accent theme + matching icon);
    /// the App Icon row keeps its dedicated full-catalog picker. The old
    /// standalone light/dark Menu row in General was folded into the
    /// studio so "how the app looks" lives in exactly one place.
    private var personalizationSection: some View {
        SettingsGroup(title: "Personalization") {
            themeAppearanceRow
            appIconRow
        }
    }

    /// Theme & Appearance row. Trailing slot shows a duotone swatch in the
    /// active theme's color pair plus the theme name so the user can see
    /// what's applied at a glance. No Pro chip here — the mode selector
    /// inside is free for everyone, and theme gating happens on Apply.
    private var themeAppearanceRow: some View {
        SettingsRow(icon: "paintpalette.fill", title: "Theme & Appearance", showsChevron: true, style: .bare) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(themeStore.currentTheme.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Circle()
                    .fill(themeStore.currentTheme.heroGradient)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.lightTap()
            // Open the studio for everyone — free users can switch mode,
            // preview themes, and discover the Pro upsell from inside,
            // which is a higher-converting moment than dropping them
            // straight into the paywall.
            showingThemePicker = true
        }
    }

    /// App Icon row. Trailing slot shows a tiny rounded preview of the active
    /// icon plus its name so the user can spot-check at a glance. Hidden
    /// entirely on devices that don't support alternate icons (vanishingly
    /// rare, but `supportsAlternateIcons` is the official guard).
    @ViewBuilder
    private var appIconRow: some View {
        if UIApplication.shared.supportsAlternateIcons {
            SettingsRow(icon: "app.badge.fill", title: "App Icon", showsChevron: true, style: .bare) {
                HStack(spacing: Theme.Spacing.sm) {
                    if proManager.isPro {
                        Text(appIconStore.currentIcon.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Image(appIconStore.currentIcon.previewAssetName)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    } else {
                        proLockChip
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticManager.shared.lightTap()
                showingAppIconPicker = true
            }
        }
    }

    /// Reusable Pro lock chip used by both Personalization rows so the
    /// non-Pro state stays visually consistent.
    private var proLockChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Pro")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.appPrimary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
    }

    // MARK: - Notifications

    /// Single nav row that hides the 4–9 reminder + insight rows
    /// behind a focused sub-page. The trailing value shows the live
    /// "N active" count so the state is glanceable without opening
    /// the sub-page; tapping presents the dedicated
    /// `NotificationsSettingsView` sheet (no root nav push — see
    /// the body PERF note).
    private var notificationsSection: some View {
        SettingsGroup(title: "Notifications") {
            SettingsRow(
                icon: "bell.fill",
                title: "Reminders & Insights",
                showsChevron: true,
                style: .bare
            ) {
                SettingsRowValue(text: activeNotificationsLabel)
            }
            .onTapGesture {
                HapticManager.shared.lightTap()
                showingNotifications = true
            }
        }
    }

    /// "Off" when nothing's enabled, "1 active" / "3 active" otherwise.
    /// Driven by the four `@AppStorage` booleans that `NotificationsSettingsView`
    /// also writes to, so this stays live without notification glue.
    private var activeNotificationsLabel: String {
        let count = [
            weeklySummaryEnabled,
            monthlyDigestEnabled,
            backupReminderEnabled,
            smartInsightsEnabled
        ].filter { $0 }.count

        if count == 0 { return "Off" }
        return "\(count) active"
    }

    // MARK: - Data section

    /// Combines export / import / clear-all + the full Backup Health card +
    /// info note. Backup-related settings now live together in one place
    /// instead of being split across two sections.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Section title + backup-health badge ride above the
            // grouped card so the page-level "Data" header has the
            // same hierarchy as Preferences / Reminders / About.
            HStack {
                Text("DATA")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundColor(.secondary)
                Spacer()
                backupHealthBadge
            }
            .padding(.horizontal, Theme.Spacing.md)

            backupHealthCard

            VStack(spacing: 0) {
                SettingsRow(icon: "square.and.arrow.up.fill", title: "Export Data", style: .bare)
                    .onTapGesture {
                        HapticManager.shared.lightTap()
                        showingExportSheet = true
                    }
                Divider().padding(.leading, Theme.Spacing.lg + 30 + Theme.Spacing.md)
                SettingsRow(icon: "square.and.arrow.down.fill", title: "Import Data", style: .bare)
                    .onTapGesture {
                        HapticManager.shared.lightTap()
                        showingImportSheet = true
                    }
                Divider().padding(.leading, Theme.Spacing.lg + 30 + Theme.Spacing.md)
                SettingsRowDestructive(icon: "trash.fill", title: "Clear All Data", style: .bare)
                    .onTapGesture {
                        HapticManager.shared.mediumTap()
                        activeAlert = .clearAllData
                    }
            }
            .cardSurface()

            HStack(alignment: .top, spacing: Theme.Spacing.sm + 2) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("Your data lives only on this device. Regular exports keep your history safe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportDataView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportDataView()
                .environmentObject(viewModel)
        }
    }

    // MARK: - About section

    /// Bottom-of-page about: support / about / community as a single-row icon
    /// strip. Replaces the previous 3 full-width social tiles which dominated
    /// the screen, and absorbs the "Support the App" row that previously lived
    /// in Settings.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SettingsGroup(title: "About") {
                SettingsRow(icon: "star.fill", iconTint: .yellow, title: "Rate CashLens", style: .bare)
                    .onTapGesture {
                        HapticManager.shared.lightTap()
                        openWriteReview()
                    }

                SettingsRow(icon: "heart.fill", iconTint: .pink, title: "Support the App", style: .bare)
                    .onTapGesture {
                        HapticManager.shared.lightTap()
                        showingDonationSheet = true
                    }

                // Always visible (Guideline 3.1.1): even a user who is
                // currently Pro via a donor grant may need to restore a
                // real StoreKit purchase — e.g. after moving devices.
                restorePurchasesRow

                SettingsRow(icon: "doc.text.fill", title: "About CashLens", style: .bare)
                    .onTapGesture {
                        HapticManager.shared.lightTap()
                        showingAboutSheet = true
                    }
            }

            communityIconRow
                .padding(.top, Theme.Spacing.md)
        }
        .sheet(isPresented: $showingAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showingDonationSheet) {
            NavigationView { DonationView() }
        }
        // Attached here (not on the ScrollView) so it can't collide
        // with the `alert(item:)` that owns the clear-all-data flow.
        .alert("Restore Purchases", isPresented: Binding(
            get: { restoreResultMessage != nil },
            set: { if !$0 { restoreResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { restoreResultMessage = nil }
        } message: {
            Text(restoreResultMessage ?? "")
        }
    }

    private var restorePurchasesRow: some View {
        SettingsRow(
            icon: "arrow.clockwise",
            title: "Restore Purchases",
            subtitle: proManager.isPro ? nil : "Already Pro on another device?",
            showsChevron: false,
            style: .bare
        ) {
            if isRestoringPurchases {
                ProgressView()
            }
        }
        .onTapGesture {
            guard !isRestoringPurchases else { return }
            HapticManager.shared.lightTap()
            isRestoringPurchases = true
            let wasProBefore = proManager.isPro
            Task {
                await proManager.restorePurchases()
                isRestoringPurchases = false
                if proManager.isPro {
                    HapticManager.shared.success()
                    restoreResultMessage = wasProBefore
                        ? "Your purchases are up to date — Pro is active."
                        : "Pro is back — everything is unlocked."
                } else {
                    restoreResultMessage = "No previous purchases were found for this Apple ID."
                }
            }
        }
    }

    private func openWriteReview() {
        // Same App Store ID used by the in-app feedback flow.
        guard let url = URL(string: "https://apps.apple.com/app/id6743153951?action=write-review") else { return }
        UIApplication.shared.open(url)
    }

    /// Compact 3-up community icon row. Way less visual real estate than the
    /// previous stacked tiles, but still discoverable + brand-tinted.
    private var communityIconRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Join the community")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, Theme.Spacing.xs)

            HStack(spacing: Theme.Spacing.md) {
                communityCircleButton(
                    icon: "camera.fill",
                    title: "Instagram",
                    background: AnyShapeStyle(Color.pink)
                ) { openSocialMedia(.instagram) }

                communityCircleButton(
                    icon: "bird.fill",
                    title: "X",
                    background: AnyShapeStyle(Color.black)
                ) { openSocialMedia(.twitter) }

                communityCircleButton(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Reddit",
                    background: AnyShapeStyle(Color.orange)
                ) { openSocialMedia(.reddit) }
            }
        }
    }

    private func communityCircleButton(
        icon: String,
        title: String,
        background: AnyShapeStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.shared.lightTap()
            action()
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(background)
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    enum SocialPlatform {
        case instagram, twitter, reddit
    }

    private func openSocialMedia(_ platform: SocialPlatform) {
        let urlString: String
        switch platform {
        case .instagram: urlString = "https://instagram.com/cashlensapp"
        case .twitter:   urlString = "https://x.com/cashlensapp"
        case .reddit:    urlString = "https://www.reddit.com/r/cashlens/s/Z36oUPfZ3j"
        }

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Version footer

    /// Tiny footer text — replaces the previous full "Version" settings row which
    /// wasted a tappable-row slot on a non-tappable label.
    private var versionFooter: some View {
        HStack {
            Spacer()
            Text("CashLens · v\(Self.versionString)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Backup Health card

    private var backupHealthBadge: some View {
        let status = backupHealthStatus

        return HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Text(status.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(status.color)
        }
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var backupHealthCard: some View {
        let status = backupHealthStatus
        let lastBackup = lastBackupDate
        let backupCount = totalBackupCount

        return VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xl) {
                ZStack {
                    Circle()
                        .stroke(status.color.opacity(0.3), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: status.ringProgress)
                        .stroke(status.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: status.icon)
                        .font(.system(size: 24))
                        .foregroundColor(status.color)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs + 2) {
                    Text(status.title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(status.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 0) {
                backupStatCell(
                    title: "Last Backup",
                    value: lastBackup.map(formatBackupDate) ?? "Never",
                    isCritical: lastBackup == nil
                )

                backupStatDivider

                backupStatCell(title: "Total Backups", value: "\(backupCount)")

                backupStatDivider

                backupStatCell(title: "Expenses", value: "\(cachedExpenseCount)")
            }

            if status != .good {
                Button(action: {
                    HapticManager.shared.mediumTap()
                    showingExportSheet = true
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise.icloud")
                            .font(.system(size: 16, weight: .semibold))

                        Text("Backup Now")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding()
        .cardSurface(radius: Theme.Radius.chip)
    }

    private func backupStatCell(title: String, value: String, isCritical: Bool = false) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isCritical ? .red : .primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private var backupStatDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 30)
    }

    // MARK: - Backup Health Status

    private enum BackupHealthStatus: Equatable {
        case good
        case okay
        case needsAttention
        case critical

        var label: String {
            switch self {
            case .good: return "Good"
            case .okay: return "OK"
            case .needsAttention: return "Needs Attention"
            case .critical: return "Critical"
            }
        }

        var color: Color {
            switch self {
            case .good: return .green
            case .okay, .needsAttention: return .orange
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .good: return "checkmark.shield.fill"
            case .okay: return "clock.badge.checkmark.fill"
            case .needsAttention: return "exclamationmark.shield.fill"
            case .critical: return "xmark.shield.fill"
            }
        }

        var title: String {
            switch self {
            case .good: return "Your data is safe"
            case .okay: return "Backup recommended"
            case .needsAttention: return "Backup needed"
            case .critical: return "No backup found"
            }
        }

        var subtitle: String {
            switch self {
            case .good: return "You've backed up recently. Great job!"
            case .okay: return "It's been a while since your last backup."
            case .needsAttention: return "Your data hasn't been backed up in over a month."
            case .critical: return "Your data exists only on this device. Please backup!"
            }
        }

        var ringProgress: CGFloat {
            switch self {
            case .good: return 1.0
            case .okay: return 0.65
            case .needsAttention: return 0.35
            case .critical: return 0.1
            }
        }
    }

    private var backupHealthStatus: BackupHealthStatus {
        guard let lastBackup = lastBackupDate else {
            return .critical
        }

        let daysSinceBackup = Calendar.current.dateComponents([.day], from: lastBackup, to: Date()).day ?? Int.max

        switch daysSinceBackup {
        case 0...7:   return .good
        case 8...14:  return .okay
        case 15...30: return .needsAttention
        default:      return .critical
        }
    }

    /// Hoisted so the backup card doesn't allocate a fresh formatter on
    /// every render. Medium date style is locale-stable; main-actor only.
    private static let backupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func formatBackupDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days < 7 {
                return "\(days) days ago"
            } else {
                return Self.backupDateFormatter.string(from: date)
            }
        }
    }
}

// MARK: - Preview

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(ExpenseViewModel())
            .environmentObject(ProManager.shared)
            .environmentObject(BudgetViewModel())
            .environmentObject(SubscriptionViewModel())
            .environmentObject(CategoryViewModel())
    }
}
