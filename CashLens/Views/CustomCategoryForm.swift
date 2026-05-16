import SwiftUI

/// Add / Edit Custom Category screen.
///
/// Structural twin of `BudgetSetupView` and `AddSubscriptionView`:
/// custom header (no nav bar), bold rounded field labels, `fieldCard()`
/// inputs, a live preview tile at the top, inline colour + icon strips
/// for fast selection, and the same fixed bottom save button with a
/// fade-to-background gradient.
struct CustomCategoryForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var categoryViewModel: CategoryViewModel

    // MARK: - State

    @State private var categoryName: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColor: String = "mauve"
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    @State private var errorMessage: String = ""
    @State private var showingError = false
    @State private var isSaving = false

    @FocusState private var nameFocused: Bool

    var editingCategory: CustomCategory?
    var onSave: ((CustomCategory) -> Void)?

    // MARK: - Init

    init(editingCategory: CustomCategory? = nil, onSave: ((CustomCategory) -> Void)? = nil) {
        self.editingCategory = editingCategory
        self.onSave = onSave

        if let category = editingCategory {
            _categoryName = State(initialValue: category.name)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColor = State(initialValue: category.colorName)
        }
    }

    // MARK: - Tokens

    private static let fieldLabelFont = Font.system(size: 18, weight: .bold, design: .rounded)
    private var isEditing: Bool { editingCategory != nil }

    private var trimmedName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isValid: Bool { !trimmedName.isEmpty }

    /// First 8 colours from each group make a balanced quick-pick row.
    /// Anything beyond that lives behind the "All colours" full-grid sheet.
    private var quickColors: [String] {
        let warm = CustomCategory.colorGroups.first { $0.name == "Warm" }?.colors.prefix(4) ?? []
        let cool = CustomCategory.colorGroups.first { $0.name == "Cool" }?.colors.prefix(4) ?? []
        let accent = CustomCategory.colorGroups.first { $0.name == "Accent" }?.colors.prefix(2) ?? []
        return Array(warm) + Array(cool) + Array(accent)
    }

    /// Hand-picked icons that cover the most common categories — so a
    /// brand-new user almost never has to open the full picker.
    private static let quickIcons: [String] = [
        "fork.knife", "cart.fill", "car.fill", "house.fill",
        "creditcard.fill", "tv.fill", "heart.fill", "airplane.departure",
        "book.fill", "sparkles", "tag.fill", "ellipsis"
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xxxl - 4) {
                        previewTile
                        nameField
                        colorField
                        iconField
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.sm + 2)
                    .padding(.bottom, 40)
                }

                saveButton
            }
        }
        .navigationBarHidden(true)
        .alert(isPresented: $showingError) {
            Alert(
                title: Text("Heads up"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(
                selectedIcon: $selectedIcon,
                tintColorName: selectedColor
            )
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerView(selectedColor: $selectedColor)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                Text(isEditing ? "Edit Category" : "New Category")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(isEditing ? "Update its look and feel" : "Pick a colour and an icon")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Preview tile

    private var previewTile: some View {
        let tint = Color.forCategory(selectedColor)
        return HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 64, height: 64)
                Image(systemName: selectedIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .id(selectedIcon)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(trimmedName.isEmpty ? "Your category" : trimmedName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(isEditing ? "Tap below to update." : "This is how it'll appear.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.lg)
        .cardSurface()
        .softShadow()
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Name")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
            }

            TextField("e.g. Coffee Runs", text: $categoryName)
                .font(.system(size: 17, weight: .medium))
                .focused($nameFocused)
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .fieldCard(isFocused: nameFocused)
                .contentShape(Rectangle())
                .onTapGesture { nameFocused = true }
        }
    }

    // MARK: - Color

    private var colorField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Colour")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    HapticManager.shared.lightTap()
                    showingColorPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.appPrimary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(quickColors, id: \.self) { name in
                        colorSwatch(name)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private func colorSwatch(_ name: String) -> some View {
        let isSelected = selectedColor == name
        let tint = Color.forCategory(name)
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) { selectedColor = name }
        } label: {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 44, height: 44)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? tint.opacity(0.9) : Color.clear, lineWidth: 3)
                    .padding(-4)
            )
            .shadow(color: isSelected ? tint.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icon

    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Icon")
                    .font(Self.fieldLabelFont)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    HapticManager.shared.lightTap()
                    showingIconPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.appPrimary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Self.quickIcons, id: \.self) { icon in
                        iconChip(icon)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private func iconChip(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon
        let tint = Color.forCategory(selectedColor)
        return Button {
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) { selectedIcon = icon }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.22) : Color.secondarySystemBackground)
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? tint : .primary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.7) : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? tint.opacity(0.25) : .clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save

    private var saveButton: some View {
        // Solid bottom bar — no fade gradient, no gradient button. A
        // hairline separator is enough to distinguish the CTA strip
        // from the scrolling content above.
        VStack(spacing: 0) {
            Divider().opacity(0.35)

            Button(action: handleSaveTap) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text(isEditing ? "Save Changes" : "Create Category")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isValid ? Color.appPrimary : Color.gray.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(
                    color: isValid ? Color.appPrimary.opacity(0.3) : Color.gray.opacity(0.18),
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }
            .disabled(!isValid || isSaving)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 40)
            .background(Color(.systemGroupedBackground))
        }
    }

    private func handleSaveTap() {
        guard isValid else { return }
        isSaving = true
        HapticManager.shared.mediumTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticManager.shared.success()
        }
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }

    private func save() {
        // Duplicate-name guard. We do this *after* the visual save state
        // has flipped so the user gets immediate feedback that their tap
        // landed, but we never persist a duplicate.
        if categoryViewModel.categoryNameExists(trimmedName, excluding: editingCategory?.id) {
            isSaving = false
            errorMessage = "A category named “\(trimmedName)” already exists."
            showingError = true
            return
        }

        if var category = editingCategory {
            category.name = trimmedName
            category.icon = selectedIcon
            category.colorName = selectedColor
            categoryViewModel.updateCustomCategory(category)
            onSave?(category)
        } else {
            let newCategory = CustomCategory(
                name: trimmedName,
                icon: selectedIcon,
                colorName: selectedColor
            )
            categoryViewModel.addCustomCategory(newCategory)
            onSave?(newCategory)
        }
    }
}

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String
    /// Used to tint the selected chip in the picker so the choice
    /// previews against the colour the user has already chosen.
    var tintColorName: String = "mauve"

    @State private var query: String = ""

    private let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 80), spacing: Theme.Spacing.md)
    ]

    /// Filter applied across every group's icons. Matches against the
    /// raw symbol name so "fork", "cart.fill" etc. all hit.
    private var filteredGroups: [CustomCategory.IconGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return CustomCategory.iconGroups }
        return CustomCategory.iconGroups.compactMap { group in
            let hits = group.icons.filter { $0.lowercased().contains(q) }
            return hits.isEmpty ? nil : CustomCategory.IconGroup(name: group.name, icons: hits)
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                pickerHeader

                searchField
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.lg)

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl, pinnedViews: []) {
                        if filteredGroups.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredGroups, id: \.name) { group in
                                section(group)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var pickerHeader: some View {
        HStack {
            Text("Choose Icon")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.appPrimary)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("Search icons", text: $query)
                .font(.system(size: 15, weight: .medium))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    HapticManager.shared.lightTap()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .cardSurface()
        .softShadow()
    }

    private func section(_ group: CustomCategory.IconGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(group.name.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(group.icons, id: \.self) { icon in
                    iconCell(icon)
                }
            }
        }
    }

    private func iconCell(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon
        let tint = Color.forCategory(tintColorName)
        return Button {
            HapticManager.shared.selectionChanged()
            selectedIcon = icon
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dismiss()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.22) : Color.secondarySystemBackground)
                    .frame(height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(isSelected ? tint : .primary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.8) : Color.clear, lineWidth: 2)
            )
            .shadow(
                color: isSelected ? tint.opacity(0.3) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No icons match “\(query)”")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Color Picker View

struct ColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedColor: String

    private let columns = [
        GridItem(.adaptive(minimum: 56, maximum: 72), spacing: Theme.Spacing.lg)
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                pickerHeader

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        ForEach(CustomCategory.colorGroups, id: \.name) { group in
                            section(group)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var pickerHeader: some View {
        HStack {
            Text("Choose Colour")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.appPrimary)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func section(_ group: CustomCategory.ColorGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(group.name.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                ForEach(group.colors, id: \.self) { name in
                    colorCell(name)
                }
            }
        }
    }

    private func colorCell(_ name: String) -> some View {
        let isSelected = selectedColor == name
        let tint = Color.forCategory(name)
        return Button {
            HapticManager.shared.selectionChanged()
            selectedColor = name
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 52, height: 52)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(isSelected ? tint.opacity(0.9) : Color.clear, lineWidth: 3)
                    .padding(-4)
            )
            .shadow(color: isSelected ? tint.opacity(0.4) : .clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct CustomCategoryForm_Previews: PreviewProvider {
    static var previews: some View {
        CustomCategoryForm()
            .environmentObject(CategoryViewModel())
    }
}
