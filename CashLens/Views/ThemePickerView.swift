import SwiftUI

/// Pro-gated picker that lets the user choose an accent color theme for the
/// entire app. Free users can preview any theme (instant visual feedback) but
/// applying anything other than the default `Mauve` opens the paywall.
///
/// Layout:
/// 1. Live preview card — a miniature mock of the home screen showing pills,
///    a FAB, and a tinted bar so the user sees exactly how their choice
///    cascades through the UI.
/// 2. 2 × 3 swatch grid — circular wells in each theme's primary color, with
///    an animated check on the active (saved) theme and a tinted ring on
///    the previewed-but-not-yet-applied selection.
/// 3. Sticky bottom action bar — "Apply <Theme>" for Pro users / default
///    theme, "Unlock <Theme> with Pro" for free users on Pro themes, or a
///    disabled "<Theme> is active" state when preview matches saved.
///
/// Tap-on-swatch is preview-only: it updates `previewTheme` and animates
/// the live preview card, but does NOT commit. Commit only happens via the
/// bottom Apply button, which calls `ThemeStore.applyTheme(_:)` and forces
/// a soft cross-dissolve refresh so SwiftUI + UIKit dynamic colors re-
/// resolve cleanly.
struct ThemePickerView: View {

    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var proManager: ProManager
    @Environment(\.dismiss) private var dismiss

    @State private var previewTheme: AppTheme
    @State private var showingPaywall = false

    init() {
        _previewTheme = State(initialValue: ThemeStore.activeTheme)
    }

    private var isPreviewingProTheme: Bool {
        previewTheme.id != AppTheme.default.id && !proManager.isPro
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    livePreviewCard
                    swatchGrid
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Color.systemGroupedBackground)
            .navigationTitle("Color Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            // Sticky bottom action bar — sits above the home indicator and
            // never scrolls away. The Apply button is the only way to
            // commit the theme; tapping a swatch only updates the preview.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActionBar
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    // MARK: - Live Preview Card

    /// Miniature mock that mirrors the real home screen surfaces a theme
    /// touches — selected pill, FAB, tinted progress bar — so the user can
    /// gut-check contrast in their current appearance mode before committing.
    private var livePreviewCard: some View {
        let primary = previewTheme.primaryColor

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Live preview")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text(previewTheme.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundColor(primary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(primary.opacity(0.14)))
                    .contentTransition(.identity)
                    .animation(Theme.Motion.snappy, value: previewTheme.id)
            }

            HStack(spacing: Theme.Spacing.sm) {
                previewPill(title: "Today", isSelected: false, primary: primary)
                previewPill(title: "Week", isSelected: true, primary: primary)
                previewPill(title: "Month", isSelected: false, primary: primary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Spent this week")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$324.50")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.tertiarySystemBackground)
                        Capsule()
                            .fill(primary)
                            .frame(width: proxy.size.width * 0.65)
                            .animation(Theme.Motion.tap, value: previewTheme.id)
                    }
                }
                .frame(height: 8)
            }

            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                Text("The accent flows through pills, buttons, charts, and the tab bar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(primary)
                        .frame(width: 40, height: 40)
                        .shadow(color: primary.opacity(0.3), radius: 6, x: 0, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .animation(Theme.Motion.tap, value: previewTheme.id)
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    private func previewPill(title: String, isSelected: Bool, primary: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(isSelected ? primary : Color.tertiarySystemBackground)
            )
            .animation(Theme.Motion.snappy, value: previewTheme.id)
    }

    // MARK: - Swatch Grid

    private var swatchGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg)
        ]

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Themes")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if !proManager.isPro {
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
                ForEach(AppTheme.all) { theme in
                    swatchButton(theme)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
        )
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

                    Circle()
                        .fill(theme.primaryColor)
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

    // MARK: - Bottom Action Bar

    /// Sticky action bar pinned to the bottom safe area. Three states:
    ///
    /// - **Pro lock**: free user previewing a Pro theme → "Unlock <Theme>
    ///   with Pro" button in `appPrimary`. Tap opens the paywall.
    /// - **Apply**: there's a real change to commit (preview ≠ saved) and
    ///   the theme is unlocked → button in the previewed theme's primary
    ///   colour, labelled "Apply <Theme>". Tap commits via `themeStore`.
    /// - **No-op**: preview matches the saved theme → disabled button
    ///   reading "<Theme> is active", just so the bar doesn't
    ///   appear/disappear mid-interaction (which feels janky).
    private var bottomActionBar: some View {
        let isLocked = isPreviewingProTheme
        let hasChange = previewTheme.id != themeStore.currentTheme.id

        let label: String = {
            if isLocked { return "Unlock \(previewTheme.displayName) with Pro" }
            if hasChange { return "Apply \(previewTheme.displayName)" }
            return "\(previewTheme.displayName) is active"
        }()

        let icon: String? = isLocked ? "lock.fill" : (hasChange ? nil : "checkmark")

        let buttonColor: Color = {
            if isLocked { return Color.appPrimary }
            if hasChange { return previewTheme.primaryColor }
            return Color.gray.opacity(0.35)
        }()

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
                        .fill(buttonColor)
                )
                .shadow(
                    color: isInteractive ? buttonColor.opacity(0.35) : .clear,
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

    // MARK: - Tap handling

    /// Swatch tap = preview only. Lets the user audition any theme in the
    /// live preview card without committing. Commit happens via the
    /// bottom Apply button.
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
    ThemePickerView()
        .environmentObject(ThemeStore.shared)
        .environmentObject(ProManager.shared)
}
