import SwiftUI

/// The unified "make it yours" studio — appearance mode, accent theme,
/// and matching app icon in one sheet. Replaces the old `ThemePickerView`
/// (theme grid only) so personalization is a single designed moment
/// instead of three scattered settings rows.
///
/// Layout, top to bottom:
///   1. `SheetHeader` — "Appearance", the app's canonical sheet chrome.
///   2. Live preview — a miniature Today screen (greeting, spent hero,
///      status pill, progress bar, week bars, FAB) rendered entirely in
///      the *previewed* theme so the user gut-checks the real surfaces,
///      not an abstract swatch.
///   3. Mode selector — System / Light / Dark as three mini-mock cards.
///      Free for everyone; applies instantly (it's a native trait).
///   4. Theme grids — "Classics" and "Pastels" groups. Swatches are
///      duotone circles (the theme's hero gradient) so each theme reads
///      as the designed *pair* it is. Tap = preview only.
///   5. "Complete the look" — when the previewed theme has a matching
///      app icon that isn't applied, a one-tap pairing card appears.
///
/// Pro gating matches the old picker: free users can preview everything,
/// but committing any non-default theme (or a non-primary icon) routes
/// to the paywall. Commit happens only via the sticky bottom Apply bar.
struct AppearanceStudioView: View {

    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var proManager: ProManager
    @EnvironmentObject private var iconStore: AppIconStore
    @EnvironmentObject private var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var previewTheme: AppTheme
    @State private var showingPaywall = false
    @State private var iconError: String?
    @State private var isApplyingIcon = false

    init() {
        _previewTheme = State(initialValue: ThemeStore.activeTheme)
    }

