import SwiftUI
import UserNotifications

/// Notifications & Reminders hub — pushed from "You → Notifications".
///
/// Owns all reminder schedules + the Smart Insights toggle so the
/// Settings root stays calm and scannable instead of stacking 4–9
/// reminder-related rows. Surface here is a single elevated card
/// per category (with the schedule sub-row appearing only when the
/// toggle is on), plus a dedicated Smart Insights group at the
/// bottom for the Pro feature.
///
/// State management:
/// - All `@AppStorage` keys are the same ones `ProfileView` used to
///   own — they're shared via UserDefaults, so both `ProfileView`'s
///   "N active" badge and this view stay in sync automatically.
/// - Schedule pickers are presented as sheets and write through to
///   the live `@AppStorage` values on save, then trigger a
///   notification refresh through `NotificationScheduler`.
struct NotificationsSettingsView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @EnvironmentObject var proManager: ProManager

    // MARK: - Weekly digest

    @AppStorage(UserDefaultsKeys.weeklySummaryEnabled) private var weeklySummaryEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.weeklySummaryWeekday) private var weeklySummaryWeekday: Int = 2
    @AppStorage(UserDefaultsKeys.weeklySummaryHour) private var weeklySummaryHour: Int = 9
    @AppStorage(UserDefaultsKeys.weeklySummaryMinute) private var weeklySummaryMinute: Int = 0

    @State private var showingWeeklySchedule = false
    @State private var weeklyTempWeekday: Int = 2
    @State private var weeklyTempTime: Date = Date()

    // MARK: - Monthly digest

    @AppStorage(UserDefaultsKeys.monthlyDigestEnabled) private var monthlyDigestEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.monthlyDigestDayOfMonth) private var monthlyDigestDayOfMonth: Int = 1
    @AppStorage(UserDefaultsKeys.monthlyDigestHour) private var monthlyDigestHour: Int = 9
    @AppStorage(UserDefaultsKeys.monthlyDigestMinute) private var monthlyDigestMinute: Int = 0

    @State private var showingMonthlySchedule = false
    @State private var monthlyTempDayOfMonth: Int = 1
    @State private var monthlyTempTime: Date = Date()

    // MARK: - Backup reminder

    @AppStorage(UserDefaultsKeys.backupReminderEnabled) private var backupReminderEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.backupReminderDayOfMonth) private var backupReminderDayOfMonth: Int = 1
    @AppStorage(UserDefaultsKeys.backupReminderHour) private var backupReminderHour: Int = 9
    @AppStorage(UserDefaultsKeys.backupReminderMinute) private var backupReminderMinute: Int = 0

    @State private var showingBackupSchedule = false
    @State private var backupTempDayOfMonth: Int = 1
    @State private var backupTempTime: Date = Date()

    // MARK: - Smart Insights (Pro)

    @AppStorage(UserDefaultsKeys.smartInsightsEnabled) private var smartInsightsEnabled: Bool = false

    // MARK: - Cross-cutting

    @State private var showingPaywall = false
    @State private var showingPermissionAlert = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxl) {
                introBlock

                SettingsGroup(title: "Reminders") {
                    weeklyDigestToggleRow
                    if weeklySummaryEnabled {
                        scheduleRow(
                            value: weeklySummaryScheduleText(),
                            enabled: weeklySummaryEnabled
                        ) {
                            weeklyTempWeekday = weeklySummaryWeekday
                            weeklyTempTime = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
                            showingWeeklySchedule = true
                        }
                    }

                    monthlyDigestToggleRow
                    if monthlyDigestEnabled {
                        scheduleRow(
                            value: monthlyDigestScheduleText(),
                            enabled: monthlyDigestEnabled
                        ) {
                            monthlyTempDayOfMonth = monthlyDigestDayOfMonth
                            monthlyTempTime = makeTimeDate(hour: monthlyDigestHour, minute: monthlyDigestMinute)
                            showingMonthlySchedule = true
                        }
                    }

                    backupReminderToggleRow
                    if backupReminderEnabled {
                        scheduleRow(
                            value: backupReminderScheduleText(),
                            enabled: backupReminderEnabled
                        ) {
                            backupTempDayOfMonth = backupReminderDayOfMonth
                            backupTempTime = makeTimeDate(hour: backupReminderHour, minute: backupReminderMinute)
                            showingBackupSchedule = true
                        }
                    }
                }

                SettingsGroup(title: "Premium") {
                    smartInsightsToggleRow
                }

                footerNote
            }
            .padding()
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Color.systemBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        // Parent tab root (You) hides its nav bar; pushed views must
        // explicitly opt back in or the back button disappears.
        .navigationBarHidden(false)
        .sheet(isPresented: $showingWeeklySchedule) {
            weeklyScheduleSheet
        }
        .sheet(isPresented: $showingMonthlySchedule) {
            monthlyScheduleSheet
        }
        .sheet(isPresented: $showingBackupSchedule) {
            backupScheduleSheet
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(context: .insights)
        }
        .alert("Enable Notifications", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable notifications in Settings to receive reminders.")
        }
    }

    // MARK: - Intro / footer

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Stay on track without the noise. Each reminder is opt-in — pick exactly when CashLens should reach out.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.xs)
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm + 2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Reminders fire in your local time. Digests include your spending total — if you'd rather keep that off the Lock Screen, set notification previews to \"When Unlocked\" in iOS Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Shared schedule row

    private func scheduleRow(
        value: String,
        enabled: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        SettingsRow(icon: "clock.fill", title: "Schedule", style: .bare) {
            SettingsRowValue(text: value)
        }
        .opacity(enabled ? 1.0 : 0.5)
        .onTapGesture {
            guard enabled else { return }
            HapticManager.shared.lightTap()
            onTap()
        }
    }

    // MARK: - Weekly digest

    private var weeklyDigestToggleRow: some View {
        SettingsRow(
            icon: "bell.badge.fill",
            title: "Weekly Digest",
            subtitle: "Spending summary every week.",
            showsChevron: false,
            style: .bare
        ) {
            Toggle("", isOn: Binding(
                get: { weeklySummaryEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    Task { await applyToggle(newValue) { ok in weeklySummaryEnabled = ok } }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    private var weeklyScheduleSheet: some View {
        NavigationView {
            Form {
                Picker("Day", selection: $weeklyTempWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(weekdayName(weekday)).tag(weekday)
                    }
                }
                DatePicker("Time", selection: $weeklyTempTime, displayedComponents: [.hourAndMinute])
            }
            .navigationTitle("Weekly Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingWeeklySchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: weeklyTempTime)
                        weeklySummaryWeekday = weeklyTempWeekday
                        weeklySummaryHour = comps.hour ?? 9
                        weeklySummaryMinute = comps.minute ?? 0
                        showingWeeklySchedule = false
                        scheduleRefresh()
                    }
                }
            }
        }
    }

    // MARK: - Monthly digest

    private var monthlyDigestToggleRow: some View {
        SettingsRow(
            icon: "calendar.badge.clock",
            title: "Monthly Digest",
            subtitle: "Recap of last month's spending.",
            showsChevron: false,
            style: .bare
        ) {
            Toggle("", isOn: Binding(
                get: { monthlyDigestEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    Task { await applyToggle(newValue) { ok in monthlyDigestEnabled = ok } }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    private var monthlyScheduleSheet: some View {
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
                    Button("Cancel") { showingMonthlySchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: monthlyTempTime)
                        monthlyDigestDayOfMonth = monthlyTempDayOfMonth
                        monthlyDigestHour = comps.hour ?? 9
                        monthlyDigestMinute = comps.minute ?? 0
                        showingMonthlySchedule = false
                        scheduleRefresh()
                    }
                }
            }
        }
    }

    // MARK: - Backup reminder

    private var backupReminderToggleRow: some View {
        SettingsRow(
            icon: "externaldrive.fill.badge.timemachine",
            title: "Backup Reminder",
            subtitle: "Monthly nudge to export to Files.",
            showsChevron: false,
            style: .bare
        ) {
            Toggle("", isOn: Binding(
                get: { backupReminderEnabled },
                set: { newValue in
                    HapticManager.shared.lightTap()
                    Task { await applyToggle(newValue) { ok in backupReminderEnabled = ok } }
                }
            ))
            .labelsHidden()
            .tint(.appPrimary)
        }
    }

    private var backupScheduleSheet: some View {
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
                    Button("Cancel") { showingBackupSchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: backupTempTime)
                        backupReminderDayOfMonth = backupTempDayOfMonth
                        backupReminderHour = comps.hour ?? 9
                        backupReminderMinute = comps.minute ?? 0
                        showingBackupSchedule = false
                        scheduleRefresh()
                    }
                }
            }
        }
    }

    // MARK: - Smart Insights (Pro)

    /// Mirrors the gating treatment in `ProfileView`: free users see
    /// the row with a lock pill so the feature is discoverable, and
    /// tapping the row drops them into the paywall instead of
    /// flipping the switch.
    private var smartInsightsToggleRow: some View {
        SettingsRow(
            icon: "sparkles",
            title: "Smart Insights",
            subtitle: proManager.isPro
                ? "One push only when something interesting happens."
                : "Unlock weekly highlights powered by your data.",
            showsChevron: false,
            style: .bare
        ) {
            if proManager.isPro {
                Toggle("", isOn: Binding(
                    get: { smartInsightsEnabled },
                    set: { newValue in
                        HapticManager.shared.lightTap()
                        Task { await applyToggle(newValue) { ok in smartInsightsEnabled = ok } }
                    }
                ))
                .labelsHidden()
                .tint(.appPrimary)
            } else {
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
            if !proManager.isPro {
                HapticManager.shared.lightTap()
                showingPaywall = true
            }
        }
    }

    // MARK: - Toggle apply / scheduler

    /// Shared toggle handler. Asks for notification permission when
    /// turning on, surfaces the in-app alert if it's denied, and
    /// refreshes the scheduler in both directions.
    private func applyToggle(_ newValue: Bool, write: @MainActor @escaping (Bool) -> Void) async {
        if newValue {
            let ok = await NotificationScheduler.ensureAuthorized()
            await MainActor.run {
                write(ok)
                if !ok { showingPermissionAlert = true }
            }
        } else {
            await MainActor.run { write(false) }
        }
        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(
            viewModel: viewModel,
            isPro: proManager.isPro
        )
    }

    private func scheduleRefresh() {
        Task {
            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(
                viewModel: viewModel,
                isPro: proManager.isPro
            )
        }
    }

    // MARK: - Schedule label helpers

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
}

// MARK: - Preview

struct NotificationsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotificationsSettingsView()
                .environmentObject(ExpenseViewModel())
                .environmentObject(ProManager.shared)
        }
    }
}
