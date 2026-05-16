import Foundation
import SwiftUI

/// Per-expense payment instrument — Cash, Credit, Debit, UPI, etc.
///
/// Captured on the entry form so users can later see, in the **Payment Methods**
/// donut on Statistics, how their cash-vs-credit-vs-UPI mix actually breaks
/// down. The donut/breakdown is a Pro feature; setting the value on an
/// expense is free, exactly like tags. That keeps the data clean for the
/// moment a user upgrades and starts caring about the analytics.
///
/// ## Storage model
///
/// `Expense.paymentMethod` is `PaymentMethod?`:
/// - `nil`  → user didn't pick one (legacy rows, default).
/// - `.cash`/`.credit`/… → an explicit choice from this enum.
///
/// We deliberately keep this as a flat enum (no custom strings) for v1.
/// "Custom" payment methods can be added later as a sibling Core Data
/// entity if real demand shows up — keeping the v1 schema small means
/// zero risk to existing backups, no migration headaches, and a clean
/// pivot point if we go custom later.
enum PaymentMethod: String, CaseIterable, Codable, Identifiable, Hashable {
    case cash
    case creditCard      = "credit"
    case debitCard       = "debit"
    case upi
    case bankTransfer    = "bank"
    case wallet
    case other

    var id: String { rawValue }

    /// Short, readable label used in pickers and breakdown rows.
    var displayName: String {
        switch self {
        case .cash:         return "Cash"
        case .creditCard:   return "Credit Card"
        case .debitCard:    return "Debit Card"
        case .upi:          return "UPI"
        case .bankTransfer: return "Bank Transfer"
        case .wallet:       return "Wallet"
        case .other:        return "Other"
        }
    }

    /// Compact label used inside small pills (e.g. on the expense card).
    var shortLabel: String {
        switch self {
        case .cash:         return "Cash"
        case .creditCard:   return "Credit"
        case .debitCard:    return "Debit"
        case .upi:          return "UPI"
        case .bankTransfer: return "Bank"
        case .wallet:       return "Wallet"
        case .other:        return "Other"
        }
    }

    /// SF Symbol drawn alongside the label. Picked to be recognisable at
    /// 12pt without colour, so monochrome contexts (badge on a card) still
    /// read at a glance.
    var icon: String {
        switch self {
        case .cash:         return "banknote"
        case .creditCard:   return "creditcard.fill"
        case .debitCard:    return "creditcard"
        case .upi:          return "qrcode"
        case .bankTransfer: return "building.columns"
        case .wallet:       return "wallet.pass.fill"
        case .other:        return "ellipsis.circle"
        }
    }

    /// Brand colour for donut slices and accent treatments. Chosen for
    /// strong contrast against each other — credit (orange) vs debit (blue)
    /// vs cash (green) is intentionally legible even with the donut at 150pt.
    var color: Color {
        switch self {
        case .cash:         return Color.green
        case .creditCard:   return Color.orange
        case .debitCard:    return Color.blue
        case .upi:          return Color.purple
        case .bankTransfer: return Color.teal
        case .wallet:       return Color.pink
        case .other:        return Color.gray
        }
    }

    // MARK: - Backward-compatible decoding

    /// Decode from a raw string with a tolerant fallback. We accept the
    /// modern raw values (`"credit"`, `"debit"`, …) plus a handful of
    /// historic spellings just in case anyone hand-edits a JSON backup.
    /// Unknown values decode as `.other` rather than throwing — losing the
    /// payment method shouldn't fail an entire import.
    static func tolerant(from raw: String?) -> PaymentMethod? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let direct = PaymentMethod(rawValue: raw.lowercased()) {
            return direct
        }
        switch raw.lowercased() {
        case "creditcard", "credit_card", "credit card":      return .creditCard
        case "debitcard", "debit_card", "debit card":         return .debitCard
        case "banktransfer", "bank_transfer", "bank transfer", "transfer", "ach":
            return .bankTransfer
        case "wallet", "applepay", "apple pay", "googlepay", "google pay", "paypal", "venmo":
            return .wallet
        case "qr", "upi/qr":
            return .upi
        default:
            return .other
        }
    }
}
