import SwiftUI

/// One-time thank-you shown when a past donor's grandfather grant is
/// first applied (see `ProManager.scanForDonorGrant()`).
///
/// Founder ($4.99+ tip): permanent Pro. Smaller tip: 1 year of Pro.
/// This is a gift, not a sell — no plan cards, no CTA other than a
/// warm dismiss.
struct DonorThanksView: View {
    let grant: ProManager.DonorGrant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.lg)

            HeroGlyph(systemName: "heart.fill")

            VStack(spacing: Theme.Spacing.sm) {
                Text("Thanks for supporting CashLens early")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Pro is on us.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.appPrimary)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            if grant == .founder {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("FOUNDER")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                }
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.appPrimary.opacity(0.12)))
            }

            Spacer(minLength: Theme.Spacing.lg)

            Button {
                HapticManager.shared.success()
                dismiss()
            } label: {
                Text("Enjoy Pro")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md + 4)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xxl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var detailText: String {
        switch grant {
        case .founder:
            return "Your tip helped build CashLens — every Pro feature is yours, forever."
        case .yearOfPro:
            return "Your tip helped build CashLens — every Pro feature is yours for the next year."
        }
    }
}

#Preview {
    DonorThanksView(grant: .founder)
}
