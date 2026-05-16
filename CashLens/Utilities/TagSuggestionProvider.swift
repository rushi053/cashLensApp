import Foundation

/// Computes tag autocomplete + popularity data off the main actor.
///
/// The provider runs cheaply across all expenses since tag arrays are tiny.
/// For very large databases we rely on `ExpenseViewModel`'s debounced refresh;
/// this work is O(n × t) where `t` is average tags-per-expense (typically 0-2).
enum TagSuggestionProvider {

    struct Stats: Equatable {
        /// Distinct tag → total usage count across all expenses.
        let usageCounts: [String: Int]
        /// Most-recently-used-first, deduped.
        let recentTags: [String]
        /// Sorted descending by usage count.
        let popularTags: [String]

        static let empty = Stats(usageCounts: [:], recentTags: [], popularTags: [])

        var totalDistinctTags: Int { usageCounts.count }
    }

    /// Aggregate usage/recency across all expenses.
    ///
    /// - Parameter expenses: snapshot of expenses; safe to pass from any actor
    ///   since it's a value type.
    /// - Parameter recentCap: how many recent tags to keep in the "recent" list.
    static func computeStats(from expenses: [Expense], recentCap: Int = 12) -> Stats {
        var counts: [String: Int] = [:]
        var recentOrder: [String] = []
        var seenInRecent: Set<String> = []

        let sortedByDate = expenses.sorted { $0.date > $1.date }

        for expense in sortedByDate {
            guard let tags = expense.tags, !tags.isEmpty else { continue }
            for tag in tags {
                counts[tag, default: 0] += 1
                if !seenInRecent.contains(tag), recentOrder.count < recentCap {
                    recentOrder.append(tag)
                    seenInRecent.insert(tag)
                }
            }
        }

        let popular = counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { $0.key }

        return Stats(
            usageCounts: counts,
            recentTags: recentOrder,
            popularTags: popular
        )
    }

    /// Suggest autocompletions for the current partial input.
    ///
    /// Prefix matches rank above substring matches; ties break by usage count.
    /// Already-selected tags are excluded from the results.
    static func suggestions(
        for partial: String,
        allTags: [String: Int],
        excluding: Set<String>,
        limit: Int = 6
    ) -> [String] {
        let query = Tag.normalize(partial) ?? ""
        guard !query.isEmpty else { return [] }

        struct Scored {
            let tag: String
            let isPrefix: Bool
            let count: Int
        }

        let matches: [Scored] = allTags.compactMap { tag, count in
            guard !excluding.contains(tag) else { return nil }
            if tag.hasPrefix(query) {
                return Scored(tag: tag, isPrefix: true, count: count)
            }
            if tag.contains(query) {
                return Scored(tag: tag, isPrefix: false, count: count)
            }
            return nil
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.isPrefix != rhs.isPrefix { return lhs.isPrefix && !rhs.isPrefix }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.tag < rhs.tag
        }

        return Array(sorted.prefix(limit)).map { $0.tag }
    }
}
