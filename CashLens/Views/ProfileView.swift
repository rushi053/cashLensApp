import SwiftUI
import Foundation
import StoreKit
import UserNotifications

/// Profile / Settings hub.
///
/// **Information architecture (top → bottom):**
///   1. Compact profile header (small avatar + tap-to-edit name with pencil chip).
///   2. Pro card (active or upgrade).
///   3. **Backup warning banner** — only shown when backup health is not `.good`,
///      so the most critical signal can't be missed at the bottom of the scroll.
///   4. Preferences (currency / appearance / time frame / budgets).
///   5. Reminders (weekly digest / monthly digest / backup reminder + schedule rows).
///   6. Data (export / import / backup health card / clear all data).
///   7. About (about / support the app / community icon row / version footer).
///
/// **Design intent:** Settings is for persistent preferences, so action-shaped rows
/// like "Support the App" were moved out into the bottom About section.
/// `Appearance` and `Default Time Frame` use `Menu` instead of inline accordion
/// pickers — fewer taps, no layout glitches, more iOS-native.
struct ProfileView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var proManager: ProManager
    @EnvironmentObject var budgetViewModel: BudgetViewModel
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var appIconStore: AppIconStore

    @State private var isEditingName = false
    @FocusState private var nameFieldFocused: Bool
    @State private var tempUserName = ""

    @State private var showingPaywall = false
    @State private var showingBudgetList = false
    @State private var showingCurrencyPicker = false
    @State private var showingAboutSheet = false
    @State private var showingExportSheet = false
    @State private var showingDonationSheet = false
    @State private var showingImportSheet = false
    @State private var showingThemePicker = false
    @State private var showingAppIconPicker = false

    // Weekly summary
    @AppStorage(UserDefaultsKeys.weeklySummaryEnabled) private var weeklySummaryEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.weeklySummaryWeekday) private var weeklySummaryWeekday: Int = 2 // Monday
    @AppStorage(UserDefaultsKeys.weeklySummaryHour) private var weeklySummaryHour: Int = 9
    @AppStorage(UserDefaultsKeys.weeklySummaryMinute) private var weeklySummaryMinute: Int = 0

    @State private var showingWeeklySummarySchedule = false
    @State private var scheduleTempWeekday: Int = 2
    @State private var scheduleTempTime: Date = Date()

    // Monthly digest
    @AppStorage(UserDefaultsKeys.monthlyDigestEnabled) private var monthlyDigestEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.monthlyDigestDayOfMonth) private var monthlyDigestDayOfMonth: Int = 1
    @AppStorage(UserDefaultsKeys.monthlyDigestHour) private var monthlyDigestHour: Int = 9
    @AppStorage(UserDefaultsKeys.monthlyDigestMinute) private var monthlyDigestMinute: Int = 0
    @State private var showingMonthlyDigestSchedule = false
    @State private var monthlyTempDayOfMonth: Int = 1
    @State private var monthlyTempTime: Date = Date()

    // Backup reminder
    @AppStorage(UserDefaultsKeys.backupReminderEnabled) private var backupReminderEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.backupReminderDayOfMonth) private var backupReminderDayOfMonth: Int = 1
    @AppStorage(UserDefaultsKeys.backupReminderHour) private var backupReminderHour: Int = 9
    @AppStorage(UserDefaultsKeys.backupReminderMinute) private var backupReminderMinute: Int = 0
    @State private var showingBackupReminderSchedule = false
    @State private var backupTempDayOfMonth: Int = 1
    @State private var backupTempTime: Date = Date()

    // Smart Insights (Pro). No schedule sub-row — by design it fires Sunday
    // 10 AM in the user's local time and only when the engine has something
    // genuinely interesting to say. Surface area is one toggle so the
    // setting never feels noisy or fiddly.
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
        case notificationPermission

        var id: String {
            switch self {
            case .clearAllData: return "clearAllData"
            case .notificationPermission: return "notificationPermission"
            }
        }
    }

    @State private var activeAlert: ActiveAlert?

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    profileHeader
                    proSection
                    backupBanner
                    preferencesSection
                    personalizationSection
                    remindersSection
                    dataSection
                    aboutSection
                    versionFooter
                }
                .padding()
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("Profile")
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(Theme.Spacing.sm)
                        .background(Color.secondarySystemBackground)
                        .clipShape(Circle())
                }
            )
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
                case .notificationPermission:
                    return Alert(
                        title: Text("Enable Notifications"),
                        message: Text("Please enable notifications in Settings to receive weekly summaries."),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .onAppear {
                tempUserName = viewModel.userName
                scheduleTempWeekday = weeklySummaryWeekday
                scheduleTempTime = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
                reloadBackupMetadata()
            }
            .onChange(of: showingExportSheet) { _, _ in
                reloadBackupMetadata()
            }
            // PERF: Previously this listened to **every**
            // `UserDefaults.didChangeNotification` app-wide. Any
            // unrelated default write — currency change, theme bump,
            // draft autosave on AddExpense, draft autosave on
            // QuickSearch recents, summary preferences toggle, smart
            // insight history, even the digest scheduler's last-fire
            // timestamp — caused a full re-read of backup metadata
            // from UserDefaults while Profile was mounted. We use
            // `backupMetadataDidChange` (posted explicitly by
            // `BackupExporter` / `BackupImporter` whenever they touch
            // the backup keys) so only meaningful events trigger a
            // refresh.
            .onReceive(NotificationCenter.default.publisher(for: .backupMetadataDidChange)) { _ in
                reloadBackupMetadata()
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingThemePicker) {
                ThemePickerView()
                    .environmentObject(themeStore)
                    .environmentObject(proManager)
            }
            .sheet(isPresented: $showingAppIconPicker) {
                AppIconPickerView()
                    .environmentObject(appIconStore)
                    .environmentObject(proManager)
            }
        }
    }

    /// Pulls the latest backup metadata into `@State` so the banner + Backup
    /// Health card re-render. Called from `.onAppear`, `.onChange` of the
    /// export sheet, and on every `UserDefaults.didChangeNotification`.
    /// Updates are gated to avoid a no-op state assignment that would still
    /// invalidate the view tree.
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
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 72, height: 72)
                    .primaryGlow(strength: 0.25)

                Text(String(viewModel.userName.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            if isEditingName {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Your Name", text: $tempUserName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
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
                .padding(.horizontal, Theme.Spacing.xl)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Button(action: beginEditingName) {
                    HStack(spacing: 6) {
                        Text(viewModel.userName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appPrimary)
                            .padding(5)
                            .background(Color.appPrimary.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.top, Theme.Spacing.sm)
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
                    .fill(LinearGradient.appPrimaryDiagonal)
                    .frame(width: 44, height: 44)
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("CashLens Pro")
                    .font(.headline)
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
        .cardSurface(
            radius: Theme.Radius.hero,
            fill: Color.secondarySystemBackground.opacity(0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(Color.appPrimary.opacity(0.4), lineWidth: Theme.Stroke.medium)
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
                        .fill(LinearGradient.appPrimaryDiagonal)
                        .frame(width: 44, height: 44)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Upgrade to Pro")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Budgets, tags, PDF reports & more")
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
                fill: LinearGradient.appPrimarySoft
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .stroke(Color.appPrimary.opacity(0.3), lineWidth: Theme.Stroke.medium
                    )
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

    // MARK: - Preferences

    /// Persistent preferences only (currency, appearance, time frame, budgets).
    /// "Support the App" was moved to the About section since it's an action,
    /// not a preference.
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Preferences")
                .padding(.bottom, Theme.Spacing.xs)

            currencyRow
            appearanceMenuRow
            timeFrameMenuRow
            budgetManagementRow
        }
        .sectionContainer()
        .sheet(isPresented: $showingBudgetList) {
            BudgetListView()
                .environmentObject(budgetViewModel)
                .environmentObject(viewModel)
                .environmentObject(categoryViewModel)
                .environmentObject(proManager)
        }
    }

    private var currencyRow: some View {
        SettingsRow(icon: "dollarsign.circle.fill", title: "Default Currency") {
            SettingsRowValue(text: "\(viewModel.selectedCurrency.symbol) \(viewModel.selectedCurrency.rawValue)")
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            showingCurrencyPicker.toggle()
        }
    }

    /// Appearance picker — uses `Menu` so iOS owns the dropdown.
    /// Replaces the prior inline accordion which added ~50 lines and felt
    /// non-native.
    private var appearanceMenuRow: some View {
        Menu {
            ForEach(ExpenseViewModel.AppearanceMode.allCases, id: \.self) { mode in
                Button {
                    HapticManager.shared.lightTap()
                    viewModel.appearanceMode = mode
                } label: {
                    if viewModel.appearanceMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            SettingsRow(icon: "moon.fill", title: "Appearance", showsChevron: false) {
                HStack(spacing: 4) {
                    SettingsRowValue(text: viewModel.appearanceMode.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Default time frame picker via `Menu` (same rationale as appearance).
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
            SettingsRow(icon: "calendar.badge.clock", title: "Default Time Frame", showsChevron: false) {
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
        SettingsRow(icon: "target", title: "Manage Budgets") {
            if !budgetViewModel.activeBudgets.isEmpty {
                Text("\(budgetViewModel.activeBudgets.count) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            HapticManager.shared.lightTap()
            if proManager.isPro {
                showingBudgetList = true
            } else {
                showingPaywall = true
            }
        }
    }

    // MARK: - Personalization

    /// Pro-gated personalization controls (theme + app icon). Lives between
    /// Preferences and Reminders so it reads as "your visual identity"
    /// without competing with the system-level appearance toggle that stays
    /// in Preferences.
    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Personalization")
                .padding(.bottom, Theme.Spacing.xs)

            colorThemeRow
            appIconRow
        }
        .sectionContainer()
    }

    /// Color Theme row. Trailing slot shows a circular swatch in the active
    /// theme's primary color so the user can see what's applied at a glance,
    /// plus the theme name for clarity. Free users see a "Pro" pill instead.
    private var colorThemeRow: some View {
        SettingsRow(icon: "paintpalette.fill", title: "Color Theme", showsChevron: true) {
            HStack(spacing: Theme.Spacing.sm) {
                if proManager.isPro {
                    Text(themeStore.currentTheme.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(themeStore.currentTheme.primaryColor)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                } else {
                    proLockChip
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.lightTap()
            // Open the picker for everyone — free users can preview themes
            // and discover the Pro upsell from inside the picker, which is
            // a higher-converting moment than dropping them straight into
            // the paywall.
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
            SettingsRow(icon: "app.badge.fill", title: "App Icon", showsChevron: true) {
                HStack(spacing: Theme.Spacing.sm) {
                    if proManager.isPro {
                        Text(appIconStore.currentIcon.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let ui = UIImage(named: appIconStore.currentIcon.previewAssetName) {
                            Image(uiImage: ui)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }
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

    // MARK: - Reminders

    /// Notifications grouped under the friendlier label "Reminders".
    /// Schedule rows now use a consistent "Schedule" label (instead of mixed
    /// "Schedule" / "Monthly Schedule" / "Backup Schedule"), and shorter
    /// subtitles to reduce visual weight.
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Reminders")
                .padding(.bottom, Theme.Spacing.xs)

            weeklySummaryToggleRow
            if weeklySummaryEnabled {
                scheduleRow(
                    label: "Schedule",
                    value: weeklySummaryScheduleText(),
                    enabled: weeklySummaryEnabled
                ) {
                    scheduleTempWeekday = weeklySummaryWeekday
                    scheduleTempTime = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
                    showingWeeklySummarySchedule = true
                }
            }

            monthlyDigestToggleRow
            if monthlyDigestEnabled {
                scheduleRow(
                    label: "Schedule",
                    value: monthlyDigestScheduleText(),
                    enabled: monthlyDigestEnabled
                ) {
                    monthlyTempDayOfMonth = monthlyDigestDayOfMonth
                    monthlyTempTime = makeTimeDate(hour: monthlyDigestHour, minute: monthlyDigestMinute)
                    showingMonthlyDigestSchedule = true
                }
            }

            backupReminderToggleRow
            if backupReminderEnabled {
                scheduleRow(
                    label: "Schedule",
                    value: backupReminderScheduleText(),
                    enabled: backupReminderEnabled
                ) {
                    backupTempDayOfMonth = backupReminderDayOfMonth
                    backupTempTime = makeTimeDate(hour: backupReminderHour, minute: backupReminderMinute)
                    showingBackupReminderSchedule = true
                }
            }

            smartInsightsToggleRow
        }
        .sectionContainer()
        .sheet(isPresented: $showingWeeklySummarySchedule) {
            weeklySummaryScheduleSheet
        }
        .sheet(isPresented: $showingMonthlyDigestSchedule) {
            monthlyDigestScheduleSheet
        }
        .sheet(isPresented: $showingBackupReminderSchedule) {
            backupReminderScheduleSheet
        }
    }

    /// Shared schedule row helper — was previously three near-duplicate `var`s.
    private func scheduleRow(
        label: String,
        value: String,
        enabled: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        SettingsRow(icon: "calendar.badge.clock", title: label) {
            SettingsRowValue(text: value)
        }
        .opacity(enabled ? 1.0 : 0.5)
        .onTapGesture {
            guard enabled else { return }
            HapticManager.shared.lightTap()
            onTap()
        }
    }

    private var weeklySummaryToggleRow: some View {
        SettingsRow(
            icon: "bell.badge.fill",
            title: "Weekly Digest",
            subtitle: "Spending summary every week.",
            showsChevron: false
        ) {
            Toggle("", isOn: Binding(
                get: { weeklySummaryEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    Task {
                        if newValue {
                            let ok = await NotificationScheduler.ensureAuthorized()
                            await MainActor.run {
                                weeklySummaryEnabled = ok
                                if !ok { activeAlert = .notificationPermission }
                            }
                        } else {
                            await MainActor.run { weeklySummaryEnabled = false }
                        }
                        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel, isPro: proManager.isPro)
                    }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    /// Pro-gated Smart Insights toggle. When the user is not Pro the row
    /// stays visible (so the existence of the feature is discoverable) but
    /// taps route into the paywall instead of flipping the switch — that's
    /// a much better acquisition surface than a hidden setting.
    private var smartInsightsToggleRow: some View {
        SettingsRow(
            icon: "sparkles",
            title: "Smart Insights",
            subtitle: proManager.isPro
                ? "One push only when something interesting happens."
                : "Unlock weekly highlights powered by your data.",
            showsChevron: false
        ) {
            if proManager.isPro {
                Toggle("", isOn: Binding(
                    get: { smartInsightsEnabled },
                    set: { newValue in
                        HapticManager.shared.lightTap()
                        Task {
                            if newValue {
                                let ok = await NotificationScheduler.ensureAuthorized()
                                await MainActor.run {
                                    smartInsightsEnabled = ok
                                    if !ok { activeAlert = .notificationPermission }
                                }
                            } else {
                                await MainActor.run { smartInsightsEnabled = false }
                            }
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(
                                viewModel: viewModel,
                                isPro: proManager.isPro
                            )
                        }
                    }
                ))
                .labelsHidden()
                .tint(.appPrimary)
            } else {
                // Compact "Pro" pill that visually mirrors the Statistics
                // teaser. Tapping anywhere on the row opens the paywall.
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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Free users opening the paywall via a row tap is the most
            // common entry point in the rest of the app — keep parity here.
            if !proManager.isPro {
                HapticManager.shared.lightTap()
                showingPaywall = true
            }
        }
    }

    private var weeklySummaryScheduleSheet: some View {
        NavigationView {
            Form {
                Picker("Day", selection: $scheduleTempWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(weekdayName(weekday)).tag(weekday)
                    }
                }

                DatePicker("Time", selection: $scheduleTempTime, displayedComponents: [.hourAndMinute])
            }
            .navigationTitle("Weekly Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingWeeklySummarySchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleTempTime)
                        weeklySummaryWeekday = scheduleTempWeekday
                        weeklySummaryHour = comps.hour ?? 9
                        weeklySummaryMinute = comps.minute ?? 0
                        showingWeeklySummarySchedule = false

                        Task {
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel, isPro: proManager.isPro)
                        }
                    }
                }
            }
        }
    }

    private var monthlyDigestToggleRow: some View {
        SettingsRow(
            icon: "calendar.badge.clock",
            title: "Monthly Digest",
            subtitle: "Recap of last month's spending.",
            showsChevron: false
        ) {
            Toggle("", isOn: Binding(
                get: { monthlyDigestEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    Task {
                        if newValue {
                            let ok = await NotificationScheduler.ensureAuthorized()
                            await MainActor.run {
                                monthlyDigestEnabled = ok
                                if !ok { activeAlert = .notificationPermission }
                            }
                        } else {
                            await MainActor.run { monthlyDigestEnabled = false }
                        }
                        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel, isPro: proManager.isPro)
                    }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    private var monthlyDigestScheduleSheet: some View {
        NavigationView {
            Form {
                Picker("Day of month", selection: $monthlyTempDayOfMonth) {
                    ForEach(1...28, id: \.self) { d in
                        Text("\(d)").tag(d)
                    }
                }
                DatePicker("Time", selection: $monthlyTempTime, displayedComponents: [.hourAndMinute])
            }
            .navigationTitle("Monthly Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingMonthlyDigestSchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: monthlyTempTime)
                        monthlyDigestDayOfMonth = monthlyTempDayOfMonth
                        monthlyDigestHour = comps.hour ?? 9
                        monthlyDigestMinute = comps.minute ?? 0
                        showingMonthlyDigestSchedule = false

                        Task {
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel, isPro: proManager.isPro)
                        }
                    }
                }
            }
        }
    }

    private var backupReminderToggleRow: some View {
        SettingsRow(
            icon: "externaldrive.fill.badge.timemachine",
            title: "Backup Reminder",
            subtitle: "Monthly nudge to export to Files.",
            showsChevron: false
        ) {
            Toggle("", isOn: Binding(
                get: { backupReminderEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    Task {
                        if newValue {
                            let ok = await NotificationScheduler.ensureAuthorized()
                            await MainActor.run {
                                backupReminderEnabled = ok
                                if !ok { activeAlert = .notificationPermission }
                            }
                        } else {
                            await MainActor.run { backupReminderEnabled = false }
                        }
                        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel, isPro: proManager.isPro)
                    }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    private var backupReminderScheduleSheet: some View {
        NavigationView {
            Form {
                Picker("Day of month", selection: $backupTempDayOfMonth) {
                    ForEach(1...28, id: \.self) { d in
                        Text("\(d)").tag(d)
                    }
                }
                DatePicker("Time", selection: $backupTempTime, displayedComponents: [.hourAndMinute])
            }
            .navigationTitle("Backup Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingBackupReminderSchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: backupTempTime)
                        backupReminderDayOfMonth = backupTempDayOfMonth
                        backupReminderHour = comps.hour ?? 9
                        backupReminderMinute = comps.minute ?? 0
                        showingBackupReminderSchedule = false

                        Task {
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel, isPro: proManager.isPro)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data section

    /// Combines export / import / clear-all + the full Backup Health card +
    /// info note. Backup-related settings now live together in one place
    /// instead of being split across two sections.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Data") {
                backupHealthBadge
            }
            .padding(.bottom, Theme.Spacing.xs)

            backupHealthCard

            SettingsRow(icon: "square.and.arrow.up.fill", title: "Export Data")
                .onTapGesture {
                    HapticManager.shared.lightTap()
                    showingExportSheet = true
                }

            SettingsRow(icon: "square.and.arrow.down.fill", title: "Import Data")
                .onTapGesture {
                    HapticManager.shared.lightTap()
                    showingImportSheet = true
                }

            SettingsRowDestructive(icon: "trash.fill", title: "Clear All Data")
                .onTapGesture {
                    HapticManager.shared.mediumTap()
                    activeAlert = .clearAllData
                }

            HStack(alignment: .top, spacing: Theme.Spacing.sm + 2) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("Your data lives only on this device. Regular exports keep your history safe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.top, Theme.Spacing.xs)
        }
        .sectionContainer()
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("About")
                .padding(.bottom, Theme.Spacing.xs)

            SettingsRow(icon: "heart.fill", iconTint: .pink, title: "Support the App")
                .onTapGesture {
                    HapticManager.shared.lightTap()
                    showingDonationSheet = true
                }

            SettingsRow(icon: "doc.text.fill", title: "About CashLens")
                .onTapGesture {
                    HapticManager.shared.lightTap()
                    showingAboutSheet = true
                }

            communityIconRow
        }
        .sectionContainer()
        .sheet(isPresented: $showingAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showingDonationSheet) {
            NavigationView { DonationView() }
        }
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
            Text("CashLens · v\(versionString)")
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

                backupStatCell(title: "Expenses", value: "\(viewModel.expenses.count)")
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

    // MARK: - Schedule helpers

    private func weeklySummaryScheduleText() -> String {
        let time = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
        let df = DateFormatter()
        df.timeStyle = .short
        return "\(weekdayName(weeklySummaryWeekday)) • \(df.string(from: time))"
    }

    private func monthlyDigestScheduleText() -> String {
        let time = makeTimeDate(hour: monthlyDigestHour, minute: monthlyDigestMinute)
        let df = DateFormatter()
        df.timeStyle = .short
        return "Day \(max(1, min(28, monthlyDigestDayOfMonth))) • \(df.string(from: time))"
    }

    private func backupReminderScheduleText() -> String {
        let time = makeTimeDate(hour: backupReminderHour, minute: backupReminderMinute)
        let df = DateFormatter()
        df.timeStyle = .short
        return "Day \(max(1, min(28, backupReminderDayOfMonth))) • \(df.string(from: time))"
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(1, min(7, weekday)) - 1
        return symbols[index]
    }

    private func makeTimeDate(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
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
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: date)
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
            .environmentObject(CategoryViewModel())
    }
}
