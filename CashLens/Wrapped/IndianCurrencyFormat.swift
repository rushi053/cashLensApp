import Foundation

/// Indian digit grouping for rupee amounts: the last three digits, then groups of two.
/// `1234567.5` → `₹12,34,567.50`.
///
/// Grouping is done on the rounded digit string so it does not depend on the phone locale.
enum IndianCurrencyFormat {
    /// `includePaise` keeps two decimal places. Otherwise the amount is rounded to the rupee.
    static func formatINR(_ amount: Double, includePaise: Bool = true) -> String {
        format(amount, symbol: "₹", fractionDigits: includePaise ? 2 : 0)
    }

    static func format(_ amount: Double, symbol: String, fractionDigits: Int) -> String {
        guard amount.isFinite else { return symbol + "0" }

        let digits = max(0, min(fractionDigits, 2))
        let absolute = abs(amount)

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.roundingMode = .halfUp
        formatter.positivePrefix = ""
        formatter.negativePrefix = ""

        guard let raw = formatter.string(from: NSNumber(value: absolute)) else {
            return symbol + "0"
        }

        let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
        let grouped = groupIndianDigits(String(pieces.first ?? "0"))
        let fraction = pieces.count > 1 ? String(pieces[1]) : ""

        let body: String
        if digits > 0, !fraction.isEmpty {
            body = grouped + "." + fraction
        } else {
            body = grouped
        }

        let isZero = isZeroAmount(grouped: grouped, fraction: fraction)
        let sign = (amount < 0 && !isZero) ? "-" : ""
        return sign + symbol + body
    }

    /// Last 3 digits, then groups of 2. Non-digits are ignored.
    static func groupIndianDigits(_ integerDigits: String) -> String {
        let digits = integerDigits.filter(\.isNumber)
        let source = digits.isEmpty ? "0" : String(digits)
        guard source.count > 3 else { return source }

        let lastThree = source.suffix(3)
        var rest = source.dropLast(3)
        var groups: [String] = []
        while rest.count > 2 {
            groups.insert(String(rest.suffix(2)), at: 0)
            rest = rest.dropLast(2)
        }
        if !rest.isEmpty {
            groups.insert(String(rest), at: 0)
        }
        return groups.joined(separator: ",") + "," + String(lastThree)
    }

    private static func isZeroAmount(grouped: String, fraction: String) -> Bool {
        let wholeIsZero = grouped.allSatisfy { $0 == "0" || $0 == "," }
        let fractionIsZero = fraction.isEmpty || fraction.allSatisfy { $0 == "0" }
        return wholeIsZero && fractionIsZero
    }
}

/// Story amounts. INR uses Indian grouping; other currencies keep Western grouping
/// so a dollar total is not written as `$1,23,456`.
enum WrappedMoney {
    static func format(amount: Double, currency: Expense.Currency) -> String {
        guard amount.isFinite else {
            return currency == .inr ? "₹0" : "\(currency.symbol)0"
        }
        if currency == .inr {
            let withPaise = IndianCurrencyFormat.formatINR(amount, includePaise: true)
            if withPaise.hasSuffix(".00") {
                return String(withPaise.dropLast(3))
            }
            return withPaise
        }
        return western(amount, symbol: currency.symbol)
    }

    private static func western(amount: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        let number = formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
        let isZero = number == "0" || number == "0.0" || number == "0.00"
        let sign = (amount < 0 && !isZero) ? "-" : ""
        return sign + symbol + number
    }
}