    private var isPreviewingProTheme: Bool {
        previewTheme.id != AppTheme.default.id && !proManager.isPro
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                eyebrow: "Make it yours",
                title: "Appearance",
                onClose: { dismiss() }
            )

            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    livePreviewCard
                    modeSelector
                    themeGroup(title: "Classics", themes: AppTheme.classics)
                    themeGroup(title: "Pastels", themes: AppTheme.pastels)
                    matchingIconCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Color.systemBackground)
        }
        .background(Color.systemBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
        .sheet(isPresented: $showingPaywall) { PaywallView(context: .themes) }
        .alert("Couldn't change icon", isPresented: Binding(
            get: { iconError != nil },
            set: { if !$0 { iconError = nil } }
        )) {
            Button("OK", role: .cancel) { iconError = nil }
        } message: {
            Text(iconError ?? "")
        }
    }

    // MARK: - Live preview

    /// Miniature Today screen mock. Every accent surface reads from
    /// `previewTheme` directly (not `Color.appPrimary`) so tapping a
    /// swatch repaints the whole mock without touching the live app.
    private var livePreviewCard: some View {
        let primary = previewTheme.primaryColor
        let duotone = previewTheme.heroGradient

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Live preview")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(previewTheme.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundColor(primary)
                    Text(previewTheme.tagline)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .animation(Theme.Motion.snappy, value: previewTheme.id)
            }

            // Mini Today mock
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SPENT THIS WEEK")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                        Text("$324.50")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("On Track")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(primary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(primary.opacity(0.12)))
                }

                // Budget progress bar — duotone fill, like the real hero.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tertiarySystemBackground)
                        Capsule()
                            .fill(duotone)
                            .frame(width: proxy.size.width * 0.62)
                    }
                }
                .frame(height: 8)

                // Week strip — today's bar in full accent, the rest tinted.
                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(Array(mockWeekBars.enumerated()), id: \.offset) { index, height in
                        VStack(spacing: 3) {
                            Capsule()
                                .fill(index == 4 ? AnyShapeStyle(duotone) : AnyShapeStyle(primary.opacity(0.22)))
                                .frame(height: height)
                                .frame(maxWidth: .infinity)
                            Text(["M", "T", "W", "T", "F", "S", "S"][index])
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(index == 4 ? primary : .secondary)
                        }
                    }
                }
                .frame(height: 52, alignment: .bottom)
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.tertiarySystemBackground.opacity(0.5))
            )
            .overlay(alignment: .bottomTrailing) {
                // Mock FAB floating over the card corner.
                ZStack {
                    Circle()
                        .fill(duotone)
                        .frame(width: 38, height: 38)
                        .shadow(color: primary.opacity(0.35), radius: 6, x: 0, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .offset(x: -10, y: 12)
            }
            .animation(Theme.Motion.tap, value: previewTheme.id)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    /// Static heights for the mock week strip (index 4 = "today").
    private var mockWeekBars: [CGFloat] {
        [16, 30, 12, 24, 40, 20, 8]
    }

    // MARK: - Appearance mode

    /// System / Light / Dark as three visual cards, each a tiny mock of
    /// the app in that mode. Applies instantly — appearance is native,
    /// free, and reversible, so there's nothing to "commit".
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Mode")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: Theme.Spacing.md) {
                ForEach(ExpenseViewModel.AppearanceMode.allCases, id: \.self) { mode in
                    modeCard(mode)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    private func modeCard(_ mode: ExpenseViewModel.AppearanceMode) -> some View {
        let isSelected = viewModel.appearanceMode == mode
        let primary = previewTheme.primaryColor

        return Button {
            guard viewModel.appearanceMode != mode else { return }
            HapticManager.shared.selectionChanged()
            withAnimation(Theme.Motion.snappy) {
                viewModel.appearanceMode = mode
            }
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                modeMock(mode)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isSelected ? primary : Color.primary.opacity(0.08),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )

                HStack(spacing: 3) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    Text(mode.rawValue)
                        .font(.caption.weight(isSelected ? .bold : .medium))
                }
                .foregroundColor(isSelected ? primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.snappy, value: isSelected)
        .accessibilityLabel("\(mode.rawValue) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Tiny mock of the app in the given mode: a background, a text
    /// line, and an accent dot. System splits light/dark diagonally.
    @ViewBuilder
    private func modeMock(_ mode: ExpenseViewModel.AppearanceMode) -> some View {
        let primary = previewTheme.primaryColor
        switch mode {
        case .light:
            modeMockPanel(background: Color(white: 0.98), line: Color(white: 0.75), accent: primary)
        case .dark:
            modeMockPanel(background: Color(white: 0.11), line: Color(white: 0.35), accent: primary)
        case .system:
            ZStack {
                HStack(spacing: 0) {
                    Color(white: 0.98)
                    Color(white: 0.11)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color(white: 0.55)).frame(width: 34, height: 5)
                    Capsule().fill(Color(white: 0.55).opacity(0.6)).frame(width: 22, height: 5)
                    Circle().fill(primary).frame(width: 10, height: 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            }
        }
    }

    private func modeMockPanel(background: Color, line: Color, accent: Color) -> some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(line).frame(width: 34, height: 5)
                Capsule().fill(line.opacity(0.6)).frame(width: 22, height: 5)
                Circle().fill(accent).frame(width: 10, height: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        }
    }

    // MARK: - Theme grids

    private func themeGroup(title: String, themes: [AppTheme]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg)
        ]

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if !proManager.isPro && title == "Classics" {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Pro")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.appPrimary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.appPrimary.opacity(0.14)))
                }
            }

            LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                ForEach(themes) { theme in
                    swatchButton(theme)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    private func swatchButton(_ theme: AppTheme) -> some View {
        let isPreview = theme.id == previewTheme.id
        let isSaved = theme.id == themeStore.currentTheme.id
        let isFree = theme.id == AppTheme.default.id

        return Button {
            handleTap(theme)
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .stroke(isPreview ? theme.primaryColor : Color.clear, lineWidth: 3)
                        .frame(width: 64, height: 64)

                    // Duotone well — the theme's actual hero gradient, so
                    // the grid itself communicates each theme is a pair.
                    Circle()
                        .fill(theme.heroGradient)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: theme.primaryColor.opacity(0.25), radius: 6, x: 0, y: 3)

                    if isSaved {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                    }

                    if !proManager.isPro && !isFree {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .offset(x: 22, y: -22)
                    }
                }
                .scaleEffect(isPreview ? 1.05 : 1.0)
                .animation(Theme.Motion.tap, value: isPreview)

                Text(theme.displayName)
                    .font(.caption.weight(isSaved ? .bold : .medium))
                    .foregroundColor(isSaved ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Matching icon pairing

    /// Resolved icon option matching the previewed theme, if the catalog
    /// has one and it isn't already applied.
    private var matchingIcon: AppIconOption? {
        guard UIApplication.shared.supportsAlternateIcons,
              let iconId = previewTheme.matchingIconId else { return nil }
        let icon = AppIconOption.resolve(id: iconId)
        guard icon.id == iconId, icon.id != iconStore.currentIcon.id else { return nil }
        return icon
    }

    /// "Complete the look" — one-tap matching app icon for the previewed
    /// theme. The clever bit users screenshot: theme and Home Screen icon
    /// changing as a designed pair.
    @ViewBuilder
    private var matchingIconCard: some View {
        if let icon = matchingIcon {
            HStack(spacing: Theme.Spacing.md) {
                Image(icon.previewAssetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Complete the look")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Set the matching \(icon.displayName) app icon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Button {
                    applyMatchingIcon(icon)
                } label: {
                    Group {
                        if isApplyingIcon {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Use")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    .background(Capsule().fill(previewTheme.heroGradient))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isApplyingIcon)
            }
            .padding(Theme.Spacing.lg)
            .cardSurface()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func applyMatchingIcon(_ icon: AppIconOption) {
        // Non-primary icons are Pro; the primary (Mauve) icon is free.
        if !icon.isPrimary && !proManager.isPro {
            HapticManager.shared.warning()
            showingPaywall = true
            return
        }
        isApplyingIcon = true
        Task {
            defer { isApplyingIcon = false }
            do {
                try await iconStore.apply(icon)
                HapticManager.shared.success()
            } catch {
                iconError = error.localizedDescription
                HapticManager.shared.warning()
            }
        }
    }

    // MARK: - Bottom action bar

    /// Sticky commit bar. Three states — Pro lock, Apply, or a disabled
    /// "is active" no-op — mirroring the old picker so the bar never
    /// appears/disappears mid-interaction.
    private var bottomActionBar: some View {
        let isLocked = isPreviewingProTheme
        let hasChange = previewTheme.id != themeStore.currentTheme.id

        let label: String = {
            if isLocked { return "Unlock \(previewTheme.displayName) with Pro" }
            if hasChange { return "Apply \(previewTheme.displayName)" }
            return "\(previewTheme.displayName) is active"
        }()

        let icon: String? = isLocked ? "lock.fill" : (hasChange ? nil : "checkmark")
        let isInteractive = isLocked || hasChange

        return VStack(spacing: 0) {
            Divider().opacity(0.4)

            Button {
                applyPreview()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(barFill(isLocked: isLocked, hasChange: hasChange))
                )
                .shadow(
                    color: isInteractive ? previewTheme.primaryColor.opacity(0.35) : .clear,
                    radius: 10,
                    x: 0,
                    y: 4
                )
                .animation(Theme.Motion.snappy, value: previewTheme.id)
                .animation(Theme.Motion.snappy, value: hasChange)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!isInteractive)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
        }
        .background(.ultraThinMaterial)
    }

    private func barFill(isLocked: Bool, hasChange: Bool) -> AnyShapeStyle {
        if isLocked { return AnyShapeStyle(LinearGradient.appDuotone) }
        if hasChange { return AnyShapeStyle(previewTheme.heroGradient) }
        return AnyShapeStyle(Color.gray.opacity(0.35))
    }

    // MARK: - Tap handling

    /// Swatch tap = preview only; the whole studio repaints in the
    /// candidate theme. Commit happens via the bottom Apply button.
    private func handleTap(_ theme: AppTheme) {
        guard theme.id != previewTheme.id else { return }
        HapticManager.shared.selectionChanged()
        withAnimation(Theme.Motion.tap) {
            previewTheme = theme
        }
    }

    /// Commit the previewed theme. Pro-gated themes route to the paywall
    /// for free users instead of applying.
    private func applyPreview() {
        let isFree = previewTheme.id == AppTheme.default.id
        if isFree || proManager.isPro {
            HapticManager.shared.success()
            themeStore.applyTheme(previewTheme)
        } else {
            HapticManager.shared.warning()
            showingPaywall = true
        }
    }
}

#Preview {
    AppearanceStudioView()
        .environmentObject(ThemeStore.shared)
        .environmentObject(ProManager.shared)
        .environmentObject(AppIconStore.shared)
        .environmentObject(ExpenseViewModel())
}
