//
//  WidgetMoneyFormatter.swift
//  CashLensWidgets
//
//  Compact, currency-aware number formatting for tight widget surfaces.
//
//  Strategy:
//
//  - Sub-1k values render with two decimals so $4.50 ≠ $5 visually.
//  - 1k–999k values shift to compact form ("$1.2K") on Small widgets
//    where every character counts; Medium/Large can still afford full
//    grouped numerics.
//  - 1M+ always compact.
//
//  We resolve currency symbols from `Locale` so the widget respects
//  the user's chosen app currency without relying on a `Currency`
//  Codable type the widget process doesn't have access to.
//

import Foundation

enum WidgetMoneyFormatter {

    /// Cached symbol per currency code — the lookup is cheap but called
    /// once per widget render so why pay it twice.
    private static var symbolCache: [String: String] = [:]

    static func symbol(for currencyCode: String) -> String {
        if let cached = symbolCache[currencyCode] { return cached }
        let resolved = Locale.current.localizedString(forCurrencyCode: currencyCode)
            ?? currencyCode
        // Build a quick tiny formatter to get the actual symbol char.
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        let sym = f.currencySymbol ?? resolved
        symbolCache[currencyCode] = sym
        return sym
    }

    /// Full grouped "$1,234.56" style. Used by Medium / Large surfaces.
    static func full(_ amount: Double, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount.isFinite ? amount : 0)) ?? "\(symbol(for: currencyCode))0.00"
    }

    /// Compact "$1.2K" / "$3.4M" style. Used by Small surfaces and
    /// Lock Screen accessories where horizontal real estate is brutal.
    static func compact(_ amount: Double, currencyCode: String) -> String {
        let s = symbol(for: currencyCode)
        let v = abs(amount.isFinite ? amount : 0)
        let sign = amount < 0 ? "-" : ""
        switch v {
        case 0..<1_000:
            return "\(sign)\(s)\(decimal(v, fraction: v < 10 ? 2 : 0))"
        case 1_000..<10_000:
            return "\(sign)\(s)\(decimal(v / 1_000, fraction: 1))K"
        case 10_000..<1_000_000:
            return "\(sign)\(s)\(decimal(v / 1_000, fraction: 0))K"
        case 1_000_000..<10_000_000:
            return "\(sign)\(s)\(decimal(v / 1_000_000, fraction: 1))M"
        default:
            return "\(sign)\(s)\(decimal(v / 1_000_000, fraction: 0))M"
        }
    }

    private static func decimal(_ v: Double, fraction: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    /// Percentage delta string for "vs last period" chips. Returns
    /// e.g. "+12%" / "−3%" / "—" when previous == 0.
    static func percentDelta(current: Double, previous: Double) -> String {
        guard previous > 0.0001 else { return "—" }
        let delta = (current - previous) / previous * 100
        let rounded = Int(delta.rounded())
        if rounded > 0 { return "+\(rounded)%" }
        if rounded < 0 { return "\(rounded)%" }
        return "0%"
    }
}
