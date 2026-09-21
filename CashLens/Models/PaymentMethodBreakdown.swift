import Foundation

/// One row in the Statistics "Payment Methods" donut/breakdown. We keep this
/// shape parallel to `CategoryExpenseData` so the donut rendering code can
/// stay nearly identical. `amount` is refund-adjusted (net) and `percentage`
/// is computed only over positive-net buckets so a single big refund cannot
/// push share above 100% or below zero.
struct PaymentMethodSlice: Identifiable, Hashable {
    let method: PaymentMethod
    let amount: Double
    let percentage: Double
    let count: Int

    var id: PaymentMethod { method }
}

/// Aggregated result for the Pro "Payment Methods" donut. We track the
/// "unspecified" bucket separately rather than rendering it as a wedge —
/// the donut should answer "of the spend you've tagged, what's the split?",
/// while the unspecified count nudges the user to start tagging.
struct PaymentMethodBreakdown {
    let slices: [PaymentMethodSlice]
    let unspecifiedAmount: Double
    let unspecifiedCount: Int
    /// Sum of all positive-net buckets *including* unspecified. Used as the
    /// percentage denominator so the slices sum to 100% of tagged-or-untagged
    /// positive spend.
    let total: Double

    var hasData: Bool { !slices.isEmpty }

    /// Coverage of payment-method tagging in the period: 1.0 means every
    /// expense had a method set, 0.0 means none did. Drives the "tag x more
    /// expenses for a complete picture" hint without doing math in the view.
    var taggedCoverage: Double {
        guard total > 0 else { return 1.0 }
        let tagged = total - unspecifiedAmount
        return min(max(tagged / total, 0), 1)
    }
}
