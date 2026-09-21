//
//  GetSpendingIntent.swift
//  CashLens (main app target)
//
//  "How much did I spend today?" — answers with today's and this
//  month's net spend via a direct Core Data fetch (no scene, no view
//  models). Free feature.
//
import AppIntents

struct GetSpendingIntent: AppIntent {

    static var title: LocalizedStringResource = "Check Spending"
    static var description = IntentDescription(
        "Hear today's and this month's spending from CashLens.",
        categoryName: "Insights"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !PersistenceController.shared.storeLoadFailed else {
            throw QuickLogService.QuickLogError.storeUnavailable
        }

        let summary = QuickLogService.spendingSummary()
        let currency = QuickLogService.selectedCurrency()
        let todayText = QuickLogService.formatAmount(summary.today, currency: currency)
        let monthText = QuickLogService.formatAmount(summary.month, currency: currency)

        return .result(
            dialog: IntentDialog("\(todayText) today · \(monthText) this month")
        )
    }
}
