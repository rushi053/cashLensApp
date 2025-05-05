import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Get version and build from Info.plist
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "Version \(version) (\(build))"
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
                        
                        Text("CashLens is a personal finance app designed to help you track your expenses effectively.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Text("With CashLens, you can:")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            featureRow(icon: "plus.circle.fill", text: "Add and categorize expenses")
                            featureRow(icon: "chart.pie.fill", text: "View spending statistics and trends")
                            featureRow(icon: "dollarsign.circle.fill", text: "Support for multiple currencies")
                            featureRow(icon: "calendar", text: "Filter expenses by time period")
                            featureRow(icon: "square.and.arrow.up", text: "Export your financial data")
                        }
                        .padding(.leading, 8)
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(16)
                    
                    // Contact Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Contact")
                            .font(.title2)
                            .fontWeight(.bold)
                        
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
                        
                        Text("CashLens was developed by Rushiraj Jadeja as a demonstration of SwiftUI capabilities for expense tracking applications.")
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
                        Text("Privacy")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("CashLens respects your privacy. All your financial data is stored locally on your device and is not shared with any third parties.")
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