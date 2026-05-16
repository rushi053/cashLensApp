//
//  WidgetProUpsellView.swift
//  CashLensWidgets
//
//  Shared "Unlock with CashLens Pro" tile shown on Pro-gated widget
//  surfaces (Budget Progress, Subscriptions Due, No-Spend Streak) when
//  the snapshot reports `isPro == false`.
//
//  Visually quiet — a small lock medallion + the widget's name + a
//  one-line CTA. We deliberately avoid a hard-sell tone so Pro users
//  whose subscription has lapsed don't feel ambushed.
//

import SwiftUI
import WidgetKit

struct WidgetProUpsellView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family
    let themeId: String
    let title: String

    var body: some View {
        let theme = WidgetTheme.resolve(id: themeId)
        let primary = theme.primary(for: scheme)

        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(primary.opacity(0.18))
                Image(systemName: "lock.fill")
                    .font(.system(size: family == .systemSmall ? 14 : 16, weight: .semibold))
                    .foregroundStyle(primary)
            }
            .frame(width: family == .systemSmall ? 32 : 40,
                   height: family == .systemSmall ? 32 : 40)

            Text(title)
                .font(.system(size: family == .systemSmall ? 12 : 14,
                              weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("Unlock with CashLens Pro")
                .font(.system(size: family == .systemSmall ? 9 : 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(8)
    }
}
