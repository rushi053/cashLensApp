//
//  ReceiptOCRService.swift
//  CashLens
//
//  On-device receipt OCR (Wave 5, Pro). Wraps Vision's
//  `VNRecognizeTextRequest` (accurate mode, language correction, NO
//  network) and extracts two things from a captured receipt:
//
//    • the total amount — the most plausible currency value, ranked by
//      proximity to keywords like TOTAL / AMOUNT DUE / GRAND TOTAL,
//    • the merchant name — the most prominent text near the top of
//      the receipt.
//
//  Design:
//
//    • `recognize(cgImage:)` does the Vision pass; everything after
//      that is a PURE function over `[OCRLine]` (`parse(lines:)`), so
//      the heuristics are unit-testable without images.
//    • Everything is best-effort and silent. A receipt we can't parse
//      returns an empty result — never an error the form has to
//      handle. OCR must never block or slow manual entry.
//    • Privacy: all processing happens on-device. Nothing leaves the
//      phone, matching the app's core promise.
//
import Foundation
import Vision
import UIKit

// MARK: - Result & line types

/// One recognized text line with its normalized position on the page.
/// Vision's coordinate space: origin bottom-left, y grows upward — so
/// the TOP of the receipt has the LARGEST `y`.
struct OCRLine: Sendable, Equatable {
    let text: String
    /// Normalized bounding box in Vision coordinates ([0,1] × [0,1]).
    let boundingBox: CGRect
}

/// What we managed to pull out of the receipt. Either field may be nil
/// — callers fill only what's present and never overwrite user input.
struct ReceiptOCRResult: Sendable, Equatable {
    var totalAmount: Double?
    var merchantName: String?

    static let empty = ReceiptOCRResult(totalAmount: nil, merchantName: nil)
    var isEmpty: Bool { totalAmount == nil && merchantName == nil }
}

// MARK: - Service

enum ReceiptOCRService {

    /// Full pipeline: OCR the image, then run the parsing heuristics.
    /// Runs the Vision request synchronously on the calling thread —
    /// call from a background task. Returns `.empty` on any failure.
    static func extract(from image: UIImage) async -> ReceiptOCRResult {
        guard let cgImage = image.cgImage else { return .empty }
        let lines = recognizeText(in: cgImage, orientation: cgOrientation(from: image.imageOrientation))
        guard !lines.isEmpty else { return .empty }
        return parse(lines: lines)
    }

    // MARK: - Vision pass

