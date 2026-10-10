import SwiftUI

enum WrappedRenderMode {
    /// Full-screen story. Amounts are the user's own, on this phone.
    case player
    /// 360×640 point card rendered to a 1080×1920 PNG. No blur, no motion.
    case share
}

struct WrappedCardView: View {
    let page: WrappedPageKind
    let stats: WrappedStats
    var showAmounts: Bool
    var mode: WrappedRenderMode

    private var copy: WrappedCardCopy {
        WrappedCopy.content(page: page, stats: stats, showAmounts: showAmounts)
    }

    private var theme: WrappedTheme {
        WrappedTheme.theme(for: page)
    }

    var body: some View {
        let topInset: CGFloat = mode == .player ? 118 : 36
        let bottomInset: CGFloat = mode == .player ? 210 : 32

        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                Text(copy.kicker)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.1)
                    .foregroundColor(theme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 18)

                if let icon = copy.icon {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(theme.accent)
                        .padding(.bottom, 18)
                        .accessibilityHidden(true)
                }

                Text(copy.hero)
                    .font(.system(size: mode == .share ? 48 : 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(copy.line)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.9))
                    .lineSpacing(3)
                    .lineLimit(6)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 16)
                    .multilineTextAlignment(.leading)

                if !copy.footnote.isEmpty {
                    Text(copy.footnote)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.62))
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 14)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 16)

                if mode == .share {
                    Text("CashLens · on this phone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [copy.kicker, copy.hero, copy.line, copy.footnote]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private var background: some View {
        ZStack {
            theme.base
            RadialGradient(
                colors: [theme.glow.opacity(0.95), theme.glow.opacity(0.35), theme.base],
                center: .top,
                startRadius: 10,
                endRadius: 560
            )
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.clear, Color.black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct WrappedTheme {
    var base: Color
    var glow: Color
    var accent: Color

    static func theme(for page: WrappedPageKind) -> WrappedTheme {
        switch page {
        case .total:
            return WrappedTheme(base: rgb(18, 12, 32), glow: rgb(132, 78, 196), accent: rgb(236, 214, 255))
        case .topCategory:
            return WrappedTheme(base: rgb(36, 14, 24), glow: rgb(206, 92, 112), accent: rgb(255, 216, 212))
        case .topMerchant:
            return WrappedTheme(base: rgb(12, 18, 40), glow: rgb(78, 112, 214), accent: rgb(214, 226, 255))
        case .biggestDay:
            return WrappedTheme(base: rgb(40, 18, 12), glow: rgb(214, 122, 64), accent: rgb(255, 226, 196))
        case .funFact:
            return WrappedTheme(base: rgb(10, 30, 28), glow: rgb(46, 158, 136), accent: rgb(210, 255, 238))
        case .paymentSplit:
            return WrappedTheme(base: rgb(8, 22, 38), glow: rgb(42, 146, 204), accent: rgb(210, 242, 255))
        case .closing:
            return WrappedTheme(base: rgb(24, 12, 38), glow: rgb(156, 92, 196), accent: rgb(255, 222, 246))
        }
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
}

struct WrappedCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            card(.total, amounts: true).previewDisplayName("Total")
            card(.total, amounts: false).previewDisplayName("Total hidden")
            card(.topCategory, amounts: true).previewDisplayName("Category")
            card(.topMerchant, amounts: true).previewDisplayName("Merchant")
            card(.biggestDay, amounts: false).previewDisplayName("Biggest day hidden")
            card(.funFact, amounts: true).previewDisplayName("Fun fact")
            card(.paymentSplit, amounts: false).previewDisplayName("UPI hidden")
            card(.closing, amounts: false).previewDisplayName("Closing hidden")
            WrappedCardView(page: .total, stats: .emptyPreview, showAmounts: true, mode: .share)
                .previewDisplayName("Empty")
        }
        .frame(width: 360, height: 640)
        .previewLayout(.fixed(width: 360, height: 640))
    }

    private static func card(_ page: WrappedPageKind, amounts: Bool) -> some View {
        WrappedCardView(page: page, stats: .preview, showAmounts: amounts, mode: .share)
    }
}
