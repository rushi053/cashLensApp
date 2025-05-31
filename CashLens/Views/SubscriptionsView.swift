import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    @StateObject private var subscriptionViewModel = SubscriptionViewModel()
    @State private var showingAddSubscription = false
    @State private var selectedSubscription: Subscription?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header section
                    headerSection
                    
                    // Statistics section  
                    statisticsSection
                    
                    // Content section
                    if subscriptionViewModel.subscriptions.isEmpty {
                        emptyStateView
                    } else {
                        subscriptionsSection
                    }
                }
            }
            .background(Color(.systemBackground))
            .onAppear {
                subscriptionViewModel.setExpenseViewModel(expenseViewModel)
                subscriptionViewModel.loadSubscriptions()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingAddSubscription) {
            AddSubscriptionView(subscriptionViewModel: subscriptionViewModel)
                .environmentObject(expenseViewModel)
        }
        .sheet(item: $selectedSubscription) { subscription in
            AddSubscriptionView(
                subscriptionViewModel: subscriptionViewModel,
                editingSubscription: subscription
            )
            .environmentObject(expenseViewModel)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Top padding
            Rectangle()
                .fill(Color.clear)
                .frame(height: 20)
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscriptions")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("\(subscriptionViewModel.activeSubscriptionsCount) active subscription\(subscriptionViewModel.activeSubscriptionsCount == 1 ? "" : "s")")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    HapticManager.shared.impact(style: .light)
                    showingAddSubscription = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.mauve, Color.mauve.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color.mauve.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
    
    private var statisticsSection: some View {
        VStack(spacing: 16) {
            // Large Stats Card - removed extra padding and background
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Spending")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(subscriptionViewModel.formattedTotalMonthlyAmount(currency: expenseViewModel.selectedCurrency))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.mauve.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18))
                            .foregroundColor(.mauve)
                    }
                }
                
                // Mini stats row - back to horizontal layout
                HStack(spacing: 8) {
                    // Due Soon card with tap functionality
                    Button(action: {
                        HapticManager.shared.impact(style: .light)
                        if subscriptionViewModel.activeFilter == .dueSoon {
                            subscriptionViewModel.clearFilter()
                        } else {
                            subscriptionViewModel.setFilter(.dueSoon)
                        }
                    }) {
                        StatMiniCard(
                            title: "Due Soon",
                            value: "\(subscriptionViewModel.upcomingSubscriptions.count)",
                            icon: "clock.fill",
                            color: subscriptionViewModel.upcomingSubscriptions.count > 0 ? .orange : .green,
                            isSelected: subscriptionViewModel.activeFilter == .dueSoon
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Active subscriptions card - also make tappable
                    Button(action: {
                        HapticManager.shared.impact(style: .light)
                        if subscriptionViewModel.activeFilter == .active {
                            subscriptionViewModel.clearFilter()
                        } else {
                            subscriptionViewModel.setFilter(.active)
                        }
                    }) {
                        StatMiniCard(
                            title: "Active",
                            value: "\(subscriptionViewModel.activeSubscriptionsCount)",
                            icon: "checkmark.circle.fill",
                            color: .green,
                            isSelected: subscriptionViewModel.activeFilter == .active
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Total card - make tappable to show all
                    Button(action: {
                        HapticManager.shared.impact(style: .light)
                        subscriptionViewModel.clearFilter()
                    }) {
                        StatMiniCard(
                            title: "Total",
                            value: "\(subscriptionViewModel.subscriptions.count)",
                            icon: "creditcard.and.123",
                            color: .blue,
                            isSelected: subscriptionViewModel.activeFilter == .all
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)
            
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.mauve.opacity(0.1), Color.mauve.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "creditcard.and.123")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.mauve)
            }
            
            VStack(spacing: 12) {
                Text("No Subscriptions Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Track your recurring expenses like Netflix, Spotify, or gym memberships and never miss a payment")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }
            
            Button(action: {
                HapticManager.shared.impact(style: .medium)
                showingAddSubscription = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Add Your First Subscription")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.mauve, Color.mauve.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: Color.mauve.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    private var subscriptionsSection: some View {
        VStack(spacing: 0) {
            // Filter Status Header (only show when filter is active)
            if subscriptionViewModel.activeFilter != .all {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: subscriptionViewModel.activeFilter.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.mauve)
                        
                        Text("Showing: \(subscriptionViewModel.activeFilter.title)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("(\(subscriptionViewModel.filteredSubscriptions.count))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        HapticManager.shared.impact(style: .light)
                        subscriptionViewModel.clearFilter()
                    }) {
                        HStack(spacing: 4) {
                            Text("Clear")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.mauve)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.mauve.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Section Header
            HStack {
                Text(subscriptionViewModel.activeFilter == .all ? "Your Subscriptions" : subscriptionViewModel.activeFilter.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            
            // Subscriptions List
            let subscriptionsToShow = subscriptionViewModel.activeFilter == .all ? 
                subscriptionViewModel.subscriptions : subscriptionViewModel.filteredSubscriptions
                
            LazyVStack(spacing: 16) {
                ForEach(subscriptionsToShow) { subscription in
                    SubscriptionRow(
                        subscription: subscription,
                        onToggle: {
                            HapticManager.shared.impact(style: .light)
                            Task {
                                await subscriptionViewModel.toggleSubscriptionStatus(subscription)
                            }
                        },
                        onEdit: {
                            selectedSubscription = subscription
                        },
                        onMarkPaid: subscription.isActive && subscription.daysUntilNext <= 0 ? {
                            // Mark subscription as paid - create expense and update next due date
                            Task {
                                await subscriptionViewModel.markSubscriptionAsPaid(subscription)
                            }
                        } : nil,
                        onDelete: {
                            HapticManager.shared.impact(style: .medium)
                            subscriptionViewModel.deleteSubscription(subscription)
                            HapticManager.shared.success()
                        }
                    )
                }
                .onDelete(perform: { offsets in
                    deleteSubscriptions(offsets: offsets, from: subscriptionsToShow)
                })
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 120) // Adjusted padding for tab bar and floating button
            
            // Empty state for filtered results
            if subscriptionsToShow.isEmpty && subscriptionViewModel.activeFilter != .all {
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 40)
                    
                    Image(systemName: subscriptionViewModel.activeFilter.icon)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("No \(subscriptionViewModel.activeFilter.title.lowercased()) subscriptions")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Try selecting a different filter or add a new subscription")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        subscriptionViewModel.clearFilter()
                    }) {
                        Text("Show All Subscriptions")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.mauve)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.mauve.opacity(0.1))
                            .cornerRadius(20)
                    }
                    
                    Spacer()
                        .frame(height: 60)
                }
                .padding(.horizontal, 32)
            }
        }
    }
    
    private func deleteSubscriptions(offsets: IndexSet, from subscriptions: [Subscription]) {
        for index in offsets {
            let subscription = subscriptions[index]
            subscriptionViewModel.deleteSubscription(subscription)
        }
        HapticManager.shared.success()
    }
}

// Mini Stat Card Component
struct StatMiniCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let isSelected: Bool
    
    init(title: String, value: String, icon: String, color: Color, isSelected: Bool = false) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.isSelected = isSelected
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color.secondarySystemBackground.opacity(0.7))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.mauve : Color.clear, lineWidth: 2)
        )
    }
}

struct SubscriptionsView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionsView()
            .environmentObject(ExpenseViewModel())
    }
} 