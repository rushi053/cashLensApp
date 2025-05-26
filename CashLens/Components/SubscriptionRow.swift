import SwiftUI

struct SubscriptionRow: View {
    let subscription: Subscription
    let onToggle: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
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
                
                // Subscription details - matching ExpenseCard typography
                VStack(alignment: .leading, spacing: 4) {
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
                    
                    // Frequency and due date
                    HStack(spacing: 8) {
                        Text(subscription.frequency.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if subscription.daysUntilNext == 0 {
                            Text("Due today")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        } else if subscription.daysUntilNext <= 3 && subscription.isActive {
                            Text("Due in \(subscription.daysUntilNext) days")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        } else {
                            Text("Due \(subscription.formattedNextDueDate)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
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
                
                // Amount and status - matching ExpenseCard style
                VStack(alignment: .trailing, spacing: 4) {
                    Text(subscription.formattedAmount)
                        .font(.headline)
                        .foregroundColor(subscription.isActive ? .primary : .secondary)
                    
                    if subscription.isActive {
                        if subscription.daysUntilNext == 0 {
                            Text("Today")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if subscription.daysUntilNext <= 3 {
                            Text("\(subscription.daysUntilNext) days")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("\(subscription.daysUntilNext) days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Paused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        subscription.daysUntilNext == 0 && subscription.isActive ? 
                            Color.red.opacity(0.3) : 
                            Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
            
            Button(role: .destructive, action: {
                // This would need to be handled by parent view
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
                onEdit: {}
            )
            
            SubscriptionRow(
                subscription: {
                    var subscription = Subscription.sampleData[1]
                    subscription.isActive = false
                    return subscription
                }(),
                onToggle: {},
                onEdit: {}
            )
            
            SubscriptionRow(
                subscription: {
                    var subscription = Subscription.sampleData[2]
                    var calendar = Calendar.current
                    subscription.nextDueDate = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    return subscription
                }(),
                onToggle: {},
                onEdit: {}
            )
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
} 