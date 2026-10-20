//
//  MoneyFormat.swift
//  CashLens + CashLensWidgets (shared)
//
//  One rounding and digit-grouping rule for every amount the app and
//  widgets print.
//
//  - Grouping follows the selected currency, not the device region:
//    a phone set to region India showing USD must read "$114,594.13",
//    not "$1,14,594.13". Lakh/crore grouping is kept only for the
//    currencies whose home convention uses it. Decimal and grouping
//    separator characters still come from the device locale.
//  - Rounding is half away from zero to the currency's minor units,
//    after snapping binary noise, so the same total summed in a
//    different order (Today vs Insights) can never print a cent apart.
//

import Foundation

enum MoneyFormat {

    /// Currencies whose home locale groups as 1,00,000 (lakh/crore).
    static let lakhGroupingCurrencyCodes: Set<String> = ["INR", "NPR", "PKR", "BDT"]

    static func usesLakhGrouping(currencyCode: String) -> Bool {
        lakhGroupingCurrencyCodes.contains(currencyCode.uppercased())
    }

    /// `amount` rounded half away from zero to `fractionDigits`. Values
    /// within a millionth of a minor unit of the half are treated as the
    /// half, so 0.125 stored as 0.12499999… still rounds to 0.13.
    static func rounded(_ amount: Double, fractionDigits: Int) -> Double {
        guard amount.isFinite else { return 0 }
        let scale = pow(10, Double(max(0, fractionDigits)))
        let scaled = amount * scale
        let snapped = (scaled * 1_000_000).rounded() / 1_000_000
        let result = snapped.rounded(.toNearestOrAwayFromZero) / scale
        // Negative zero would print as "-$0.00".
        return result == 0 ? 0 : result
    }

    /// Applies the currency's grouping and the shared rounding mode to a
    /// formatter. Call once when configuring; never on a shared instance
    /// at format time.
    static func configure(_ formatter: NumberFormatter, currencyCode: String) {
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = usesLakhGrouping(currencyCode: currencyCode) ? 2 : 3
        formatter.roundingMode = .halfUp
    }

    /// Grouped magnitude without a symbol ("1,234.50"). Thread-safe.
    static func decimalString(_ amount: Double, fractionDigits: Int, currencyCode: String) -> String {
        let formatter = DecimalFormatterCache.formatter(
            fractionDigits: fractionDigits,
            lakh: usesLakhGrouping(currencyCode: currencyCode)
        )
        let value = rounded(amount, fractionDigits: fractionDigits)
        return formatter.string(from: NSNumber(value: value))
            ?? (fractionDigits == 0 ? "0" : "0." + String(repeating: "0", count: fractionDigits))
    }
}

/// Lock-guarded cache of immutable decimal formatters. Each one is fully
/// configured before it is published and only read afterwards, which
/// NSNumberFormatter documents as thread-safe.
private enum DecimalFormatterCache {
    private struct Key: Hashable {
        let fractionDigits: Int
        let lakh: Bool
    }

    private static let lock = NSLock()
    private static var formatters: [Key: NumberFormatter] = [:]

    static func formatter(fractionDigits: Int, lakh: Bool) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(fractionDigits: fractionDigits, lakh: lakh)
        if let cached = formatters[key] {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        MoneyFormat.configure(formatter, currencyCode: lakh ? "INR" : "USD")
        formatters[key] = formatter
        return formatter
    }
}