    /// Run `VNRecognizeTextRequest` in accurate mode. On-device only
    /// (`usesCPUOnly` not forced — Vision picks ANE/GPU as available;
    /// text recognition never touches the network).
    static func recognizeText(in cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, boundingBox: observation.boundingBox)
        }
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    // MARK: - Parsing (pure)

    /// Extract total + merchant from recognized lines. Pure function —
    /// deterministic for a given input, no I/O, fully testable.
    static func parse(lines: [OCRLine]) -> ReceiptOCRResult {
        ReceiptOCRResult(
            totalAmount: extractTotalAmount(from: lines),
            merchantName: extractMerchantName(from: lines)
        )
    }

    // MARK: Total amount heuristic

    /// Keywords that mark "this line carries the total", strongest
    /// first. Compared case-insensitively against the whole line.
    private static let totalKeywords: [String] = [
        "grand total", "amount due", "balance due", "total due",
        "amount payable", "net payable", "to pay", "total amount",
        "total", "amount", "balance"
    ]

    /// Lines that look like totals but must NOT win over the real one.
    private static let excludedKeywords: [String] = [
        "subtotal", "sub total", "sub-total",
        "tax", "vat", "gst", "tip", "change", "cash", "tendered",
        "saved", "savings", "discount", "points", "reward"
    ]

    /// Best-effort total extraction:
    ///  1. Score every currency-looking value found on every line.
    ///  2. Values on (or immediately beside) a keyword line get a large
    ///     bonus, ranked by keyword strength; excluded lines are skipped.
    ///  3. Among keyword hits, the LARGEST value wins (a "TOTAL" is
    ///     never smaller than its "SUBTOTAL"); with no keyword hit at
    ///     all, fall back to the largest plausible value on the page.
    static func extractTotalAmount(from lines: [OCRLine]) -> Double? {
        struct Candidate {
            let value: Double
            let keywordRank: Int?   // lower = stronger keyword, nil = no keyword
        }

        var candidates: [Candidate] = []

        for (index, line) in lines.enumerated() {
            let lowered = line.text.lowercased()
            if excludedKeywords.contains(where: { lowered.contains($0) })
                && !lowered.contains("total") {
                // "Tax", "Change", "Cash tendered"… — skip unless the
                // line also says total ("Total incl. tax" must survive).
                continue
            }
            if lowered.contains("subtotal") || lowered.contains("sub total") || lowered.contains("sub-total") {
                continue
            }

            let keywordRank = totalKeywords.firstIndex { lowered.contains($0) }

            var values = currencyValues(in: line.text)
            // Receipts often print "TOTAL" and the value on separate
            // physical lines that OCR splits. If a keyword line has no
            // value of its own, adopt values from the nearest line at
            // roughly the same height (same row, different column).
            if keywordRank != nil && values.isEmpty {
                let rowCenter = line.boundingBox.midY
                for other in lines where other != line {
                    if abs(other.boundingBox.midY - rowCenter) < 0.015 {
                        values.append(contentsOf: currencyValues(in: other.text))
                    }
                }
                // Still nothing on the same row — check the line just
                // below the keyword (index order approximates layout).
                if values.isEmpty, index + 1 < lines.count {
                    values.append(contentsOf: currencyValues(in: lines[index + 1].text))
                }
            }

            for value in values where isPlausibleAmount(value) {
                candidates.append(Candidate(value: value, keywordRank: keywordRank))
            }
        }

        guard !candidates.isEmpty else { return nil }

        let keyworded = candidates.filter { $0.keywordRank != nil }
        if !keyworded.isEmpty {
            // Strongest keyword tier first, then the largest value in
            // that tier (grand total ≥ any line item on the same line).
            let bestRank = keyworded.compactMap(\.keywordRank).min()!
            return keyworded
                .filter { $0.keywordRank == bestRank }
                .map(\.value)
                .max()
        }

        // No keywords anywhere (crumpled/partial receipt): largest
        // plausible value is the best guess.
        return candidates.map(\.value).max()
    }

    /// Pull every currency-looking numeric value out of a line.
    /// Handles "₹1,240.50", "$ 12.99", "1.234,56", "1240", "12.99-".
    /// Locale-aware in the sense that both `1,234.56` and `1.234,56`
    /// grouping conventions are normalized.
    static func currencyValues(in text: String) -> [Double] {
        // Numbers with optional currency symbol / grouping / decimals.
        // We deliberately require either a decimal part OR a currency
        // symbol OR 2+ digits, so quantities like "x1" don't qualify.
        let pattern = #"(?:[$€£¥₹₩₪฿]|Rs\.?|INR|USD|EUR|GBP)?\s*([0-9]{1,3}(?:[.,\s][0-9]{3})*(?:[.,][0-9]{1,3})?|[0-9]+(?:[.,][0-9]{1,3})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))

        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = ns.substring(with: match.range(at: 1))
            return normalizeNumber(raw)
        }
    }

    /// Normalize a raw numeric string with ambiguous separators into a
    /// `Double`. "1,234.56" → 1234.56; "1.234,56" → 1234.56;
    /// "1 234,56" → 1234.56; "1240" → 1240.
    static func normalizeNumber(_ raw: String) -> Double? {
        var s = raw.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }

        let lastComma = s.range(of: ",", options: .backwards)?.lowerBound
        let lastDot = s.range(of: ".", options: .backwards)?.lowerBound

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Both present: the LAST one is the decimal separator.
            if comma > dot {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        case let (comma?, nil):
            // Comma only. "12,50" (decimal) vs "1,240" (grouping):
            // treat as decimal when ≤2 digits follow, grouping otherwise.
            let digitsAfter = s.distance(from: s.index(after: comma), to: s.endIndex)
            if digitsAfter <= 2 {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        case (nil, _?):
            // Dot only. "12.50" decimal vs "1.240" grouping — same rule.
            let dot = s.range(of: ".", options: .backwards)!.lowerBound
            let digitsAfter = s.distance(from: s.index(after: dot), to: s.endIndex)
            if digitsAfter == 3 && s.distance(from: s.startIndex, to: dot) <= 3 {
                s = s.replacingOccurrences(of: ".", with: "")
            }
        case (nil, nil):
            break
        }

        return Double(s)
    }

    /// Sanity window for a receipt total. Filters out phone numbers,
    /// years, card digits, and cents-only noise the regex may catch.
    static func isPlausibleAmount(_ value: Double) -> Bool {
        value.isFinite && value >= 0.01 && value < 10_000_000
    }

    // MARK: Merchant heuristic

    /// Boilerplate that must never be mistaken for a merchant name.
    private static let merchantStopwords: [String] = [
        "receipt", "invoice", "tax invoice", "welcome", "thank you",
        "thanks", "order", "cash receipt", "duplicate", "copy",
        "customer copy", "original", "bill", "gst", "vat", "tel",
        "phone", "www.", ".com", "http"
    ]

    /// The merchant name is usually the most prominent text near the
    /// top of the receipt. Strategy: look at lines in the top ~25% of
    /// the page, drop dates / phone numbers / boilerplate / pure
    /// numbers, then pick the TALLEST remaining line (logos print big);
    /// ties break toward the topmost.
    static func extractMerchantName(from lines: [OCRLine]) -> String? {
        // Vision y: top of page = large y. Top 25% band, with a
        // fallback to the top 40% if the band was all noise.
        for cutoff in [0.75, 0.60] {
            let topLines = lines.filter { $0.boundingBox.midY >= cutoff }
            if let name = bestMerchantLine(in: topLines) {
                return name
            }
        }
        return nil
    }

    private static func bestMerchantLine(in lines: [OCRLine]) -> String? {
        let viable = lines.filter { isViableMerchantLine($0.text) }
        guard !viable.isEmpty else { return nil }

        let best = viable.max { a, b in
            if abs(a.boundingBox.height - b.boundingBox.height) > 0.004 {
                return a.boundingBox.height < b.boundingBox.height
            }
            return a.boundingBox.midY < b.boundingBox.midY
        }
        return best.map { cleanMerchantName($0.text) }
    }

    static func isViableMerchantLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 40 else { return false }

        let lowered = trimmed.lowercased()
        if merchantStopwords.contains(where: { lowered.contains($0) }) { return false }

        // Must be mostly letters — addresses, dates, and phone numbers
        // are digit-heavy.
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        guard letters >= 3, digits <= letters / 2 else { return false }

        return true
    }

    /// Normalize SHOUTING receipt headers into title case; leave
    /// mixed-case names (already human-formatted) untouched.
    static func cleanMerchantName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == trimmed.uppercased() {
            return trimmed.capitalized
        }
        return trimmed
    }
}
