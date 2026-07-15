import SwiftUI

/// Full-screen privacy cover + lock screen, mounted at the very top
/// of the root ZStack in `CashLensApp` (above onboarding, above
/// everything).
///
/// Two visual modes driven by `AppLockManager`:
///
///   • **Cover only** (`isLocked == false`) — the scene went
///     inactive (app switcher, notification shade). Just the brand
///     mark on a clean page so the switcher snapshot shows zero
///     financial data. No button — the moment the scene is active
///     again the cover fades out on its own.
///   • **Locked** (`isLocked == true`) — real re-auth required.
///     Same brand mark plus an "Unlock CashLens" CTA. The system
///     prompt auto-fires once on appear; the button re-triggers
///     after a cancel or failure.
struct AppLockView: View {
    @ObservedObject var lockManager: AppLockManager

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                // Same treatment as the onboarding welcome mark —
                // hairline edge + brand-tinted halo — so the lock
                // screen reads as CashLens, not a generic gate.
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                    )
                    .shadow(color: Color.appPrimary.opacity(0.20), radius: 24, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)

                if lockManager.isLocked {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("CashLens is locked")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Your expenses stay private until you unlock.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Theme.Spacing.xxl)
                }

                Spacer()

                if lockManager.isLocked {
                    unlockButton
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.bottom, Theme.Spacing.xxxl + Theme.Spacing.lg)
                }
            }
        }
        .onAppear {
            lockManager.autoPromptIfNeeded()
        }
    }

    private var unlockButton: some View {
        Button {
            HapticManager.shared.mediumTap()
            lockManager.requestUnlock()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: AppLockManager.unlockMethodSymbol)
                    .font(.system(size: 17, weight: .semibold))
                Text("Unlock CashLens")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md + 4)
            .background(Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .primaryGlow(strength: 0.28)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(lockManager.isAuthenticating)
        .opacity(lockManager.isAuthenticating ? 0.6 : 1)
        .frame(maxWidth: 360)
    }
}

// MARK: - Preview

struct AppLockView_Previews: PreviewProvider {
    static var previews: some View {
        AppLockView(lockManager: .shared)
    }
}
