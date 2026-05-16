import Foundation

/// Tiny `UserDefaults`-backed cache of the user's most recently picked
/// currencies, used to surface a "Recently Used" shortcut at the top of
/// `CurrencyPickerView`. Capped to a small number so we never grow the
/// list unboundedly and so the picker stays glanceable.
///
/// We deliberately track this on **active** picks (the user tapping a row
/// in the picker), not on every assignment to `selectedCurrency` — silent
/// reassignments from `autoSelectCurrencyIfNeeded()` or backup restore
/// shouldn't pollute the recents list.
enum RecentCurrenciesStore {
    /// How many recents we keep. Three is enough to show genuine signal
    /// (current + last two) without crowding the picker header.
    static let cap = 3

    /// Returns the most-recent-first list of recently picked currencies,
    /// silently dropping any codes that no longer map to a known
    /// `Expense.Currency` case (e.g. after a currency removal).
    static func load() -> [Expense.Currency] {
        let codes = (UserDefaults.standard.array(forKey: UserDefaultsKeys.recentCurrencies) as? [String]) ?? []
        return codes.compactMap { Expense.Currency(rawValue: $0) }
    }

    /// Records a fresh user pick. Idempotent: re-picking the same currency
    /// just bumps it to the front instead of duplicating.
    static func record(_ currency: Expense.Currency) {
        var codes = (UserDefaults.standard.array(forKey: UserDefaultsKeys.recentCurrencies) as? [String]) ?? []
        codes.removeAll { $0 == currency.rawValue }
        codes.insert(currency.rawValue, at: 0)
        if codes.count > cap { codes = Array(codes.prefix(cap)) }
        UserDefaults.standard.set(codes, forKey: UserDefaultsKeys.recentCurrencies)
    }
}
