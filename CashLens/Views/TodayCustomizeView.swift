import SwiftUI

// MARK: - Today section model

/// Identifies each customizable section on the Today screen. The
/// budget verdict is deliberately NOT in this list — it's the
/// screen's anchor ("am I OK?" is the first pixel, per TodayView's
/// contract) and stays pinned at the top for everyone.
///
/// Raw strings round-trip through UserDefaults, so reordering or
/// renaming enum cases later won't corrupt a stored layout.
enum TodaySectionID: String, CaseIterable, Identifiable {
    case summary
    case upcoming
    case weekStrip
    case recent
    case insight

    var id: String { rawValue }

    /// The default top-to-bottom order for users who never customize.
    /// Mirrors the pre-customization Today layout exactly.
    static let defaultOrder: [TodaySectionID] = [
        .summary, .upcoming, .weekStrip, .recent, .insight
    ]

    var title: String {
        switch self {
        case .summary:   return "Summary"
        case .upcoming:  return "Upcoming Subscriptions"
        case .weekStrip: return "This Week"
        case .recent:    return "Recent"
        case .insight:   return "Insight"
        }
    }

    var subtitle: String {
        switch self {
        case .summary:   return "Total spent and top category"
        case .upcoming:  return "Bills due in the next two weeks"
        case .weekStrip: return "Last 7 days at a glance"
        case .recent:    return "Your latest three expenses"
        case .insight:   return "One observation about your spending"
        }
    }

    var icon: String {
        switch self {
        case .summary:   return "square.grid.2x2"
        case .upcoming:  return "calendar.badge.clock"
        case .weekStrip: return "chart.bar.xaxis"
        case .recent:    return "clock.arrow.circlepath"
        case .insight:   return "lightbulb"
        }
    }

    // MARK: - Layout persistence

    /// Restores the saved layout. Unknown raw values (from a future
    /// app version) are dropped; sections missing from the stored
    /// order (added after the user last saved) are appended in
    /// default-order position so new features are visible by default.
    static func loadLayout() -> (order: [TodaySectionID], hidden: Set<TodaySectionID>) {
        let defaults = UserDefaults.standard

        var order: [TodaySectionID]
        if let raw = defaults.stringArray(forKey: UserDefaultsKeys.todaySectionOrder) {
            order = raw.compactMap(TodaySectionID.init(rawValue:))
            for section in defaultOrder where !order.contains(section) {
                order.append(section)
            }
        } else {
            order = defaultOrder
        }

        let hiddenRaw = defaults.stringArray(forKey: UserDefaultsKeys.todayHiddenSections) ?? []
        let hidden = Set(hiddenRaw.compactMap(TodaySectionID.init(rawValue:)))

        return (order, hidden)
    }

    static func saveLayout(order: [TodaySectionID], hidden: Set<TodaySectionID>) {
        let defaults = UserDefaults.standard
        defaults.set(order.map(\.rawValue), forKey: UserDefaultsKeys.todaySectionOrder)
        defaults.set(hidden.map(\.rawValue).sorted(), forKey: UserDefaultsKeys.todayHiddenSections)
    }
}

// MARK: - Customize sheet

/// "Customize Today" — lets the user reorder and hide the sections
/// below the pinned budget verdict. Changes apply live (the Today
/// screen behind the sheet re-renders as you drag) and persist
/// immediately, so there's no Save/Cancel ceremony — dismiss when
/// it looks right.
struct TodayCustomizeView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var sectionOrder: [TodaySectionID]
    @Binding var hiddenSections: Set<TodaySectionID>

    private var isDefaultLayout: Bool {
        sectionOrder == TodaySectionID.defaultOrder && hiddenSections.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Customize Today",
                subtitle: "Drag to reorder · tap to show or hide",
                onClose: { dismiss() },
                trailing: {
                    if !isDefaultLayout {
                        Button {
                            HapticManager.shared.lightTap()
                            withAnimation(Theme.Motion.tap) {
                                sectionOrder = TodaySectionID.defaultOrder
                                hiddenSections = []
                            }
                            persist()
                        } label: {
                            Text("Reset")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.appPrimary)
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset to default layout")
                    } else {
                        SheetHeaderSpacer()
                    }
                }
            )

            List {
                Section {
                    pinnedVerdictRow
                } footer: {
                    Text("Your budget verdict always stays on top — it's the one thing Today never hides.")
                }

                Section {
                    ForEach(sectionOrder) { section in
                        sectionRow(section)
                    }
                    .onMove { from, to in
                        sectionOrder.move(fromOffsets: from, toOffset: to)
                        HapticManager.shared.selectionChanged()
                        persist()
                    }
                } footer: {
                    Text("Hidden sections keep their data — they just don't appear on Today.")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Medium detent first: with the sheet at half height the
        // Today screen stays visible above it, so reorders and
        // show/hide toggles preview live as you make them.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Non-interactive row for the pinned verdict, so the list tells
    /// the full story of the screen instead of starting mid-way.
    private var pinnedVerdictRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            rowGlyph("gauge.with.needle", tint: .appPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Budget Verdict")
                    .font(Theme.Typography.rowTitle)
                    .foregroundColor(.primary)
                Text("Spending status, projection and quick stats")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Image(systemName: "pin.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .deleteDisabled(true)
        .moveDisabled(true)
    }

    private func sectionRow(_ section: TodaySectionID) -> some View {
        let isVisible = !hiddenSections.contains(section)
        return Button {
            HapticManager.shared.lightTap()
            withAnimation(Theme.Motion.tap) {
                if isVisible {
                    hiddenSections.insert(section)
                } else {
                    hiddenSections.remove(section)
                }
            }
            persist()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                rowGlyph(section.icon, tint: isVisible ? .appPrimary : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundColor(isVisible ? .primary : .secondary)
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(isVisible ? .monochrome : .hierarchical)
                    .foregroundColor(isVisible ? .appPrimary : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .deleteDisabled(true)
        .accessibilityLabel("\(section.title), \(isVisible ? "visible" : "hidden")")
        .accessibilityHint(isVisible ? "Double tap to hide from Today" : "Double tap to show on Today")
    }

    private func rowGlyph(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(tint)
            .frame(width: 30, height: 30)
    }

    private func persist() {
        TodaySectionID.saveLayout(order: sectionOrder, hidden: hiddenSections)
    }
}

#if DEBUG
struct TodayCustomizeView_Previews: PreviewProvider {
    static var previews: some View {
        TodayCustomizeView(
            sectionOrder: .constant(TodaySectionID.defaultOrder),
            hiddenSections: .constant([])
        )
    }
}
#endif
