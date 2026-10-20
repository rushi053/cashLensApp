import SwiftUI

/// One-time win-back sheet shown on the first foreground after a
/// Pro → free lapse (see `ProManager.evaluateWinBackPrompt()`).
///
/// Calm, honest framing: nothing was taken away — budgets, receipts
/// and history are untouched — the ask is only about keeping the
/// forward-looking features. Shown at most once per lapse; "No
/// thanks" silences it forever.
struct WinBackView: View {
    @EnvironmentObject var proManager: ProManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.lg)

            HeroGlyph(systemName: "crown.fill")

            VStack(spacing: Theme.Spacing.sm) {
                Text("Your Pro access ended")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Your budgets and data are untouched. Keep forecasts and insights?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            Spacer(minLength: Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    HapticManager.shared.mediumTap()
                    showingPaywall = true
                } label: {
                    VStack(spacing: 2) {
                        Text("Keep Pro")
                            .font(.system(size: 17, weight: .semibold))
                        if let yearly = proManager.yearlyProduct {
                            Text("\(yearly.displayPrice) / year")
                                .font(.system(size: 12, weight: .medium))
                                .opacity(0.85)
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md + 2)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    HapticManager.shared.lightTap()
                    proManager.declineWinBack()
                    dismiss()
                } label: {
                    Text("No thanks")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xxl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(context: .general)
        }
    }
}

#Preview {
    WinBackView()
        .environmentObject(ProManager.shared)
}
