import SwiftUI

struct AutomationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AutomationSettings.shared
    @State private var showingShortcutInstructions = false
    @State private var showingSMSInstructions = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Card
                    statusCard
                    
                    // Apple Pay Card
                    applePayCard
                    
                    // SMS/UPI Card
                    smsUPICard
                    
                    // Setup Cards
                    setupCards
                    
                    // Advanced Settings Card
                    advancedCard
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(Color.systemBackground)
            .navigationTitle("Automation Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .foregroundColor(.appPrimary)
                    .fontWeight(.medium)
                }
            }
        }
        .sheet(isPresented: $showingShortcutInstructions) {
            ShortcutInstructionsView()
        }
        .sheet(isPresented: $showingSMSInstructions) {
            SMSInstructionsView()
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("STATUS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill((settings.isEnabled || settings.enableSMSAutomation) ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: (settings.isEnabled || settings.enableSMSAutomation) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor((settings.isEnabled || settings.enableSMSAutomation) ? .green : .red)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transaction Automation")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(automationStatusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text("Enable to automatically capture transaction data from multiple sources")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var automationStatusText: String {
        let applePayEnabled = settings.isEnabled
        let smsEnabled = settings.enableSMSAutomation
        
        if applePayEnabled && smsEnabled {
            return "Apple Pay & SMS Active"
        } else if applePayEnabled {
            return "Apple Pay Active"
        } else if smsEnabled {
            return "SMS Active"
        } else {
            return "Disabled"
        }
    }
    
    // MARK: - Apple Pay Card
    
    private var applePayCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("APPLE PAY AUTOMATION")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Main Toggle
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Pay automation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Automatically capture Apple Pay NFC transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("", isOn: $settings.isEnabled)
                        .tint(.appPrimary)
                }
                
                if settings.isEnabled {
                    Divider()
                    
                    // Auto-approve transactions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.appPrimary)
                            
                            Text("Auto-approve transactions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: $settings.autoApproveTransactions)
                                .tint(.appPrimary)
                        }
                        
                        if !settings.autoApproveTransactions {
                            Text("Transactions will be saved for manual review")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 24)
                        }
                    }
                    
                    // Require confirmation
                    if !settings.autoApproveTransactions {
                        HStack {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                            
                            Text("Require confirmation")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: $settings.requireConfirmation)
                                .tint(.appPrimary)
                        }
                    }
                    
                    // Notifications
                    HStack {
                        Image(systemName: "bell")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                        
                        Text("Notify on new transaction")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.notifyOnNewTransaction)
                            .tint(.appPrimary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - SMS/UPI Card
    
    private var smsUPICard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("SMS/UPI AUTOMATION")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // SMS automation toggle
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "message.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SMS automation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Parse UPI transaction details from SMS notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Toggle("", isOn: $settings.enableSMSAutomation)
                        .tint(.appPrimary)
                }
                
                if settings.enableSMSAutomation {
                    Divider()
                    
                    // UPI detection
                    HStack {
                        Image(systemName: "indianrupeesign.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.appPrimary)
                        
                        Text("UPI detection")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.enableUPIDetection)
                            .tint(.appPrimary)
                    }
                    
                    // Auto-approve UPI transactions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                            
                            Text("Auto-approve UPI transactions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: $settings.autoApproveUPITransactions)
                                .tint(.appPrimary)
                        }
                        
                        if !settings.autoApproveUPITransactions {
                            Text("UPI transactions will be saved for manual review")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 24)
                        }
                    }
                    
                    Divider()
                    
                    // Amount limits
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                            
                            Text("Amount Limits")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Minimum:")
                                    .font(.subheadline)
                                Spacer()
                                Text("₹\(Int(settings.minimumUPIAmount))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.appPrimary)
                            }
                            
                            Slider(value: $settings.minimumUPIAmount, in: 0...1000, step: 10)
                                .tint(.appPrimary)
                            
                            HStack {
                                Text("Maximum:")
                                    .font(.subheadline)
                                Spacer()
                                Text("₹\(Int(settings.maximumUPIAmount))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.appPrimary)
                            }
                            
                            Slider(value: $settings.maximumUPIAmount, in: 100...50000, step: 100)
                                .tint(.appPrimary)
                        }
                        .padding(.leading, 24)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    Text("Supported Banks & UPI Apps")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "smartphone")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UPI Apps")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("PhonePe, Google Pay, Paytm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "building.2")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Major Banks")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("SBI, HDFC Bank, ICICI Bank")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 12))
                            .foregroundColor(.appPrimary)
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Support")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("Most major Indian banks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Setup Cards
    
    private var setupCards: some View {
        VStack(spacing: 16) {
            HStack {
                Text("SETUP")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Apple Pay Instructions
                if settings.isEnabled {
                    Button(action: { 
                        HapticManager.shared.lightTap()
                        showingShortcutInstructions = true 
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "creditcard.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple Pay Setup")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Configure iOS Shortcuts for Apple Pay")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.tertiarySystemBackground)
                        .cornerRadius(12)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                
                // SMS Instructions
                if settings.enableSMSAutomation {
                    Button(action: { 
                        HapticManager.shared.lightTap()
                        showingSMSInstructions = true 
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "message.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SMS Automation Setup")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Configure SMS parsing for UPI transactions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color.tertiarySystemBackground)
                        .cornerRadius(12)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                
                // Open Shortcuts App
                if settings.isEnabled || settings.enableSMSAutomation {
                    Button(action: { 
                        HapticManager.shared.lightTap()
                        openShortcutsApp() 
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.appPrimary.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appPrimary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open Shortcuts App")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Launch iOS Shortcuts to configure automations")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [Color.appPrimary.opacity(0.1), Color.appSecondary.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Advanced Card
    
    private var advancedCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ADVANCED")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Smart categorization
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "brain")
                            .font(.system(size: 18))
                            .foregroundColor(.purple)
                    }
                    
                    Text("Smart categorization")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.enableSmartCategorization)
                        .tint(.appPrimary)
                }
                
                Divider()
                
                // Default payment method
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "creditcard")
                            .font(.system(size: 18))
                            .foregroundColor(.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default payment method")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(settings.defaultPaymentMethod)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Test SMS Parser
                NavigationLink(destination: SMSTestView()) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test SMS Parser")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Debug UPI SMS parsing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Clear processed transactions
                Button(action: {
                    HapticManager.shared.lightTap()
                    TransactionAutomationManager.shared.processedTransactions.removeAll()
                }) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "trash")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                        }
                        
                        Text("Clear processed transactions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                        
                        Spacer()
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            Text("Advanced configuration options for all automation sources")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Actions
    
    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - SMS Instructions View

struct SMSInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Setup SMS Automation")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Automatically parse UPI transactions from SMS notifications")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    
                    // Steps
                    VStack(spacing: 16) {
                        ForEach(smsSetupSteps.indices, id: \.self) { index in
                            SMSSetupStepCard(
                                step: index + 1,
                                title: smsSetupSteps[index].title,
                                description: smsSetupSteps[index].description,
                                icon: smsSetupSteps[index].icon,
                                color: smsSetupSteps[index].color
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Supported Banks Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "building.2")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                            }
                            
                            Text("Supported Banks & UPI Apps")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            SupportedServiceRow(
                                title: "UPI Apps",
                                services: ["PhonePe", "Google Pay", "Paytm"],
                                icon: "smartphone",
                                color: .green
                            )
                            
                            SupportedServiceRow(
                                title: "Major Banks",
                                services: ["SBI", "HDFC Bank", "ICICI Bank"],
                                icon: "building.2",
                                color: .blue
                            )
                            
                            SupportedServiceRow(
                                title: "Support",
                                services: ["Most major Indian banks", "Generic UPI transaction formats"],
                                icon: "checkmark.shield",
                                color: .appPrimary
                            )
                        }
                    }
                    .padding(20)
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .background(Color.systemBackground)
            .navigationTitle("SMS Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .foregroundColor(.appPrimary)
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    private var smsSetupSteps: [(title: String, description: String, icon: String, color: Color)] {
        [
            ("Open Shortcuts App", "Open the Shortcuts app on your iPhone", "square.grid.3x3", .blue),
            ("Create SMS Automation", "Tap 'Automation' tab → '+' → 'Create Personal Automation'", "plus.circle", .green),
            ("Select Message Trigger", "Select 'Message' from the list of triggers", "message", .purple),
            ("Configure SMS Filter", "Set 'Sender' to your bank's SMS number or leave blank for all. Add keywords like 'UPI', 'debited', 'paid'", "slider.horizontal.3", .orange),
            ("Add CashLens Action", "Choose 'New Blank Automation' → Search for 'CashLens' → Select 'Parse UPI SMS'", "square.and.arrow.down", .appPrimary),
            ("Configure Parameters", "Set 'SMS Text' to 'Contents of Message' and 'Sender' to 'Sender'", "gearshape", .secondary)
        ]
    }
}

struct SMSSetupStepCard: View {
    let step: Int
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            // Step number
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Text("\(step)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct SupportedServiceRow: View {
    let title: String
    let services: [String]
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(services, id: \.self) { service in
                        Text("• \(service)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shortcut Instructions View

struct ShortcutInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Setup Apple Pay Automation")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Configure iOS Shortcuts to automatically capture Apple Pay transactions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    
                    // Steps
                    VStack(spacing: 16) {
                        ForEach(applePaySetupSteps.indices, id: \.self) { index in
                            SMSSetupStepCard(
                                step: index + 1,
                                title: applePaySetupSteps[index].title,
                                description: applePaySetupSteps[index].description,
                                icon: applePaySetupSteps[index].icon,
                                color: applePaySetupSteps[index].color
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Important Notes
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.orange)
                            }
                            
                            Text("Important Notes")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            ImportantNoteRow(
                                icon: "hand.tap",
                                text: "Only works with Apple Pay NFC transactions (not online payments)"
                            )
                            
                            ImportantNoteRow(
                                icon: "wallet.pass",
                                text: "Cards must be added to Apple Wallet"
                            )
                            
                            ImportantNoteRow(
                                icon: "gear",
                                text: "Automation runs automatically when you make a payment"
                            )
                            
                            ImportantNoteRow(
                                icon: "checkmark.shield",
                                text: "Transactions can be reviewed before adding to expenses"
                            )
                        }
                    }
                    .padding(20)
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .background(Color.systemBackground)
            .navigationTitle("Apple Pay Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.lightTap()
                        dismiss()
                    }
                    .foregroundColor(.appPrimary)
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    private var applePaySetupSteps: [(title: String, description: String, icon: String, color: Color)] {
        [
            ("Open Shortcuts App", "Open the Shortcuts app on your iPhone", "square.grid.3x3", .blue),
            ("Create Personal Automation", "Tap 'Automation' tab → '+' → 'Create Personal Automation'", "plus.circle", .green),
            ("Select Transaction Trigger", "Scroll down and select 'Transaction' from the list", "creditcard", .purple),
            ("Configure Cards", "Select the cards you want to monitor. Choose all categories and set to 'Run Immediately'", "gearshape", .orange),
            ("Add CashLens Action", "Choose 'New Blank Automation' → Search for 'CashLens' → Select 'Add Transaction'", "square.and.arrow.down", .appPrimary),
            ("Configure Parameters", "Set Amount to 'Amount', Merchant to 'Merchant', and configure other settings as needed", "slider.horizontal.3", .secondary)
        ]
    }
    
    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
    }
}

struct ImportantNoteRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.orange)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Example SMS View

struct ExampleSMS: View {
    let title: String
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.green)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
                .background(Color(.systemBackground))
                .cornerRadius(8)
        }
    }
}

// MARK: - Helper Views

struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number
            Text("\(number)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

#Preview {
    AutomationSettingsView()
} 
