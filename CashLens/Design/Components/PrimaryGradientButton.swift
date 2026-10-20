import SwiftUI

/// The canonical primary CTA used across the app: "Create Budget", "Add Your First Expense",
/// "Backup Now", "Save Changes", etc.
///
/// Fill is the sanctioned hero duotone (`LinearGradient.appDuotone`) —
/// primary → primary-blended-toward-secondary — so the active theme's
/// designed color pair shows on every primary action, not just a flat
/// accent swap. This is one of the few duotone surfaces in the app;
/// everything non-hero stays solid.
struct PrimaryGradientButton: View {
    let title: String
    var icon: String? = nil
    var width: Width = .expanded
    var isEnabled: Bool = true
    let action: () -> Void

    enum Width {
        case expanded
        case hug
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.headline)
                }
                Text(title)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: width == .expanded ? .infinity : nil)
            .padding(.horizontal, width == .hug ? Theme.Spacing.xxl : Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
            .background(LinearGradient.appDuotone)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .primaryGlow(strength: isEnabled ? 0.3 : 0)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Secondary outline CTA, used alongside primary actions (e.g. "Restore Purchases").
struct SecondaryOutlineButton: View {
    let title: String
    var icon: String? = nil
    var width: Width = .expanded
    let action: () -> Void

    enum Width {
        case expanded
        case hug
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.appPrimary)
            .frame(maxWidth: width == .expanded ? .infinity : nil)
            .padding(.horizontal, width == .hug ? Theme.Spacing.xxl : Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md + 2)
            .overlay(
                Capsule()
                    .stroke(Color.appPrimary.opacity(0.5), lineWidth: Theme.Stroke.thin)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        PrimaryGradientButton(title: "Create Budget", icon: "plus.circle.fill") {}
        PrimaryGradientButton(title: "Save Changes") {}
        PrimaryGradientButton(title: "Disabled", isEnabled: false) {}
        SecondaryOutlineButton(title: "Restore Purchases") {}
    }
    .padding()
}
