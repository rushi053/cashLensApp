import SwiftUI
import Foundation
import StoreKit
import UserNotifications

struct ProfileView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var isEditingName = false
    @State private var tempUserName = ""
    @State private var showingCurrencyPicker = false
    @State private var showingAppearancePicker = false
    @State private var showingDefaultTimeFramePicker = false
    @State private var showingAboutSheet = false
    @State private var showingExportSheet = false
    @State private var showingDonationSheet = false
    @State private var showingImportSheet = false
    
    // Weekly summary notifications (opt-in)
    @AppStorage(UserDefaultsKeys.weeklySummaryEnabled) private var weeklySummaryEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.weeklySummaryWeekday) private var weeklySummaryWeekday: Int = 2 // Monday
    @AppStorage(UserDefaultsKeys.weeklySummaryHour) private var weeklySummaryHour: Int = 9
    @AppStorage(UserDefaultsKeys.weeklySummaryMinute) private var weeklySummaryMinute: Int = 0
    
    @State private var showingWeeklySummarySchedule = false
    @State private var showingNotificationPermissionAlert = false
    @State private var scheduleTempWeekday: Int = 2
    @State private var scheduleTempTime: Date = Date()

    // Monthly digest (opt-in)
    @AppStorage(UserDefaultsKeys.monthlyDigestEnabled) private var monthlyDigestEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.monthlyDigestDayOfMonth) private var monthlyDigestDayOfMonth: Int = 1
    @AppStorage(UserDefaultsKeys.monthlyDigestHour) private var monthlyDigestHour: Int = 9
    @AppStorage(UserDefaultsKeys.monthlyDigestMinute) private var monthlyDigestMinute: Int = 0
    @State private var showingMonthlyDigestSchedule = false
    @State private var monthlyTempDayOfMonth: Int = 1
    @State private var monthlyTempTime: Date = Date()
    
    // Backup reminder (opt-in)
    @AppStorage(UserDefaultsKeys.backupReminderEnabled) private var backupReminderEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.backupReminderDayOfMonth) private var backupReminderDayOfMonth: Int = 1
    @AppStorage(UserDefaultsKeys.backupReminderHour) private var backupReminderHour: Int = 9
    @AppStorage(UserDefaultsKeys.backupReminderMinute) private var backupReminderMinute: Int = 0
    @State private var showingBackupReminderSchedule = false
    @State private var backupTempDayOfMonth: Int = 1
    @State private var backupTempTime: Date = Date()

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
    
    // Get version and build from Info.plist
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader
                    
                    // Settings Section
                    settingsSection
                    
                    // Notifications Section
                    notificationsSection
                    
                    // App Info Section
                    appInfoSection
                    
                    // Community Section
                    communitySection
                    
                    // Data Management Section
                    dataManagementSection
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(8)
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
                            hapticFeedback(style: .heavy)
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
                // Initialize the temporary user name with the current value
                tempUserName = viewModel.userName
                
                // Initialize schedule editor state
                scheduleTempWeekday = weeklySummaryWeekday
                scheduleTempTime = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile Image
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text(String(viewModel.userName.prefix(1)))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 8)
            
            // User Name
            if isEditingName {
                TextField("Your Name", text: $tempUserName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(10)
                    .padding(.horizontal, 40)
                    .onSubmit {
                        saveName()
                    }
                
                // Save button
                Button(action: saveName) {
                    Text("Save")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 8)
            } else {
                Text(viewModel.userName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .onTapGesture {
                        isEditingName = true
                    }
                
                // Edit Button
                Button(action: {
                    isEditingName = true
                }) {
                    Text("Edit Profile")
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .stroke(Color.appPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding()
        .cornerRadius(20)
    }
    
    // Save the user name
    private func saveName() {
        if !tempUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.userName = tempUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // If empty, revert to the previous name
            tempUserName = viewModel.userName
        }
        isEditingName = false
        hapticFeedback(style: .medium)
    }
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            currencyRow
            appearanceRow
            defaultTimeFrameRow
            donationRow
            appearancePicker
            defaultTimeFramePicker
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
        .sheet(isPresented: $showingDonationSheet) {
            NavigationView {
                DonationView()
            }
        }
    }
    
    // MARK: - Notifications Section
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notifications")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            weeklySummaryToggleRow
            if weeklySummaryEnabled {
                weeklySummaryScheduleRow
            }
            
            monthlyDigestToggleRow
            if monthlyDigestEnabled {
                monthlyDigestScheduleRow
            }
            
            backupReminderToggleRow
            if backupReminderEnabled {
                backupReminderScheduleRow
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
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
    
    private var weeklySummaryToggleRow: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly Digest")
                    .foregroundColor(.primary)
                Text("A weekly spending summary. Tap to open your expenses for that week.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { weeklySummaryEnabled },
                set: { newValue in
                    hapticFeedback(style: .light)
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
                        
                        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                    }
                }
            ))
            .labelsHidden()
            .tint(.mauve)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
    }
    
    private var weeklySummaryScheduleRow: some View {
        let scheduleText = weeklySummaryScheduleText()
        
        return HStack {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            Text("Schedule")
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(scheduleText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .opacity(weeklySummaryEnabled ? 1.0 : 0.5)
        .onTapGesture {
            guard weeklySummaryEnabled else { return }
            hapticFeedback(style: .light)
            scheduleTempWeekday = weeklySummaryWeekday
            scheduleTempTime = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
            showingWeeklySummarySchedule = true
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
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }

    private var monthlyDigestToggleRow: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly Digest")
                    .foregroundColor(.primary)
                Text("A monthly recap. Tap to open your expenses for that month.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { monthlyDigestEnabled },
                set: { newValue in
                    hapticFeedback(style: .light)
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
                        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                    }
                }
            ))
            .labelsHidden()
            .tint(.mauve)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
    }
    
    private var monthlyDigestScheduleRow: some View {
        let scheduleText = monthlyDigestScheduleText()
        
        return HStack {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            Text("Monthly Schedule")
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(scheduleText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .opacity(monthlyDigestEnabled ? 1.0 : 0.5)
        .onTapGesture {
            guard monthlyDigestEnabled else { return }
            hapticFeedback(style: .light)
            monthlyTempDayOfMonth = monthlyDigestDayOfMonth
            monthlyTempTime = makeTimeDate(hour: monthlyDigestHour, minute: monthlyDigestMinute)
            showingMonthlyDigestSchedule = true
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
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }
    
    private func monthlyDigestScheduleText() -> String {
        let time = makeTimeDate(hour: monthlyDigestHour, minute: monthlyDigestMinute)
        let df = DateFormatter()
        df.timeStyle = .short
        return "Day \(max(1, min(28, monthlyDigestDayOfMonth))) • \(df.string(from: time))"
    }
    
    private var backupReminderToggleRow: some View {
        HStack {
            Image(systemName: "externaldrive.fill.badge.timemachine")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Backup Reminder")
                    .foregroundColor(.primary)
                Text("A monthly reminder to export your data to Files.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { backupReminderEnabled },
                set: { newValue in
                    hapticFeedback(style: .light)
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
                        await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                    }
                }
            ))
            .labelsHidden()
            .tint(.mauve)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
    }
    
    private var backupReminderScheduleRow: some View {
        let scheduleText = backupReminderScheduleText()
        
        return HStack {
            Image(systemName: "clock")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            Text("Backup Schedule")
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(scheduleText)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .opacity(backupReminderEnabled ? 1.0 : 0.5)
        .onTapGesture {
            guard backupReminderEnabled else { return }
            hapticFeedback(style: .light)
            backupTempDayOfMonth = backupReminderDayOfMonth
            backupTempTime = makeTimeDate(hour: backupReminderHour, minute: backupReminderMinute)
            showingBackupReminderSchedule = true
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
                            await NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }
    
    private func backupReminderScheduleText() -> String {
        let time = makeTimeDate(hour: backupReminderHour, minute: backupReminderMinute)
        let df = DateFormatter()
        df.timeStyle = .short
        return "Day \(max(1, min(28, backupReminderDayOfMonth))) • \(df.string(from: time))"
    }
    
    private func weeklySummaryScheduleText() -> String {
        let time = makeTimeDate(hour: weeklySummaryHour, minute: weeklySummaryMinute)
        let df = DateFormatter()
        df.timeStyle = .short
        return "\(weekdayName(weeklySummaryWeekday)) • \(df.string(from: time))"
    }
    
    private func weekdayName(_ weekday: Int) -> String {
        // Calendar weekday: 1=Sunday...7=Saturday
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

    // MARK: - Settings Subviews (kept separate to avoid type-check timeouts)
    
    private var currencyRow: some View {
        HStack {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            Text("Default Currency")
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(viewModel.selectedCurrency.symbol) \(viewModel.selectedCurrency.rawValue)")
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            hapticFeedback(style: .light)
            showingCurrencyPicker.toggle()
        }
    }
    
    private var appearanceRow: some View {
        HStack {
            Image(systemName: "moon.fill")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            Text("Appearance")
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(viewModel.appearanceMode.rawValue)
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            hapticFeedback(style: .light)
            showingAppearancePicker.toggle()
        }
    }
    
    private var defaultTimeFrameRow: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 22))
                .foregroundColor(.appPrimary)
                .frame(width: 30)
            
            Text("Default Time Frame")
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(viewModel.defaultHomeTimeFrame.rawValue)
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            hapticFeedback(style: .light)
            showingDefaultTimeFramePicker.toggle()
        }
    }
    
    private var donationRow: some View {
        HStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 22))
                .foregroundColor(.pink)
                .frame(width: 30)
            
            Text("Support the App")
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            hapticFeedback(style: .light)
            showingDonationSheet = true
        }
    }
    
    @ViewBuilder
    private var appearancePicker: some View {
        if showingAppearancePicker {
            VStack(spacing: 0) {
                ForEach(ExpenseViewModel.AppearanceMode.allCases, id: \.self) { mode in
                    HStack {
                        Text(mode.rawValue)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if viewModel.appearanceMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundColor(.appPrimary)
                        }
                    }
                    .padding()
                    .background(
                        viewModel.appearanceMode == mode ?
                        Color.appPrimary.opacity(0.1) :
                        Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hapticFeedback(style: .medium)
                        withAnimation(.spring()) {
                            viewModel.appearanceMode = mode
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingAppearancePicker = false
                            }
                        }
                    }
                    
                    if mode != ExpenseViewModel.AppearanceMode.allCases.last {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.mauve.opacity(0.3), lineWidth: 1)
            )
            .transition(.opacity)
        }
    }
    
    @ViewBuilder
    private var defaultTimeFramePicker: some View {
        if showingDefaultTimeFramePicker {
            VStack(spacing: 0) {
                ForEach(ExpenseViewModel.TimeFrame.allCases, id: \.self) { timeFrame in
                    HStack {
                        Text(timeFrame.rawValue)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if viewModel.defaultHomeTimeFrame == timeFrame {
                            Image(systemName: "checkmark")
                                .foregroundColor(.appPrimary)
                        }
                    }
                    .padding()
                    .background(
                        viewModel.defaultHomeTimeFrame == timeFrame ?
                        Color.appPrimary.opacity(0.1) :
                        Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hapticFeedback(style: .medium)
                        withAnimation(.spring()) {
                            viewModel.defaultHomeTimeFrame = timeFrame
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingDefaultTimeFramePicker = false
                            }
                        }
                    }
                    
                    if timeFrame != ExpenseViewModel.TimeFrame.allCases.last {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.mauve.opacity(0.3), lineWidth: 1)
            )
            .transition(.opacity)
        }
    }
    
    // MARK: - App Info Section
    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Info")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            // Version Info
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Version")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(versionString)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            
            // About
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("About CashLens")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingAboutSheet = true
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Community Section
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Community")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Join our community for tips, feedback, and updates!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            
            // Social Media Buttons
            VStack(spacing: 12) {
                // Instagram
                Button(action: {
                    hapticFeedback(style: .light)
                    openSocialMedia(.instagram)
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Instagram")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Daily tips & app updates")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.pink, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
                
                // X (Twitter)
                Button(action: {
                    hapticFeedback(style: .light)
                    openSocialMedia(.twitter)
                }) {
                    HStack {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("X (Twitter)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Quick updates & announcements")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Reddit
                Button(action: {
                    hapticFeedback(style: .light)
                    openSocialMedia(.reddit)
                }) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reddit")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Community discussions & support")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Social Media Handling
    enum SocialPlatform {
        case instagram, twitter, reddit
    }
    
    private func openSocialMedia(_ platform: SocialPlatform) {
        let urlString: String
        
        switch platform {
        case .instagram:
            urlString = "https://instagram.com/cashlensapp"
        case .twitter:
            urlString = "https://x.com/cashlensapp"
        case .reddit:
            urlString = "https://www.reddit.com/r/cashlens/s/Z36oUPfZ3j"
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Data Management Section
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            // Export Data
            HStack {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Export Data")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingExportSheet = true
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportDataView()
                    .environmentObject(viewModel)
            }
            
            // Import Data
            HStack {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Import Data")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingImportSheet = true
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportDataView()
                    .environmentObject(viewModel)
            }
            
            // Clear Data
            HStack {
                Image(systemName: "trash.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.red)
                    .frame(width: 30)
                
                Text("Clear All Data")
                    .foregroundColor(.red)
                
                Spacer()
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .medium)
                activeAlert = .clearAllData
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Haptic Feedback
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(ExpenseViewModel())
    }
} 
