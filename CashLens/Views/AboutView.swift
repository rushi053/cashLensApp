import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Get version and build from Info.plist
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "Version \(version) (\(build))"
    }
    
    private var whatsNewTitle: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        return "What’s New in v\(version)"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App Logo
                    VStack(spacing: 16) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.appPrimary)
                            .padding()
                            .background(
                                Circle()
                                    .fill(Color.appPrimary.opacity(0.1))
                                    .frame(width: 160, height: 160)
                            )
                        
                        Text("CashLens")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(versionString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                    
                    // App Description
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About CashLens")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("CashLens is a comprehensive personal finance app designed to help you track expenses, manage subscriptions, and gain insights into your spending habits with beautiful visualizations.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Text("Key Features:")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            featureRow(icon: "plus.circle.fill", text: "Track expenses with smart categorization")
                            featureRow(icon: "arrow.clockwise.circle.fill", text: "Manage recurring subscriptions with notifications")
                            featureRow(icon: "chart.pie.fill", text: "Beautiful spending statistics and insights")
                            featureRow(icon: "tag.fill", text: "Create custom categories with personalized icons")
                            featureRow(icon: "slider.horizontal.3", text: "Customize your Home summary cards (including custom categories)")
                            featureRow(icon: "dollarsign.circle.fill", text: "Support for 150+ global currencies")
                            featureRow(icon: "calendar", text: "Filter data by flexible time periods")
                            featureRow(icon: "square.and.arrow.up", text: "Export data in CSV and JSON formats")
                            featureRow(icon: "square.and.arrow.down", text: "Import data to restore complete financial history")
                            featureRow(icon: "paintbrush.fill", text: "Customizable appearance with dark/light modes")
                            featureRow(icon: "bell.fill", text: "Smart notifications: renewals, digests, and backup reminders (all opt‑in)")
                            featureRow(icon: "shield.fill", text: "Local data storage - your privacy protected")
                        }
                        .padding(.leading, 8)
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    
                    // What's New Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text(whatsNewTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            featureRow(icon: "bell.badge.fill", text: "Weekly & monthly digests (opt‑in) with deep links into your expenses")
                            featureRow(icon: "externaldrive.fill.badge.timemachine", text: "Backup reminders (opt‑in) and one‑tap export to Files")
                            featureRow(icon: "chart.pie.fill", text: "More visual statistics: category share + spending heatmap + cleaner trend chart")
                            featureRow(icon: "calendar", text: "Date range filtering across Statistics & All Expenses")
                            featureRow(icon: "tag.fill", text: "Custom categories everywhere: filters and Summary customization")
                            featureRow(icon: "slider.horizontal.3", text: "More personalization: default Home time frame + improved UI polish")
                            featureRow(icon: "checkmark.circle.fill", text: "Stability fixes and better data sync for subscriptions & categories")
                        }
                        .padding(.leading, 8)
                        
                        Text("These updates focus on clarity, consistency, and helpful reminders—while keeping CashLens fast, private, and simple.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    
                    // Contact Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Contact")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("For any bugs, feature requests, or feedback, feel free to reach out!")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Link(destination: URL(string: "mailto:email@rushiraj.me")!) {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.appPrimary)
                                Text("email@rushiraj.me")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.secondarySystemBackground)
                            .cornerRadius(10)
                        }
                        Link(destination: URL(string: "https://cashlens.app")!) {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.appPrimary)
                                Text("cashlens.app")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.secondarySystemBackground)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    
                    // Developer Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Developer")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("CashLens was developed by Rushiraj Jadeja with a focus on creating an intuitive, powerful, and privacy-first personal finance experience.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Text("© 2025 Rushiraj Jadeja. All rights reserved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    
                    // Privacy Policy
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Privacy & Security")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("CashLens respects your privacy. All your financial data is stored locally on your device and is never shared with third parties. Your subscription data, custom categories, and expense history remain completely private and under your control.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitle("About", displayMode: .inline)
            .navigationBarItems(trailing: 
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .fontWeight(.bold)
                        .foregroundColor(.appPrimary)
                }
            )
            .background(Color.systemBackground)
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.appPrimary)
                .frame(width: 24, height: 24)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
} 