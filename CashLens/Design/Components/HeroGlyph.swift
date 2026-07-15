import SwiftUI

/// Hero symbol for sheet headers (paywall, about, import/export,
/// donation, privacy dashboard…).
///
/// Replaces the old "icon in a tinted circle bubble" medallion, which
/// read as template/stock when repeated on every sheet. The premium
/// treatment is the symbol itself, drawn large with hierarchical
/// rendering — SF Symbols' multi-tone mode gives the glyph its own
/// depth without any backdrop shape.
struct HeroGlyph: View {
    let systemName: String
    var tint: Color = .appPrimary
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            // Fixed square frame so headers keep identical vertical
            // rhythm regardless of each glyph's intrinsic proportions.
            .frame(width: size + 20, height: size + 20)
    }
}

#Preview {
    HStack(spacing: 24) {
        HeroGlyph(systemName: "crown.fill")
        HeroGlyph(systemName: "lock.shield.fill")
        HeroGlyph(systemName: "heart.fill", tint: .pink)
    }
    .padding()
}
