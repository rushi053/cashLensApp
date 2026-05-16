import SwiftUI

/// The canonical primary CTA used across the app: "Create Budget", "Add Your First Expense",
/// "Backup Now", "Save Changes", etc.
///
/// Name retained for backwards compatibility with existing call sites,
/// but the fill is now a **solid** `Color.appPrimary` (no gradient) to
/// match the app-wide no-gradient design language.
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
            .background(Color.appPrimary)
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
