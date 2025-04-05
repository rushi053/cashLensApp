import SwiftUI

struct CustomCategoryForm: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var categoryViewModel: CategoryViewModel
    
    @State private var categoryName: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColor: String = "mauve"
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    @State private var errorMessage: String = ""
    @State private var showingError = false
    
    var editingCategory: CustomCategory?
    var onSave: ((CustomCategory) -> Void)?
    
    init(editingCategory: CustomCategory? = nil, onSave: ((CustomCategory) -> Void)? = nil) {
        self.editingCategory = editingCategory
        self.onSave = onSave
        
        // Set initial values if editing
        if let category = editingCategory {
            _categoryName = State(initialValue: category.name)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColor = State(initialValue: category.colorName)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category Details")) {
                    TextField("Category Name", text: $categoryName)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                    
                    Button(action: {
                        HapticManager.shared.mediumTap()
                        showingIconPicker = true
                    }) {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundColor(Color.forCategory(selectedColor))
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(Color.forCategory(selectedColor).opacity(0.15))
                                )
                            Text("Select")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                    
                    Button(action: {
                        HapticManager.shared.mediumTap()
                        showingColorPicker = true
                    }) {
                        HStack {
                            Text("Color")
                            Spacer()
                            Circle()
                                .fill(Color.forCategory(selectedColor))
                                .frame(width: 24, height: 24)
                            Text("Select")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                
                Section {
                    Button(action: saveCategory) {
                        Text("Save Category")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.appPrimary)
                }
            }
            .navigationTitle(editingCategory == nil ? "New Category" : "Edit Category")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveCategory()
                }
                .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
            .alert(isPresented: $showingError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
                    .environmentObject(categoryViewModel)
            }
            .sheet(isPresented: $showingColorPicker) {
                ColorPickerView(selectedColor: $selectedColor)
                    .environmentObject(categoryViewModel)
            }
        }
    }
    
    private func saveCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate inputs
        guard !trimmedName.isEmpty else {
            errorMessage = "Category name cannot be empty"
            showingError = true
            return
        }
        
        // Check if name already exists (except when editing the same category)
        if categoryViewModel.categoryNameExists(trimmedName, excluding: editingCategory?.id) {
            errorMessage = "A category with this name already exists"
            showingError = true
            return
        }
        
        // Create or update the category
        if var category = editingCategory {
            // Update existing category
            category.name = trimmedName
            category.icon = selectedIcon
            category.colorName = selectedColor
            
            categoryViewModel.updateCustomCategory(category)
            onSave?(category)
        } else {
            // Create new category
            let newCategory = CustomCategory(
                name: trimmedName,
                icon: selectedIcon,
                colorName: selectedColor
            )
            
            categoryViewModel.addCustomCategory(newCategory)
            onSave?(newCategory)
        }
        
        // Dismiss the form
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Icon Picker View
struct IconPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedIcon: String
    
    let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 80), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CustomCategory.availableIcons, id: \.self) { icon in
                        Button(action: {
                            HapticManager.shared.mediumTap()
                            selectedIcon = icon
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: icon)
                                .font(.system(size: 28))
                                .frame(width: 60, height: 60)
                                .background(
                                    Circle()
                                        .fill(selectedIcon == icon ? 
                                              Color.appPrimary.opacity(0.2) : 
                                              Color.secondarySystemBackground)
                                )
                                .foregroundColor(selectedIcon == icon ? 
                                                Color.appPrimary : 
                                                Color.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("Select Icon")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Color Picker View
struct ColorPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedColor: String
    
    let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 80), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CustomCategory.availableColors, id: \.self) { colorName in
                        Button(action: {
                            HapticManager.shared.mediumTap()
                            selectedColor = colorName
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Circle()
                                .fill(Color.forCategory(colorName))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .opacity(selectedColor == colorName ? 1 : 0)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("Select Color")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

struct CustomCategoryForm_Previews: PreviewProvider {
    static var previews: some View {
        CustomCategoryForm()
            .environmentObject(CategoryViewModel())
    }
} 