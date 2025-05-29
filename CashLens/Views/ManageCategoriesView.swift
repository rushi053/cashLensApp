import SwiftUI

struct ManageCategoriesView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    @EnvironmentObject var expenseViewModel: ExpenseViewModel
    
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    @State private var showingDeleteAlert = false
    @State private var categoryToDelete: CustomCategory?
    @State private var showingDeleteDefaultAlert = false
    @State private var defaultCategoryToDelete: Expense.Category?
    @State private var deletedDefaultCategories: Set<String> = []
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Default Categories")) {
                    ForEach(Expense.Category.allCases.filter { $0 != .custom && !deletedDefaultCategories.contains($0.rawValue) }, id: \.self) { category in
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
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                defaultCategoryToDelete = category
                                showingDeleteDefaultAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                
                // Show deleted categories section if any exist
                if !deletedDefaultCategories.isEmpty {
                    Section(header: Text("Deleted Default Categories")) {
                        ForEach(Array(deletedDefaultCategories), id: \.self) { categoryName in
                            if let category = Expense.Category.allCases.first(where: { $0.rawValue == categoryName && $0 != .custom }) {
                                HStack {
                                    ZStack {
                                        Circle()
                                            .fill(Color.forCategory(category.color).opacity(0.2))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: category.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(Color.forCategory(category.color).opacity(0.5))
                                    }
                                    
                                    Text(category.rawValue)
                                        .padding(.leading, 8)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Restore") {
                                        restoreDefaultCategory(category)
                                    }
                                    .foregroundColor(.appPrimary)
                                    .font(.caption)
                                }
                                .padding(.vertical, 4)
                            }
                        }
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
                
                // Load deleted default categories
                loadDeletedDefaultCategories()
            }
            .sheet(isPresented: $showingAddCategory, onDismiss: {
                // Reload categories when returning from the category form
                categoryViewModel.loadCustomCategories()
            }) {
                CustomCategoryForm(editingCategory: editingCategory)
                    .environmentObject(categoryViewModel)
            }
            .alert("Delete Custom Category", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let category = categoryToDelete {
                        categoryViewModel.deleteCustomCategory(id: category.id)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this custom category? Any expenses using this category will be moved to 'Other'.")
            }
            .alert("Delete Default Category", isPresented: $showingDeleteDefaultAlert) {
                Button("Delete", role: .destructive) {
                    if let category = defaultCategoryToDelete {
                        deleteDefaultCategory(category)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this default category? This will hide it from all category selections. Any existing expenses with this category will be moved to 'Other'. You can restore it later if needed.")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadDeletedDefaultCategories() {
        if let deleted = UserDefaults.standard.array(forKey: "deletedDefaultCategories") as? [String] {
            deletedDefaultCategories = Set(deleted)
        }
    }
    
    private func saveDeletedDefaultCategories() {
        UserDefaults.standard.set(Array(deletedDefaultCategories), forKey: "deletedDefaultCategories")
    }
    
    private func deleteDefaultCategory(_ category: Expense.Category) {
        // Move existing expenses from this category to "Other"
        expenseViewModel.moveExpensesFromDeletedCategory(category.rawValue)
        
        // Add to deleted categories
        deletedDefaultCategories.insert(category.rawValue)
        saveDeletedDefaultCategories()
    }
    
    private func restoreDefaultCategory(_ category: Expense.Category) {
        deletedDefaultCategories.remove(category.rawValue)
        saveDeletedDefaultCategories()
    }
}

struct ManageCategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        ManageCategoriesView()
            .environmentObject(CategoryViewModel())
            .environmentObject(ExpenseViewModel())
    }
} 