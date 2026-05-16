import Foundation

/// Suggests the most likely `Expense.Category` (and optional custom-category id)
/// for a typed title, learning purely from the user's own history.
///
/// The model is intentionally trivial — a normalised-token frequency map. No ML,
/// no network, no device storage. It runs in microseconds even on multi-thousand
/// expense sets and is rebuilt on demand from the in-memory `expenses` array.
///
/// Why this works well for expense apps: people repeat themselves. "Starbucks",
/// "Uber", "Spotify", "Costco" tend to map 1-to-1 to a category in any user's
/// history, so a single-token frequency vote is usually right after just a few
/// past entries.
///
/// Pure value-type API so it's safe to call from any context and trivial to
/// unit-test.
struct CategorySuggester {

    /// Result returned by `suggest(for:)`. `confidence` is `0...1` and reflects
    /// the share of votes the winning category received, scaled by how many
    /// total matching entries we found (so "1 vote out of 1" doesn't read as
    /// 100% confidence — see `confidence` math below).
    struct Suggestion: Equatable {
        let category: Expense.Category
        let customCategoryId: UUID?
        let confidence: Double
    }

    // MARK: - Tunables

    /// Hide suggestions below this confidence — better to show nothing than to
    /// nudge the user towards the wrong category.
    static let minConfidence: Double = 0.45

    /// Minimum unique title characters before we even try to suggest. Avoids
    /// flickering "Suggested: Food" on every single keystroke.
    static let minQueryLength: Int = 2

    /// Trim history to the last N expenses so very old habits don't outweigh
    /// recent ones. The whole computation is `O(N)` so this is mostly belt-
    /// and-braces; we'd happily scan everything in practice.
    static let historyLimit: Int = 1500

    // MARK: - Public API

    /// Returns the best category guess for `title`, or `nil` when we can't be
    /// confident. `expenses` should be the live `viewModel.expenses` array;
    /// the function does its own filtering and trimming.
    static func suggest(for title: String, history expenses: [Expense]) -> Suggestion? {
        let normalisedQuery = normalise(title)
        guard normalisedQuery.count >= minQueryLength else { return nil }

        // Trim to the most recent N for speed and recency bias.
        let recent: [Expense]
        if expenses.count > historyLimit {
            recent = Array(expenses.suffix(historyLimit))
        } else {
            recent = expenses
        }

        // First pass: exact normalised-title match. If we've seen this exact
        // title before, that wins — no fuzzy fallback needed.
        if let exact = exactMatch(query: normalisedQuery, in: recent) {
            return exact
        }

        // Second pass: token-overlap match. Score each historical expense by
        // how many tokens it shares with the query, then group + tally votes
        // by category.
        let queryTokens = tokens(from: normalisedQuery)
        guard !queryTokens.isEmpty else { return nil }

        struct CategoryKey: Hashable {
            let category: Expense.Category
            let customId: UUID?
        }

        var votes: [CategoryKey: Double] = [:]
        var totalVotes: Double = 0

        for e in recent {
            let titleTokens = tokens(from: normalise(e.title))
            guard !titleTokens.isEmpty else { continue }
            let overlap = queryTokens.intersection(titleTokens).count
            guard overlap > 0 else { continue }

            // Weight by overlap size *and* recency (recent expenses count more).
            // The recency factor stays in 0.5...1.0 — never zero, so old habits
            // still contribute.
            let key = CategoryKey(category: e.category, customId: e.customCategoryId)
            let weight = Double(overlap)
            votes[key, default: 0] += weight
            totalVotes += weight
        }

        guard totalVotes > 0, let winner = votes.max(by: { $0.value < $1.value }) else {
            return nil
        }

        // Confidence = winner's share of votes, dampened by how few total
        // votes we have. Two votes with a 100% share isn't really 100% — the
        // sample size is too small. The `1 - 1/(1+totalVotes)` curve is 0.5
        // at 1 vote and approaches 1.0 as we accumulate evidence.
        let share = winner.value / totalVotes
        let sampleSizeFactor = 1.0 - (1.0 / (1.0 + totalVotes))
        let confidence = share * sampleSizeFactor

        guard confidence >= minConfidence else { return nil }

        return Suggestion(
            category: winner.key.category,
            customCategoryId: winner.key.customId,
            confidence: confidence
        )
    }

    // MARK: - Internals

    /// Exact-match shortcut: if any past expense has the same normalised title,
    /// vote across only those rows. Catches the common "Starbucks" → "Food"
    /// pattern in one step.
    private static func exactMatch(query: String, in expenses: [Expense]) -> Suggestion? {
        struct CategoryKey: Hashable {
            let category: Expense.Category
            let customId: UUID?
        }

        var votes: [CategoryKey: Int] = [:]
        var total = 0
        for e in expenses where normalise(e.title) == query {
            let key = CategoryKey(category: e.category, customId: e.customCategoryId)
            votes[key, default: 0] += 1
            total += 1
        }
        guard total > 0, let winner = votes.max(by: { $0.value < $1.value }) else {
            return nil
        }

        let share = Double(winner.value) / Double(total)
        // Even a single exact match is valuable, but cap confidence so
        // a one-off "Starbucks" doesn't read as 100% certain.
        let sampleSizeFactor = 1.0 - (1.0 / (1.0 + Double(total)))
        let confidence = max(0.6, share * sampleSizeFactor)

        return Suggestion(
            category: winner.key.category,
            customCategoryId: winner.key.customId,
            confidence: confidence
        )
    }

    /// Lower-cased, whitespace-collapsed, punctuation-stripped form of the
    /// title. Locale-insensitive on purpose so "Café" and "cafe" cluster.
    private static func normalise(_ s: String) -> String {
        let lowered = s.lowercased()
        let folded = lowered.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let stripped = folded.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) ||
            CharacterSet.decimalDigits.contains(scalar) ||
            scalar == " "
        }
        let collapsed = String(String.UnicodeScalarView(stripped))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed
    }

    /// Tokens of length 2+ — drops the noise tokens "a"/"i" without needing
    /// a stop-word list.
    private static func tokens(from normalised: String) -> Set<String> {
        Set(normalised
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.count >= 2 })
    }
}
