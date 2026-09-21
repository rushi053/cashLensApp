import UIKit
import SwiftUI

/// Generates a polished, accountant-friendly PDF report summarizing the user's spending
/// for a selected date range. Designed for Pro users — the output is the "wow" artifact
/// they can share with an accountant, a partner, or simply save for their records.
///
/// Usage:
///
/// ```swift
/// let data = PDFReportGenerator.ReportData(...)
/// let url = try PDFReportGenerator.generate(data: data)
/// // present share sheet with `url`
/// ```
enum PDFReportGenerator {

    // MARK: - Input Model

    /// Everything the report needs, packaged up so the generator is fully deterministic
    /// and can be called from a background task.
    struct ReportData {
        let title: String                // e.g. "CashLens Spending Report"
        let subtitle: String             // e.g. "Apr 1 – Apr 22, 2026"
        let rangeStart: Date
        let rangeEnd: Date
        let generatedAt: Date
        let currencyCode: String         // e.g. "USD"

        let totalSpent: Double
        let transactionCount: Int
        let averagePerTransaction: Double
        let previousTotal: Double        // prior same-length period (0 if none)

        let dailyPace: Double            // optional enrichment (0 if unknown)
        let projectedTotal: Double       // velocity projection (0 if completed)
        let isProjecting: Bool

        let categories: [CategoryRow]    // sorted biggest -> smallest
        let topExpenses: [ExpenseRow]    // already sorted biggest -> smallest (cap at ~40)

        struct CategoryRow {
            let name: String
            let amount: Double
            let percentage: Double       // 0...100
            let transactionCount: Int
        }

        struct ExpenseRow {
            let date: Date
            let title: String            // description or category fallback
            let category: String
            let amount: Double
        }

        func formatted(_ amount: Double) -> String {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currencyCode
            f.maximumFractionDigits = 2
            return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        }
    }

