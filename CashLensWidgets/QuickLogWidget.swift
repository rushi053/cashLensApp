//
//  QuickLogWidget.swift
//  CashLensWidgets
//
//  Interactive "Quick Log" widget — today's total plus one-tap
//  template buttons.
//
//  CRITICAL architecture note: `Button(intent:)` executes its App
//  Intent in the WIDGET EXTENSION process, which cannot reach the
//  app-container Core Data store. The intent therefore appends a
//  `PendingExpenseRecord` to the App Group queue
//  (`PendingExpenseQueue`) and reloads this widget's timeline; the
//  provider adds queued-today records to the snapshot total, so the
//  displayed number bumps optimistically. The main app drains the
//  queue into Core Data on its next launch/foreground and republishes
//  the snapshot, reconciling the optimistic total with ground truth.
//
//  Free/Pro: the widget itself is free with ONE active template
//  button; additional templates render locked until the snapshot
//  reports `isPro == true`.
//
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget-side intent

/// Enqueues one template expense. Runs in the widget process — it must
/// never touch Core Data. Not discoverable: this is plumbing for the
/// widget buttons, not a user-facing Shortcuts action (the app target
/// vends `LogExpenseIntent` for that).
struct QuickLogTemplateIntent: AppIntent {

    static var title: LocalizedStringResource = "Quick Log Expense"
    static var description = IntentDescription("Logs a saved template from the Quick Log widget.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Title")
    var name: String

    @Parameter(title: "Category")
    var categoryRaw: String

    @Parameter(title: "Custom Category ID")
    var customCategoryId: String?

    init() {}

    init(template: WidgetSnapshot.QuickLogTemplate) {
        self.amount = template.amount
        self.name = template.name
        self.categoryRaw = template.categoryRaw
        self.customCategoryId = template.customCategoryId?.uuidString
    }

    func perform() async throws -> some IntentResult {
        let record = PendingExpenseRecord(
            id: UUID(),
            amount: amount,
            title: name,
            categoryRaw: categoryRaw,
            customCategoryId: customCategoryId.flatMap(UUID.init(uuidString:)),
            createdAt: Date()
        )
        // If the App Group write failed, don't reload — bumping the
        // optimistic total for a tap that was silently lost would show
        // the user a number that never materializes in the app.
        guard PendingExpenseQueue.append(record) else { return .result() }
        // Re-render so the optimistic total reflects the tap right away.
        WidgetCenter.shared.reloadTimelines(ofKind: QuickLogWidget.kind)
        return .result()
    }
}

// MARK: - Provider

struct QuickLogTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: Date(), snapshot: .preview, pendingTodayNet: 0, pendingTodayCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    /// Snapshot + optimistic overlay: queued records dated today that
    /// the app hasn't drained yet get added on top of the snapshot's
    /// today total, so a tap bumps the number immediately.
    private func makeEntry() -> QuickLogEntry {
        let snapshot = WidgetSnapshotIO.read()
        let calendar = Calendar.current
        let pendingToday = PendingExpenseQueue.readAll()
            .filter { calendar.isDateInToday($0.createdAt) }
        return QuickLogEntry(
            date: Date(),
            snapshot: snapshot,
            pendingTodayNet: pendingToday.reduce(0) { $0 + $1.amount },
            pendingTodayCount: pendingToday.count
        )
    }
}

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let pendingTodayNet: Double
    let pendingTodayCount: Int

    var todayAggregate: WidgetSnapshot.TimeframeAggregate {
        snapshot.spending.byTimeframe[.today]
            ?? .init(net: 0, previousNet: 0, topCategories: [], expenseCount: 0)
    }

    /// Snapshot total + optimistic queued-today overlay.
    var todayNet: Double { todayAggregate.net + pendingTodayNet }
    var todayCount: Int { todayAggregate.expenseCount + pendingTodayCount }

    var templates: [WidgetSnapshot.QuickLogTemplate] {
        snapshot.quickLogTemplates ?? []
    }
}

// MARK: - Widget

struct QuickLogWidget: Widget {
    static let kind: String = "QuickLog"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: QuickLogTimelineProvider()) { entry in
            QuickLogEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SpendingBackground(themeId: entry.snapshot.activeThemeId)
                }
        }
        .configurationDisplayName("Quick Log")
        .description("Log your usual expenses in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry view (size router)

struct QuickLogEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickLogEntry

    var body: some View {
        switch family {
        case .systemMedium: QuickLogMediumView(entry: entry)
        default:            QuickLogSmallView(entry: entry)
        }
    }
}

// MARK: - Deep link

/// The "+" affordance — matches `DeepLinkURLs.addExpense` in the app.
private let addExpenseURL = URL(string: "cashlens://add-expense")!

