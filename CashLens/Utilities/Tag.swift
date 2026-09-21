import Foundation

/// Pure helpers for tag normalization and presentation.
///
/// Tags are stored **without** the leading `#` so search/equality works cleanly,
/// and are rendered **with** `#` via `displayForm(_:)` everywhere user-facing.
enum Tag {

    /// Max characters per tag after normalization. Keeps UI readable and prevents pathological input.
    static let maxLength: Int = 30

    /// Max number of tags that can live on a single expense.
    static let maxPerExpense: Int = 10

    /// Free-tier tag limit per expense. Additional tags trigger the Pro teaser.
    ///
    /// We allow **adding** tags generously on the free tier so the feature
    /// stays addictive; Pro's real payoff is filtering and analysis.
    static let freeTagsPerExpense: Int = Int.max

    /// Normalize a raw user-entered string into the canonical storage form.
    ///
    /// - Trims whitespace
    /// - Strips a leading `#` if present
    /// - Collapses internal whitespace into `-`
    /// - Lowercases for canonical storage/matching
    /// - Discards empty results and anything over `maxLength`
    ///
    /// Returns `nil` for empty / invalid input so callers can drop it cleanly.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Collapse runs of whitespace into a single dash so "work lunch" → "work-lunch".
        let collapsed = s
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let lowered = collapsed.lowercased()

        guard !lowered.isEmpty, lowered.count <= maxLength else { return nil }
        return lowered
    }

    /// User-facing rendering of a stored tag — always prefixed with `#`.
    static func displayForm(_ stored: String) -> String {
        "#\(stored)"
    }

    /// Merge `incoming` into `existing`, dedupe case-insensitively, preserving order.
    static func merged(existing: [String], incoming: String) -> [String] {
        guard let normalized = normalize(incoming) else { return existing }
        if existing.contains(normalized) { return existing }
        return existing + [normalized]
    }

    /// Non-destructive removal helper.
    static func removing(_ tag: String, from list: [String]) -> [String] {
        list.filter { $0 != tag }
    }
}