    enum GeneratorError: Error, LocalizedError {
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .writeFailed: return "Couldn't write the PDF to disk."
            }
        }
    }

    // MARK: - Layout Constants

    private static let pageWidth: CGFloat = 612   // 8.5"
    private static let pageHeight: CGFloat = 792  // 11"
    private static let margin: CGFloat = 48

    private static let brand = UIColor(red: 0.63, green: 0.44, blue: 0.79, alpha: 1.0) // mauve fallback

    // MARK: - Public

    /// Writes the PDF to a temporary URL and returns it. Safe to call from a background
    /// queue; the result can be passed straight to `UIActivityViewController`.
    static func generate(data: ReportData) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(
            bounds: bounds,
            format: makeFormat(data: data)
        )

        let fileName = "CashLens-Report-\(fileSafeDate(data.rangeStart))-to-\(fileSafeDate(data.rangeEnd)).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try renderer.writePDF(to: tempURL) { context in
                var state = DrawState(context: context, pageIndex: 0)
                drawCoverAndSummary(data: data, state: &state)
                drawCategoryBreakdown(data: data, state: &state)
                drawTopExpenses(data: data, state: &state)
                // Stamp the footer on the final page (breakPage() only runs between pages).
                if state.hasDrawnFirstPage {
                    state.drawFooter()
                }
            }
        } catch {
            throw GeneratorError.writeFailed
        }

        return tempURL
    }

    // MARK: - Drawing State

    private struct DrawState {
        let context: UIGraphicsPDFRendererContext
        var pageIndex: Int
        var y: CGFloat = margin
        var hasDrawnFirstPage: Bool = false

        mutating func beginPageIfNeeded() {
            if !hasDrawnFirstPage {
                context.beginPage()
                hasDrawnFirstPage = true
                y = margin
                drawHeader()
            }
        }

        mutating func breakPage() {
            drawFooter()
            pageIndex += 1
            context.beginPage()
            y = margin
            drawHeader()
        }

        mutating func ensureSpace(for height: CGFloat) {
            if y + height > pageHeight - margin - 32 { // 32 reserves room for footer
                breakPage()
            }
        }

        private func drawHeader() {
            // Small brand mark at the top of each page.
            let text = "CashLens"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor.systemGray
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(x: margin, y: margin - 24),
                withAttributes: attrs
            )
            // A thin rule under the header.
            let rule = UIBezierPath()
            rule.move(to: CGPoint(x: margin, y: margin - 10))
            rule.addLine(to: CGPoint(x: pageWidth - margin, y: margin - 10))
            UIColor.systemGray5.setStroke()
            rule.lineWidth = 0.5
            rule.stroke()
            _ = size
        }

        fileprivate func drawFooter() {
            let text = "Generated by CashLens · Page \(pageIndex + 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.systemGray
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(
                    x: pageWidth - margin - size.width,
                    y: pageHeight - margin + 8
                ),
                withAttributes: attrs
            )
        }
    }

    // MARK: - Cover & Summary

    private static func drawCoverAndSummary(data: ReportData, state: inout DrawState) {
        state.beginPageIfNeeded()

        // Title
        state.y += 12
        drawText(
            data.title,
            font: .systemFont(ofSize: 28, weight: .bold),
            color: .label,
            at: &state
        )
        state.y += 4

        // Subtitle (date range)
        drawText(
            data.subtitle,
            font: .systemFont(ofSize: 14, weight: .medium),
            color: .secondaryLabel,
            at: &state
        )
        state.y += 24

        // Big total card
        drawTotalBanner(data: data, at: &state)
        state.y += 28

        // Stat tiles (2x3 grid)
        drawStatGrid(data: data, at: &state)
        state.y += 24
    }

    private static func drawTotalBanner(data: ReportData, at state: inout DrawState) {
        let bannerHeight: CGFloat = 96
        let rect = CGRect(
            x: margin,
            y: state.y,
            width: pageWidth - margin * 2,
            height: bannerHeight
        )

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
        brand.withAlphaComponent(0.08).setFill()
        path.fill()
        brand.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: brand,
            .kern: 0.8
        ]
        ("TOTAL SPENT" as NSString).draw(
            at: CGPoint(x: rect.minX + 20, y: rect.minY + 16),
            withAttributes: labelAttrs
        )

        // Value
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (data.formatted(data.totalSpent) as NSString).draw(
            at: CGPoint(x: rect.minX + 20, y: rect.minY + 34),
            withAttributes: valueAttrs
        )

        // Comparison (right side)
        if data.previousTotal > 0 {
            let change = ((data.totalSpent - data.previousTotal) / data.previousTotal) * 100
            let arrow = change >= 0 ? "▲" : "▼"
            let color: UIColor = change >= 0 ? .systemRed : .systemGreen
            let str = "\(arrow) \(String(format: "%.1f", abs(change)))% vs previous"

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: color
            ]
            let size = (str as NSString).size(withAttributes: attrs)
            (str as NSString).draw(
                at: CGPoint(x: rect.maxX - 20 - size.width, y: rect.minY + 16),
                withAttributes: attrs
            )

            // Prev total under it
            let prevAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let prevStr = "Previous: \(data.formatted(data.previousTotal))"
            let prevSize = (prevStr as NSString).size(withAttributes: prevAttrs)
            (prevStr as NSString).draw(
                at: CGPoint(x: rect.maxX - 20 - prevSize.width, y: rect.minY + 34),
                withAttributes: prevAttrs
            )
        }

        state.y = rect.maxY
    }

    private static func drawStatGrid(data: ReportData, at state: inout DrawState) {
        let tileHeight: CGFloat = 72
        let gap: CGFloat = 12

        var tiles: [StatTile] = [
            StatTile(title: "Transactions", value: "\(data.transactionCount)", subtitle: nil),
            StatTile(title: "Avg / Transaction", value: data.formatted(data.averagePerTransaction), subtitle: nil),
            StatTile(title: "Daily Pace", value: data.formatted(data.dailyPace), subtitle: "per day")
        ]
        if data.isProjecting, data.projectedTotal > 0 {
            tiles.append(StatTile(
                title: "Projected Total",
                value: data.formatted(data.projectedTotal),
                subtitle: "end of period"
            ))
        }

        let columns = 3
        let rows = Int((Double(tiles.count) / Double(columns)).rounded(.up))
        let gridWidth = pageWidth - margin * 2
        let tileWidth = (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)

        for rowIndex in 0..<rows {
            for col in 0..<columns {
                let idx = rowIndex * columns + col
                guard idx < tiles.count else { continue }
                let tile = tiles[idx]
                let x = margin + CGFloat(col) * (tileWidth + gap)
                let y = state.y + CGFloat(rowIndex) * (tileHeight + gap)
                drawStatTile(
                    tile: tile,
                    rect: CGRect(x: x, y: y, width: tileWidth, height: tileHeight)
                )
            }
        }
        state.y += CGFloat(rows) * tileHeight + CGFloat(max(0, rows - 1)) * gap
    }

    private struct StatTile {
        let title: String
        let value: String
        let subtitle: String?
    }

    private static func drawStatTile(tile: StatTile, rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        UIColor.secondarySystemBackground.setFill()
        path.fill()
        UIColor.systemGray5.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 0.5
        ]
        (tile.title.uppercased() as NSString).draw(
            at: CGPoint(x: rect.minX + 14, y: rect.minY + 12),
            withAttributes: titleAttrs
        )

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        (tile.value as NSString).draw(
            at: CGPoint(x: rect.minX + 14, y: rect.minY + 28),
            withAttributes: valueAttrs
        )

        if let subtitle = tile.subtitle {
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            (subtitle as NSString).draw(
                at: CGPoint(x: rect.minX + 14, y: rect.minY + 50),
                withAttributes: subAttrs
            )
        }
    }

    // MARK: - Category Breakdown

    private static func drawCategoryBreakdown(data: ReportData, state: inout DrawState) {
        guard !data.categories.isEmpty else { return }

        state.ensureSpace(for: 120)
        drawSectionHeader("Category Breakdown", at: &state)
        state.y += 12

        for category in data.categories.prefix(10) {
            state.ensureSpace(for: 44)
            drawCategoryRow(category: category, data: data, at: &state)
            state.y += 8
        }

        state.y += 16
    }

    private static func drawCategoryRow(
        category: ReportData.CategoryRow,
        data: ReportData,
        at state: inout DrawState
    ) {
        let rowWidth = pageWidth - margin * 2
        let rowHeight: CGFloat = 36

        // Name + amount
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        (category.name as NSString).draw(
            at: CGPoint(x: margin, y: state.y),
            withAttributes: nameAttrs
        )

        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let countStr = "\(category.transactionCount) txns"
        (countStr as NSString).draw(
            at: CGPoint(x: margin + 200, y: state.y + 1),
            withAttributes: countAttrs
        )

        let amountStr = data.formatted(category.amount)
        let amountAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let amountSize = (amountStr as NSString).size(withAttributes: amountAttrs)
        (amountStr as NSString).draw(
            at: CGPoint(x: pageWidth - margin - amountSize.width, y: state.y),
            withAttributes: amountAttrs
        )

        // Percentage under amount
        let pctStr = "\(String(format: "%.1f", category.percentage))%"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let pctSize = (pctStr as NSString).size(withAttributes: pctAttrs)
        (pctStr as NSString).draw(
            at: CGPoint(x: pageWidth - margin - pctSize.width, y: state.y + 16),
            withAttributes: pctAttrs
        )

        // Progress bar
        let barY = state.y + 22
        let barHeight: CGFloat = 6
        let track = UIBezierPath(
            roundedRect: CGRect(x: margin, y: barY, width: rowWidth - 80, height: barHeight),
            cornerRadius: 3
        )
        UIColor.systemGray6.setFill()
        track.fill()

        let fillWidth = (rowWidth - 80) * CGFloat(category.percentage / 100)
        if fillWidth > 0 {
            let fill = UIBezierPath(
                roundedRect: CGRect(x: margin, y: barY, width: fillWidth, height: barHeight),
                cornerRadius: 3
            )
            brand.setFill()
            fill.fill()
        }

        state.y += rowHeight
    }

    // MARK: - Top Expenses

    private static func drawTopExpenses(data: ReportData, state: inout DrawState) {
        guard !data.topExpenses.isEmpty else { return }

        state.ensureSpace(for: 80)
        drawSectionHeader("Top Expenses", at: &state)
        state.y += 8

        // Column headers
        drawColumnHeaders(at: &state)
        state.y += 6

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        for (index, expense) in data.topExpenses.enumerated() {
            state.ensureSpace(for: 20)
            drawExpenseRow(
                expense: expense,
                data: data,
                dateFormatter: dateFormatter,
                zebra: index % 2 == 1,
                at: &state
            )
        }
    }

    private static func drawColumnHeaders(at state: inout DrawState) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 0.5
        ]
        ("DATE" as NSString).draw(at: CGPoint(x: margin, y: state.y), withAttributes: attrs)
        ("DESCRIPTION" as NSString).draw(at: CGPoint(x: margin + 70, y: state.y), withAttributes: attrs)
        ("CATEGORY" as NSString).draw(at: CGPoint(x: margin + 290, y: state.y), withAttributes: attrs)

        let amtStr = "AMOUNT" as NSString
        let size = amtStr.size(withAttributes: attrs)
        amtStr.draw(
            at: CGPoint(x: pageWidth - margin - size.width, y: state.y),
            withAttributes: attrs
        )
        state.y += 14

        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: margin, y: state.y))
        rule.addLine(to: CGPoint(x: pageWidth - margin, y: state.y))
        UIColor.systemGray5.setStroke()
        rule.lineWidth = 0.5
        rule.stroke()
    }

    private static func drawExpenseRow(
        expense: ReportData.ExpenseRow,
        data: ReportData,
        dateFormatter: DateFormatter,
        zebra: Bool,
        at state: inout DrawState
    ) {
        let rowHeight: CGFloat = 20

        if zebra {
            let bg = UIBezierPath(rect: CGRect(
                x: margin - 4,
                y: state.y,
                width: pageWidth - margin * 2 + 8,
                height: rowHeight
            ))
            UIColor.systemGray6.withAlphaComponent(0.4).setFill()
            bg.fill()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.label
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]

        let yText = state.y + 5
        (dateFormatter.string(from: expense.date) as NSString).draw(
            at: CGPoint(x: margin, y: yText),
            withAttributes: subAttrs
        )

        let descText = truncate(expense.title, max: 34)
        (descText as NSString).draw(
            at: CGPoint(x: margin + 70, y: yText),
            withAttributes: attrs
        )

        let catText = truncate(expense.category, max: 18)
        (catText as NSString).draw(
            at: CGPoint(x: margin + 290, y: yText),
            withAttributes: subAttrs
        )

        let amtStr = data.formatted(expense.amount)
        let amtAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let size = (amtStr as NSString).size(withAttributes: amtAttrs)
        (amtStr as NSString).draw(
            at: CGPoint(x: pageWidth - margin - size.width, y: yText),
            withAttributes: amtAttrs
        )

        state.y += rowHeight
    }

    // MARK: - Shared Helpers

    private static func drawSectionHeader(_ title: String, at state: inout DrawState) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        (title as NSString).draw(
            at: CGPoint(x: margin, y: state.y),
            withAttributes: attrs
        )
        state.y += 20

        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: margin, y: state.y))
        rule.addLine(to: CGPoint(x: pageWidth - margin, y: state.y))
        brand.withAlphaComponent(0.5).setStroke()
        rule.lineWidth = 1.2
        rule.stroke()
        state.y += 8
    }

    private static func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        at state: inout DrawState
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: margin, y: state.y),
            withAttributes: attrs
        )
        state.y += size.height
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        let idx = s.index(s.startIndex, offsetBy: max - 1)
        return String(s[..<idx]) + "…"
    }

    private static func fileSafeDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func makeFormat(data: ReportData) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: data.title,
            kCGPDFContextAuthor as String: "CashLens",
            kCGPDFContextCreator as String: "CashLens iOS"
        ]
        return format
    }
}
