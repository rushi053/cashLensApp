import SwiftUI

/// Picks a period, then plays the story. Stats are built from expenses already on the device.
struct WrappedFlowView: View {
    @EnvironmentObject private var viewModel: ExpenseViewModel
    @EnvironmentObject private var categoryViewModel: CategoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var stats: WrappedStats?

    var body: some View {
        Group {
            if let stats {
                WrappedPlayerView(stats: stats, onDismiss: { dismiss() })
            } else {
                launcher
            }
        }
    }

    private var launcher: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A spending story from the expenses already on this phone. Nothing is uploaded.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    periodButton(
                        title: WrappedPeriod.thisMonth.pickerTitle,
                        subtitle: monthWindow.title,
                        systemImage: "calendar"
                    ) {
                        open(.thisMonth)
                    }

                    periodButton(
                        title: WrappedPeriod.festiveSeason.pickerTitle,
                        subtitle: festiveSubtitle,
                        systemImage: "sparkles"
                    ) {
                        open(.festiveSeason)
                    }

                    Text("Diwali night is the anchor. The season runs 21 days before it through Bhai Dooj. Shared cards hide amounts unless you turn that on.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Color.systemBackground)
            .navigationTitle("Wrapped")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func periodButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.mauve.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.mauve)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.mauve)
            }
            .padding(16)
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var monthWindow: WrappedWindow {
        WrappedCalendar.monthWindow(containing: Date(), calendar: .current)
    }

    private var festiveSubtitle: String {
        let calendar = Calendar.current
        guard let window = WrappedCalendar.festiveWindow(relevantTo: Date(), calendar: calendar) else {
            return "No Diwali date for this year yet"
        }
        let start = WrappedCalendar.shortDayLabel(for: window.start, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        let end = WrappedCalendar.shortDayLabel(for: lastDay, calendar: calendar)
        if Date() < window.start {
            return "Starts \(start) · \(window.title)"
        }
        return "\(start) – \(end)"
    }

    private func open(_ period: WrappedPeriod) {
        HapticManager.shared.mediumTap()
        var names: [UUID: String] = [:]
        var icons: [UUID: String] = [:]
        for category in categoryViewModel.customCategories {
            names[category.id] = category.name
            icons[category.id] = category.icon
        }
        stats = WrappedEngine.build(
            expenses: viewModel.expenses,
            period: period,
            now: Date(),
            calendar: .current,
            currency: viewModel.selectedCurrency,
            customCategoryNames: names,
            customCategoryIcons: icons
        )
    }
}