// MARK: - Small

struct QuickLogSmallView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: QuickLogEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primary(for: scheme))
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(theme.primary(for: scheme))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 4)

            Text(WidgetMoneyFormatter.compact(entry.todayNet, currencyCode: entry.snapshot.currencyCode))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Spacer(minLength: 6)

            if entry.templates.isEmpty {
                QuickLogEmptyHint(compact: true)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(entry.templates.prefix(2).enumerated()), id: \.element.id) { idx, template in
                        QuickLogTemplateButton(
                            template: template,
                            currencyCode: entry.snapshot.currencyCode,
                            locked: idx > 0 && !entry.snapshot.isPro,
                            compact: true,
                            theme: theme
                        )
                    }
                }
            }
        }
        // Anywhere that isn't a button opens the add-expense sheet.
        .widgetURL(addExpenseURL)
    }
}

// MARK: - Medium

struct QuickLogMediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: QuickLogEntry

    var body: some View {
        let theme = WidgetTheme.resolve(id: entry.snapshot.activeThemeId)

        HStack(alignment: .top, spacing: 14) {
            // Left column: today hero + the "+" deep link.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primary(for: scheme))
                    Text("QUICK LOG")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(theme.primary(for: scheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(WidgetMoneyFormatter.compact(entry.todayNet, currencyCode: entry.snapshot.currencyCode))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(entry.todayCount) today")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Link(destination: addExpenseURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(theme.primary(for: scheme))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.primary(for: scheme).opacity(0.16)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: template buttons.
            VStack(spacing: 6) {
                if entry.templates.isEmpty {
                    Spacer(minLength: 0)
                    QuickLogEmptyHint(compact: false)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(entry.templates.prefix(3).enumerated()), id: \.element.id) { idx, template in
                        QuickLogTemplateButton(
                            template: template,
                            currencyCode: entry.snapshot.currencyCode,
                            locked: idx > 0 && !entry.snapshot.isPro,
                            compact: false,
                            theme: theme
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Template button

/// One tappable template chip. Free users get the first template
/// active; the rest render with a lock (still visible so the value of
/// Pro is obvious). A locked chip is not an intent Button — on the
/// Small family it falls through to the container's `widgetURL`, so
/// tapping it opens the app (where the paywall entry points live)
/// instead of silently logging.
struct QuickLogTemplateButton: View {
    @Environment(\.colorScheme) private var scheme
    let template: WidgetSnapshot.QuickLogTemplate
    let currencyCode: String
    let locked: Bool
    let compact: Bool
    let theme: WidgetTheme

    var body: some View {
        let color = Color(hex: template.hex) ?? theme.primary(for: scheme)

        if locked {
            chipLabel(color: color)
                .opacity(0.5)
        } else {
            Button(intent: QuickLogTemplateIntent(template: template)) {
                chipLabel(color: color)
            }
            .buttonStyle(.plain)
        }
    }

    private func chipLabel(color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: locked ? "lock.fill" : template.symbol)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(template.name)
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 3)
            Text(WidgetMoneyFormatter.compact(template.amount, currencyCode: currencyCode))
                .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                .fill(color.opacity(0.14))
        )
    }
}

// MARK: - Empty state

/// Shown when the user hasn't saved any templates yet.
struct QuickLogEmptyHint: View {
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No templates yet")
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            Text(compact ? "Save one in CashLens." : "Save a template in CashLens\nto log it in one tap.")
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    QuickLogWidget()
} timeline: {
    QuickLogEntry(date: .now, snapshot: .quickLogPreview, pendingTodayNet: 0, pendingTodayCount: 0)
}

#Preview("Medium", as: .systemMedium) {
    QuickLogWidget()
} timeline: {
    QuickLogEntry(date: .now, snapshot: .quickLogPreview, pendingTodayNet: 0, pendingTodayCount: 0)
}

private extension WidgetSnapshot {
    static var quickLogPreview: WidgetSnapshot {
        var s = WidgetSnapshot.preview
        s.quickLogTemplates = [
            .init(id: UUID(), name: "Coffee", amount: 4.50, categoryRaw: "Food",
                  customCategoryId: nil, symbol: "cup.and.saucer.fill", hex: "FFBEA0"),
            .init(id: UUID(), name: "Bus fare", amount: 2.75, categoryRaw: "Transportation",
                  customCategoryId: nil, symbol: "bus.fill", hex: "64BEFF"),
            .init(id: UUID(), name: "Lunch", amount: 12.00, categoryRaw: "Food",
                  customCategoryId: nil, symbol: "fork.knife", hex: "FFBEA0")
        ]
        return s
    }
}
