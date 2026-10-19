import SwiftUI

/// Left-aligned flow layout that wraps fixed-size chips onto as many
/// rows as the available width needs, instead of squeezing them into
/// one `HStack` and letting `lineLimit(1)` truncate the labels
/// ("Subs inc…", "Confide…").
///
/// Shared by the tag input card and the Pro teaser pill rows in
/// Insights. Every subview is measured at its ideal size; rows are
/// `rowSpacing` apart and chips `spacing` apart.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct Arrangement {
        let frames: [CGRect]
        let size: CGSize
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        let verticalGap = rowSpacing ?? spacing
        var frames: [CGRect] = []
        var rowStart = 0           // index of the first frame in the current row
        var rowY: CGFloat = 0
        var rowX: CGFloat = 0
        var rowHeight: CGFloat = 0

        // Items in one row are centred on the row's vertical midline so a
        // small badge sits level with the title beside it.
        func closeRow(upTo end: Int) {
            for index in rowStart..<end {
                frames[index].origin.y = rowY + (rowHeight - frames[index].height) / 2
            }
        }

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            // A single chip wider than the container (accessibility text
            // sizes: "Complete Backup", "Confidence band") would otherwise
            // be placed at its ideal width and clip at the card edge.
            // Re-measure against the available width so the chip wraps or
            // truncates instead; chips that fit are untouched.
            if size.width > maxWidth, maxWidth.isFinite {
                let constrained = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size = CGSize(width: min(constrained.width, maxWidth), height: constrained.height)
            }
            if rowX + size.width > maxWidth && rowX > 0 {
                closeRow(upTo: frames.count)
                rowStart = frames.count
                rowY += rowHeight + verticalGap
                rowX = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: rowX, y: rowY), size: size))
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        closeRow(upTo: frames.count)

        let totalHeight = rowY + rowHeight
        let usedWidth = frames.map { $0.maxX }.max() ?? 0
        return Arrangement(
            frames: frames,
            size: CGSize(width: usedWidth, height: totalHeight)
        )
    }
}
