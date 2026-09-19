import SwiftUI

/// A `LazyVGrid` whose column count is derived from the container
/// width (like `GridItem.adaptive`) but **rounded down to an even
/// number** above a threshold.
///
/// Why: iPhone Duo's partially-folded poses put a division region down
/// the middle of the inner display. Apple's guidance is for grids to
/// prefer even column counts so no tile straddles the fold. Phones and
/// iPads get the same counts they would from an adaptive grid — 4 on an
/// iPhone category picker, 6 in an iPad form sheet — but the 5s and 7s
/// that adaptive layout produces at in-between widths become 4s and 6s.
///
/// `evenColumnsAbove` lets a grid keep a deliberate odd count at small
/// sizes (the theme picker wants 3 on phones): counts *greater than*
/// this value are rounded down to even; counts at or below it are kept.
struct EvenColumnGrid<Content: View>: View {
    let minimumItemWidth: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let evenColumnsAbove: Int
    let alignment: HorizontalAlignment
    let itemAlignment: Alignment
    @ViewBuilder let content: () -> Content

    /// Container width and any Duo hinge gutter, measured together.
    private struct Measurement: Equatable {
        var width: CGFloat = 0
        var divisionGutter: CGFloat = 0
    }

    @State private var measurement = Measurement()

    init(
        minimumItemWidth: CGFloat,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat,
        evenColumnsAbove: Int = 2,
        alignment: HorizontalAlignment = .center,
        itemAlignment: Alignment = .top,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minimumItemWidth = minimumItemWidth
        self.columnSpacing = columnSpacing
        self.rowSpacing = rowSpacing
        self.evenColumnsAbove = evenColumnsAbove
        self.alignment = alignment
        self.itemAlignment = itemAlignment
        self.content = content
    }

    /// Same arithmetic `GridItem.adaptive` uses, then the even rule.
    /// Before the first measurement (`measuredWidth == 0`) this yields
    /// 2, so the first frame is a sane two-column layout rather than a
    /// single stretched column.
    /// Column gap, widened by the hinge gutter when a division region
    /// is present (Duo 27.1; zero everywhere else).
    private var effectiveColumnSpacing: CGFloat {
        columnSpacing + measurement.divisionGutter
    }

    private var columnCount: Int {
        guard measurement.width > 0 else { return 2 }
        let fit = Int((measurement.width + effectiveColumnSpacing) / (minimumItemWidth + effectiveColumnSpacing))
        var count = max(1, fit)
        if count > evenColumnsAbove, count % 2 == 1 {
            count -= 1
        }
        return count
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: effectiveColumnSpacing, alignment: itemAlignment),
                count: columnCount
            ),
            alignment: alignment,
            spacing: rowSpacing
        ) {
            content()
        }
        .onGeometryChange(for: Measurement.self) { proxy in
            // `DuoLayoutSupport.divisionGutter` is 0 on today's SDK and
            // on every non-Duo device; see `DuoLayoutSupport.swift`.
            Measurement(
                width: proxy.size.width,
                divisionGutter: DuoLayoutSupport.divisionGutter(in: proxy)
            )
        } action: { newValue in
            measurement = newValue
        }
    }
}
