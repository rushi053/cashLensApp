import SwiftUI

struct SubscriptionRow: View {
    let subscription: Subscription
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMarkPaid: (() -> Void)?
    let onDelete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Main subscription info
            Button(action: {
                HapticManager.shared.impact(style: .light)
                onEdit()
            }) {
                HStack(spacing: 16) {
                    // Category icon - matching ExpenseCard style
                    ZStack {
                        Circle()
                            .fill(Color.forCategory(subscription.category.color).opacity(subscription.isActive ? 0.3 : 0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: subscription.category.icon)
                            .font(.system(size: 20))
                            .foregroundColor(Color.forCategory(subscription.category.color).opacity(subscription.isActive ? 1.0 : 0.5))
                    }
                    
                    // Subscription details - improved layout
                    VStack(alignment: .leading, spacing: 6) {
                        // Service name with status
                        HStack(spacing: 8) {
                            Text(subscription.name)
                                .font(.headline)
                                .foregroundColor(subscription.isActive ? .primary : .secondary)
                                .lineLimit(1)
                            
                            if !subscription.isActive {
                                Text("PAUSED")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                        }
                        
                        // Frequency
                        Text(subscription.frequency.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Due date - better aligned and styled
                        if subscription.daysUntilNext == 0 {
                            Text("Due today")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        } else if subscription.daysUntilNext < 0 {
                            Text("Overdue by \(abs(subscription.daysUntilNext)) \(abs(subscription.daysUntilNext) == 1 ? "day" : "days")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        } else if subscription.daysUntilNext <= 3 && subscription.isActive {
                            Text("Due in \(subscription.daysUntilNext) \(subscription.daysUntilNext == 1 ? "day" : "days")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        } else {
                            Text("Due \(subscription.formattedNextDueDate)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Notes if available
                        if let notes = subscription.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Amount and visual indicator - right aligned
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(subscription.formattedAmount)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(subscription.isActive ? .primary : .secondary)
                        
                        // Status indicator with proper alignment
                        HStack(spacing: 4) {
                            if subscription.isActive {
                                Circle()
                                    .fill(subscription.daysUntilNext <= 0 ? Color.red : 
                                         subscription.daysUntilNext <= 3 ? Color.orange : Color.green)
                                    .frame(width: 8, height: 8)
                                
                                if subscription.daysUntilNext <= 0 {
                                    Text(subscription.daysUntilNext == 0 ? "Due" : "Overdue")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                } else if subscription.daysUntilNext <= 3 {
                                    Text("Soon")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.orange)
                                } else {
                                    Text("Active")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 8, height: 8)
                                
                                Text("Paused")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.secondarySystemBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Mark as Paid button for due/overdue subscriptions
            if subscription.isActive && subscription.daysUntilNext <= 0 && onMarkPaid != nil {
                Button(action: {
                    HapticManager.shared.impact(style: .medium)
                    onMarkPaid?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text("Mark as Paid")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.mauve, Color.mauve.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.mauve.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(action: onToggle) {
                Label(
                    subscription.isActive ? "Pause" : "Resume",
                    systemImage: subscription.isActive ? "pause.circle" : "play.circle"
                )
            }
            
            // Add Mark as Paid option in context menu for due subscriptions
            if subscription.isActive && subscription.daysUntilNext <= 0 && onMarkPaid != nil {
                Button(action: { onMarkPaid?() }) {
                    Label("Mark as Paid", systemImage: "checkmark.circle")
                }
            }
            
            Button(role: .destructive, action: {
                HapticManager.shared.impact(style: .medium)
                onDelete?()
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct SubscriptionRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            SubscriptionRow(
                subscription: Subscription.sampleData[0],
                onToggle: {},
                onEdit: {},
                onMarkPaid: nil,
                onDelete: nil
            )
            
            SubscriptionRow(
                subscription: {
                    var subscription = Subscription.sampleData[1]
                    subscription.isActive = false
                    return subscription
                }(),
                onToggle: {},
                onEdit: {},
                onMarkPaid: nil,
                onDelete: nil
            )
            
            SubscriptionRow(
                subscription: {
                    var subscription = Subscription.sampleData[2]
                    var calendar = Calendar.current
                    subscription.nextDueDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    return subscription
                }(),
                onToggle: {},
                onEdit: {},
                onMarkPaid: nil,
                onDelete: nil
            )
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
} 