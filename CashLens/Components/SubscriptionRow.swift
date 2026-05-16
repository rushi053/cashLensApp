import SwiftUI

/// One row in the Subscriptions list.
///
/// Design goals vs. the legacy row:
/// - **One** status line per row (no redundant "Soon" label + colored dot + due
///   date line + inline "PAUSED" badge all competing).
/// - Monthly equivalent is only shown when the billing frequency is *not*
///   monthly (otherwise it repeats the amount).
/// - Mark-as-Paid is a compact inline action, not a full-row button — the row
///   rhythm stays tight whether the sub is due or not.
/// - Swipe actions provide quick pause / resume / delete without forcing the
///   user into a context menu.
struct SubscriptionRow: View {
    let subscription: Subscription
    let monthlyEquivalentText: String?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMarkPaid: (() -> Void)?
    let onDelete: (() -> Void)?

    // MARK: - Derived

    private var tint: Color {
        Color.forCategory(subscription.category.color)
    }

    /// Canonical status the row communicates. `.paused`, `.overdue`, `.dueToday`,
    /// `.dueSoon`, `.scheduled` — mutually exclusive.
    private enum Status {
        case paused, overdue(Int), dueToday, dueSoon(Int), scheduled
    }

    private var status: Status {
        if !subscription.isActive { return .paused }
        let days = subscription.daysUntilNext
        if days < 0 { return .overdue(abs(days)) }
        if days == 0 { return .dueToday }
        if days <= 3 { return .dueSoon(days) }
        return .scheduled
    }

    private var statusColor: Color {
        switch status {
        case .paused: return .secondary
        case .overdue, .dueToday: return .red
        case .dueSoon: return .orange
        case .scheduled: return .green
        }
    }

    private var statusText: String {
        switch status {
        case .paused:
            return "Paused"
        case .overdue(let d):
            return "Overdue by \(d) day\(d == 1 ? "" : "s")"
        case .dueToday:
            return "Due today"
        case .dueSoon(let d):
            return "Due in \(d) day\(d == 1 ? "" : "s")"
        case .scheduled:
            return "Renews \(subscription.formattedNextDueDate)"
        }
    }

    private var showMarkAsPaid: Bool {
        onMarkPaid != nil
            && subscription.isActive
            && subscription.daysUntilNext <= 0
    }

    // MARK: - Body

    var body: some View {
        Button(action: {
            HapticManager.shared.lightTap()
            onEdit()
        }) {
            HStack(spacing: Theme.Spacing.lg) {
                iconBadge

                VStack(alignment: .leading, spacing: 4) {
                    titleLine
                    statusLine
                    if let monthlyEquivalentText, subscription.isActive,
                       subscription.frequency != .monthly {
                        Text("≈ \(monthlyEquivalentText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Theme.Spacing.sm)

                trailing
            }
            .padding(Theme.Spacing.lg)
            // `cardSurface()` already paints the elevation (crisp + soft
            // shadow + hairline border). A second `.softShadow()` on top
            // tripled the per-row shadow passes during scroll — the
            // audit caught this as a P0 reason Subscriptions scrolled
            // jittery with many rows. One elevation source per cell.
            .cardSurface()
            .opacity(subscription.isActive ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuContent
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                HapticManager.shared.lightTap()
                onToggle()
            } label: {
                Label(
                    subscription.isActive ? "Pause" : "Resume",
                    systemImage: subscription.isActive ? "pause.fill" : "play.fill"
                )
            }
            .tint(subscription.isActive ? .orange : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button(role: .destructive) {
                    HapticManager.shared.mediumTap()
                    onDelete()
                    HapticManager.shared.success()
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
            }
        }
    }

    // MARK: - Pieces

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(subscription.isActive ? 0.22 : 0.12))
                .frame(width: 46, height: 46)

            Image(systemName: subscription.category.icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(tint.opacity(subscription.isActive ? 1.0 : 0.6))
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(subscription.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("· \(subscription.frequency.rawValue)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(statusColor)
                .lineLimit(1)
        }
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(subscription.formattedAmount)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if showMarkAsPaid, let onMarkPaid {
                Button {
                    HapticManager.shared.mediumTap()
                    onMarkPaid()
                    HapticManager.shared.success()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Mark paid")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appPrimary)
                    .clipShape(Capsule())
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            } else if subscription.reminderEnabled && subscription.isActive {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
        }

        Button(action: onToggle) {
            Label(
                subscription.isActive ? "Pause" : "Resume",
                systemImage: subscription.isActive ? "pause.circle" : "play.circle"
            )
        }

        if subscription.isActive && subscription.daysUntilNext <= 0, let onMarkPaid {
            Button(action: onMarkPaid) {
                Label("Mark as Paid", systemImage: "checkmark.circle")
            }
        }

        if let onDelete {
            Button(role: .destructive, action: {
                HapticManager.shared.mediumTap()
                onDelete()
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        SubscriptionRow(
            subscription: Subscription.sampleData[0],
            monthlyEquivalentText: nil,
            onToggle: {},
            onEdit: {},
            onMarkPaid: {},
            onDelete: {}
        )

        SubscriptionRow(
            subscription: {
                var s = Subscription.sampleData[1]
                s.isActive = false
                return s
            }(),
            monthlyEquivalentText: nil,
            onToggle: {},
            onEdit: {},
            onMarkPaid: nil,
            onDelete: {}
        )

        SubscriptionRow(
            subscription: {
                var s = Subscription.sampleData[2]
                s.nextDueDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                return s
            }(),
            monthlyEquivalentText: nil,
            onToggle: {},
            onEdit: {},
            onMarkPaid: {},
            onDelete: {}
        )
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
