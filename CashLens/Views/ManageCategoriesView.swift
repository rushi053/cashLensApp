import SwiftUI

struct ManageCategoriesView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    @State private var showingDeleteAlert = false
    @State private var categoryToDelete: CustomCategory?
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Default Categories")) {
                    ForEach(Expense.Category.allCases.filter { $0 != .custom }, id: \.self) { category in
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.forCategory(category.color).opacity(0.3))
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: category.icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.forCategory(category.color))
                            }
                            
                            Text(category.rawValue)
                                .padding(.leading, 8)
                            
                            Spacer()
                            
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Custom Categories")) {
                    if categoryViewModel.customCategories.isEmpty {
                        Text("No custom categories yet")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.vertical, 8)
                    } else {
                        ForEach(categoryViewModel.customCategories) { category in
                            Button(action: {
                                editingCategory = category
                                showingAddCategory = true
                            }) {
                                HStack {
                                    ZStack {
                                        Circle()
                                            .fill(Color.forCategory(category.colorName).opacity(0.3))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: category.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(Color.forCategory(category.colorName))
                                    }
                                    
                                    Text(category.name)
                                        .padding(.leading, 8)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    categoryToDelete = category
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let categoriesToDelete = indexSet.map { categoryViewModel.customCategories[$0] }
                            for category in categoriesToDelete {
                                categoryViewModel.deleteCustomCategory(id: category.id)
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        editingCategory = nil
                        showingAddCategory = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.appPrimary)
                            
                            Text("Add New Category")
                                .foregroundColor(.appPrimary)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Manage Categories")
            .navigationBarItems(
                leading: Button("Back") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                // Load categories when view appears
                categoryViewModel.loadCustomCategories()
                
                // Create default categories if needed
                categoryViewModel.createDefaultCategoriesIfNeeded()
            }
            .sheet(isPresented: $showingAddCategory, onDismiss: {
                // Reload categories when returning from the category form
                categoryViewModel.loadCustomCategories()
            }) {
                CustomCategoryForm(editingCategory: editingCategory)
                    .environmentObject(categoryViewModel)
            }
            .alert(isPresented: $showingDeleteAlert) {
                Alert(
                    title: Text("Delete Category"),
                    message: Text("Are you sure you want to delete this category? Any expenses using this category will be moved to 'Other'."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let category = categoryToDelete {
                            categoryViewModel.deleteCustomCategory(id: category.id)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

struct ManageCategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        ManageCategoriesView()
            .environmentObject(CategoryViewModel())
    }
} 