import SwiftUI

/// Pro-gated picker that lets the user choose an alternate app icon.
///
/// Free users can browse and tap to preview, but applying anything other
/// than the primary `Mauve` icon opens the paywall — matching the
/// `ThemePickerView` UX so users have a consistent mental model.
///
/// The picker shows a 2 × 4 grid (8 options total) of generously sized icon
/// tiles with rounded corners that mirror the iOS home-screen grid. The
/// active icon gets a checkmark badge and a thin accent ring.
struct AppIconPickerView: View {

    @EnvironmentObject private var iconStore: AppIconStore
    @EnvironmentObject private var proManager: ProManager
    @Environment(\.dismiss) private var dismiss

    @State private var previewIcon: AppIconOption
    @State private var showingPaywall = false
    @State private var errorBanner: String?
    @State private var isApplying = false

    init() {
        _previewIcon = State(initialValue: AppIconStore.shared.currentIcon)
    }

    private var isPreviewingProIcon: Bool {
        !previewIcon.isPrimary && !proManager.isPro
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    heroPreview
                    iconGrid

                    if isPreviewingProIcon {
                        proCallToAction
                    }

                    if !UIApplication.shared.supportsAlternateIcons {
                        unsupportedNotice
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Color.systemGroupedBackground)
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .alert("Couldn't change icon", isPresented: Binding(
                get: { errorBanner != nil },
                set: { if !$0 { errorBanner = nil } }
            )) {
                Button("OK", role: .cancel) { errorBanner = nil }
            } message: {
                Text(errorBanner ?? "")
            }
        }
    }

    // MARK: - Hero preview

    /// Large rounded-square preview of the currently-previewed icon. Mirrors
    /// the iOS home-screen icon mask so the user sees exactly what'll appear
    /// after applying. Animates between selections with a soft spring.
    private var heroPreview: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Live preview")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            iconImage(previewIcon, size: 132, cornerRadius: 30)
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .scaleEffect(isApplying ? 0.95 : 1.0)
                .animation(Theme.Motion.tap, value: previewIcon.id)
                .animation(Theme.Motion.tap, value: isApplying)

            VStack(spacing: 4) {
                Text(previewIcon.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                    .contentTransition(.opacity)
                    .animation(Theme.Motion.snappy, value: previewIcon.id)

                Text(previewIcon.id == iconStore.currentIcon.id
                     ? "Currently applied"
                     : "Tap apply to use this icon")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .contentTransition(.opacity)
                    .animation(Theme.Motion.snappy, value: previewIcon.id)
                    .animation(Theme.Motion.snappy, value: iconStore.currentIcon.id)
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    // MARK: - Grid

    private var iconGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg),
            GridItem(.flexible(), spacing: Theme.Spacing.lg)
        ]

        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("Icons")
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
                ForEach(AppIconOption.all) { icon in
                    iconTile(icon)
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    private func iconTile(_ icon: AppIconOption) -> some View {
        let isPreview = icon.id == previewIcon.id
        let isApplied = icon.id == iconStore.currentIcon.id

        return Button {
            handleTap(icon)
        } label: {
            VStack(spacing: Theme.Spacing.xs + 2) {
                ZStack(alignment: .topTrailing) {
                    iconImage(icon, size: 60, cornerRadius: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isPreview ? Color.appPrimary : Color.clear, lineWidth: 2.5)
                        )
                        .scaleEffect(isPreview ? 1.05 : 1.0)
                        .animation(Theme.Motion.tap, value: isPreview)

                    if isApplied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.appPrimary))
                            .offset(x: 6, y: -6)
                    }

                    if !proManager.isPro && !icon.isPrimary {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .offset(x: 6, y: -6)
                    }
                }

                Text(icon.displayName)
                    .font(.caption2.weight(isApplied ? .bold : .medium))
                    .foregroundColor(isApplied ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Loads the icon image from the asset catalog. Falls back to a neutral
    /// placeholder if the asset is missing — defensive so we don't crash if
    /// the build settings get out of sync with the picker catalog.
    private func iconImage(_ icon: AppIconOption, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let ui = UIImage(named: icon.previewAssetName) {
                Image(uiImage: ui)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.tertiarySystemBackground)
                    .overlay(
                        Image(systemName: "questionmark.app.dashed")
                            .font(.system(size: size * 0.35, weight: .semibold))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Pro CTA / Notices

    private var proCallToAction: some View {
        Button {
            HapticManager.shared.lightTap()
            showingPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.appPrimary))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock \(previewIcon.displayName) with Pro")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Pick from any of the alternate icons.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Color.secondarySystemGroupedBackground)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var unsupportedNotice: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Custom icons aren't supported on this device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    // MARK: - Tap handling

    private func handleTap(_ icon: AppIconOption) {
        withAnimation(Theme.Motion.tap) {
            previewIcon = icon
        }

        if !proManager.isPro && !icon.isPrimary {
            HapticManager.shared.warning()
            showingPaywall = true
            return
        }

        // Pro user (or primary tap): apply for real.
        Task { await applyToOS(icon) }
    }

    private func applyToOS(_ icon: AppIconOption) async {
        guard icon.id != iconStore.currentIcon.id else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            try await iconStore.apply(icon)
            HapticManager.shared.success()
        } catch {
            errorBanner = error.localizedDescription
            HapticManager.shared.warning()
            // Revert preview to the still-applied icon so the UI doesn't lie.
            withAnimation(Theme.Motion.snappy) {
                previewIcon = iconStore.currentIcon
            }
        }
    }
}

#Preview {
    AppIconPickerView()
        .environmentObject(AppIconStore.shared)
        .environmentObject(ProManager.shared)
}
