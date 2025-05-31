import SwiftUI

struct SummaryCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    @State private var selectedCategories: [Expense.Category] = []
    @State private var availableCategories: [Expense.Category] = []
    
    private let maxSelections = 3 // Total will be 4 with "Total Expenses" always included
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Section
                    headerSection
                    
                    // Main Content
                    ScrollView {
                        VStack(spacing: 32) {
                            // Preview Section
                            previewSection
                            
                            // Categories Selection Section
                            categoriesSection
                            
                            // Reset Button
                            resetSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(
                // Save button overlay
                VStack {
                    Spacer()
                    saveButton
                }
            )
        }
        .onAppear {
            setupInitialState()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 20) {
            // Top navigation
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            // Title section
            VStack(spacing: 12) {
                Text("Customize Summary")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Choose 3 categories to display on your home screen")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        .background(
            Rectangle()
                .fill(Color(.systemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }
    
    // MARK: - Preview Section
    private var previewSection: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("How your summary will look")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Preview cards container
            VStack(spacing: 16) {
                // First row: Total Expenses + one more
                HStack(spacing: 12) {
                    PreviewSummaryCard(
                        title: "Total Expenses",
                        icon: "creditcard.fill",
                        color: .appPrimary
                    )
                    
                    if selectedCategories.count >= 1 {
                        PreviewSummaryCard(
                            title: selectedCategories[0].displayName,
                            icon: selectedCategories[0].icon,
                            color: Color.forCategory(selectedCategories[0].color)
                        )
                    } else {
                        PreviewSummaryCard(
                            title: "Select Category",
                            icon: "plus.circle.dotted",
                            color: .gray,
                            isPlaceholder: true
                        )
                    }
                }
                
                // Second row: Two more categories
                HStack(spacing: 12) {
                    if selectedCategories.count >= 2 {
                        PreviewSummaryCard(
                            title: selectedCategories[1].displayName,
                            icon: selectedCategories[1].icon,
                            color: Color.forCategory(selectedCategories[1].color)
                        )
                    } else {
                        PreviewSummaryCard(
                            title: "Select Category",
                            icon: "plus.circle.dotted",
                            color: .gray,
                            isPlaceholder: true
                        )
                    }
                    
                    if selectedCategories.count >= 3 {
                        PreviewSummaryCard(
                            title: selectedCategories[2].displayName,
                            icon: selectedCategories[2].icon,
                            color: Color.forCategory(selectedCategories[2].color)
                        )
                    } else {
                        PreviewSummaryCard(
                            title: "Select Category",
                            icon: "plus.circle.dotted",
                            color: .gray,
                            isPlaceholder: true
                        )
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
        }
    }
    
    // MARK: - Categories Section
    private var categoriesSection: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Categories")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Tap to select your preferred categories")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection counter
                HStack(spacing: 6) {
                    Text("\(selectedCategories.count)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(selectedCategories.count == maxSelections ? .white : .appPrimary)
                    
                    Text("/")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("\(maxSelections)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedCategories.count == maxSelections ? 
                              LinearGradient(colors: [.appPrimary, .appSecondary], startPoint: .leading, endPoint: .trailing) :
                              LinearGradient(colors: [Color(.systemGray6), Color(.systemGray5)], startPoint: .leading, endPoint: .trailing)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(selectedCategories.count == maxSelections ? Color.appPrimary : Color.clear, lineWidth: 1)
                )
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(availableCategories, id: \.self) { category in
                    CategorySelectionCard(
                        category: category,
                        isSelected: selectedCategories.contains(category),
                        isDisabled: !selectedCategories.contains(category) && selectedCategories.count >= maxSelections,
                        onTap: {
                            toggleCategory(category)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Reset Section
    private var resetSection: some View {
        Button(action: resetToDefaults) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Reset to Defaults")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.appPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appPrimary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.appPrimary.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private var saveButton: some View {
        VStack(spacing: 0) {
            // Gradient overlay
            LinearGradient(
                colors: [Color.clear, Color(.systemGroupedBackground).opacity(0.8), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            
            Button(action: saveAndDismiss) {
                Text("Save Changes")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.appPrimary, Color.appSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.appPrimary.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private func setupInitialState() {
        // Get available categories (excluding custom and other for summary)
        availableCategories = Expense.Category.allCases.filter { $0 != .custom && $0 != .other }
        
        // Load current preferences
        selectedCategories = Array(viewModel.preferredSummaryCategories.prefix(3))
        
        // If no preferences set, use defaults
        if selectedCategories.isEmpty {
            selectedCategories = Array(viewModel.getDefaultSummaryCategories().prefix(3))
        }
    }
    
    private func toggleCategory(_ category: Expense.Category) {
        HapticManager.shared.impact(style: .light)
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            if selectedCategories.contains(category) {
                selectedCategories.removeAll { $0 == category }
            } else if selectedCategories.count < maxSelections {
                selectedCategories.append(category)
            }
        }
    }
    
    private func resetToDefaults() {
        HapticManager.shared.impact(style: .medium)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            selectedCategories = Array(viewModel.getDefaultSummaryCategories().prefix(3))
        }
    }
    
    private func saveAndDismiss() {
        HapticManager.shared.impact(style: .medium)
        viewModel.updateSummaryCategories(selectedCategories)
        dismiss()
    }
}

// MARK: - Supporting Views

struct CategorySelectionCard: View {
    let category: Expense.Category
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                                LinearGradient(colors: [Color.forCategory(category.color), Color.forCategory(category.color).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [Color(.systemGray6), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color.forCategory(category.color) : Color.clear,
                                    lineWidth: 3
                                )
                        )
                        .shadow(color: isSelected ? Color.forCategory(category.color).opacity(0.3) : Color.black.opacity(0.1), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
                    
                    Image(systemName: category.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                
                Text(category.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? Color.forCategory(category.color) : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? Color.forCategory(category.color).opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .opacity(isDisabled ? 0.5 : 1.0)
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .disabled(isDisabled)
        .buttonStyle(PlainButtonStyle())
    }
}

struct PreviewSummaryCard: View {
    let title: String
    let icon: String
    let color: Color
    var isPlaceholder: Bool = false
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isPlaceholder ? 
                            LinearGradient(colors: [Color(.systemGray5), Color(.systemGray4)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [color.opacity(0.2), color.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isPlaceholder ? Color.clear : color.opacity(0.3), lineWidth: 1)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isPlaceholder ? .secondary : color)
            }
            
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPlaceholder ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32) // Fixed height to prevent layout shifts
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
        .opacity(isPlaceholder ? 0.7 : 1.0)
    }
}

struct SummaryCustomizationView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryCustomizationView()
            .environmentObject(ExpenseViewModel())
    }
} 