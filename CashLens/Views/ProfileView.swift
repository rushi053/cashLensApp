import SwiftUI
import Foundation
import StoreKit

struct ProfileView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var isEditingName = false
    @State private var tempUserName = ""
    @State private var showingCurrencyPicker = false
    @State private var showingAppearancePicker = false
    @State private var showingConfirmation = false
    @State private var showingAboutSheet = false
    @State private var showingExportSheet = false
    @State private var showingDonationSheet = false
    @State private var showingImportSheet = false
    
    // Get version and build from Info.plist
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader
                    
                    // Settings Section
                    settingsSection
                    
                    // App Info Section
                    appInfoSection
                    
                    // Community Section
                    communitySection
                    
                    // Data Management Section
                    dataManagementSection
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color.secondarySystemBackground)
                        .clipShape(Circle())
                }
            )
            .background(Color.systemBackground)
            .alert(isPresented: $showingConfirmation) {
                Alert(
                    title: Text("Clear All Data"),
                    message: Text("Are you sure you want to delete ALL your data? This includes expenses, subscriptions, custom categories, and deleted category preferences. This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete All")) {
                        withAnimation {
                            viewModel.clearAllData()
                        }
                        hapticFeedback(style: .heavy)
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                // Initialize the temporary user name with the current value
                tempUserName = viewModel.userName
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile Image
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.appPrimary.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text(String(viewModel.userName.prefix(1)))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 8)
            
            // User Name
            if isEditingName {
                TextField("Your Name", text: $tempUserName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(10)
                    .padding(.horizontal, 40)
                    .onSubmit {
                        saveName()
                    }
                
                // Save button
                Button(action: saveName) {
                    Text("Save")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.appPrimary, Color.appSecondary]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 8)
            } else {
                Text(viewModel.userName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .onTapGesture {
                        isEditingName = true
                    }
                
                // Edit Button
                Button(action: {
                    isEditingName = true
                }) {
                    Text("Edit Profile")
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .stroke(Color.appPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding()
        .cornerRadius(20)
    }
    
    // Save the user name
    private func saveName() {
        if !tempUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.userName = tempUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // If empty, revert to the previous name
            tempUserName = viewModel.userName
        }
        isEditingName = false
        hapticFeedback(style: .medium)
    }
    
    // MARK: - Settings Section
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            // Currency Setting
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Default Currency")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(viewModel.selectedCurrency.symbol) \(viewModel.selectedCurrency.rawValue)")
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingCurrencyPicker.toggle()
            }
            
            // Appearance Setting
            HStack {
                Image(systemName: "moon.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Appearance")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(viewModel.appearanceMode.rawValue)
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingAppearancePicker.toggle()
            }
            
            // Donation Entry
            HStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.pink)
                    .frame(width: 30)
                
                Text("Support the App")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingDonationSheet = true
            }
            
            if showingAppearancePicker {
                VStack(spacing: 0) {
                    ForEach(ExpenseViewModel.AppearanceMode.allCases, id: \.self) { mode in
                        HStack {
                            Text(mode.rawValue)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if viewModel.appearanceMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.appPrimary)
                            }
                        }
                        .padding()
                        .background(
                            viewModel.appearanceMode == mode ?
                            Color.appPrimary.opacity(0.1) :
                            Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hapticFeedback(style: .medium)
                            withAnimation(.spring()) {
                                // Apply the appearance mode change
                                viewModel.appearanceMode = mode
                                
                                // Dismiss the picker after a short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showingAppearancePicker = false
                                }
                            }
                        }
                        
                        if mode != ExpenseViewModel.AppearanceMode.allCases.last {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .background(Color.secondarySystemBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.mauve.opacity(0.3), lineWidth: 1)
                )
                .transition(.opacity)
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
        .sheet(isPresented: $showingDonationSheet) {
            NavigationView {
                DonationView()
            }
        }
    }
    
    // MARK: - App Info Section
    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Info")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            // Version Info
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Version")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(versionString)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            
            // About
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("About CashLens")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingAboutSheet = true
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Community Section
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Community")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Join our community for tips, feedback, and updates!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            
            // Social Media Buttons
            VStack(spacing: 12) {
                // Instagram
                Button(action: {
                    hapticFeedback(style: .light)
                    openSocialMedia(.instagram)
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Instagram")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Daily tips & app updates")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.pink, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
                
                // X (Twitter)
                Button(action: {
                    hapticFeedback(style: .light)
                    openSocialMedia(.twitter)
                }) {
                    HStack {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("X (Twitter)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Quick updates & announcements")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Reddit
                Button(action: {
                    hapticFeedback(style: .light)
                    openSocialMedia(.reddit)
                }) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reddit")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Community discussions & support")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Social Media Handling
    enum SocialPlatform {
        case instagram, twitter, reddit
    }
    
    private func openSocialMedia(_ platform: SocialPlatform) {
        let urlString: String
        
        switch platform {
        case .instagram:
            urlString = "https://instagram.com/cashlensapp"
        case .twitter:
            urlString = "https://x.com/cashlensapp"
        case .reddit:
            urlString = "https://www.reddit.com/r/cashlens/s/Z36oUPfZ3j"
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Data Management Section
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom, 4)
            
            // Export Data
            HStack {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Export Data")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingExportSheet = true
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportDataView()
                    .environmentObject(viewModel)
            }
            
            // Import Data
            HStack {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appPrimary)
                    .frame(width: 30)
                
                Text("Import Data")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .light)
                showingImportSheet = true
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportDataView()
                    .environmentObject(viewModel)
            }
            
            // Clear Data
            HStack {
                Image(systemName: "trash.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.red)
                    .frame(width: 30)
                
                Text("Clear All Data")
                    .foregroundColor(.red)
                
                Spacer()
            }
            .padding()
            .background(Color.secondarySystemBackground)
            .cornerRadius(10)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticFeedback(style: .medium)
                showingConfirmation = true
            }
        }
        .padding()
        .background(Color.secondarySystemBackground.opacity(0.5))
        .cornerRadius(20)
    }
    
    // MARK: - Haptic Feedback
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(ExpenseViewModel())
    }
} 
