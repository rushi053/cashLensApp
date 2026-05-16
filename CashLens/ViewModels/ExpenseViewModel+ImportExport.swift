import Foundation
import CoreData

/// Thin compatibility surface kept on `ExpenseViewModel` so existing call
/// sites (and a few diagnostics views) keep working. All real work now lives
/// in `BackupExporter` / `BackupImporter` under `CashLens/Backup/`.
///
/// Prefer the new `BackupExporter.write(_:as:)` and
/// `BackupImporter.preview(url:fallbackCurrency:)` APIs in new code.
extension ExpenseViewModel {

    // MARK: - Export (delegates to BackupExporter)

    /// Write a v2 backup as a flat, RFC 4180-compliant CSV (expenses only).
    /// Use `exportToJSON()` for a full backup including subscriptions,
    /// custom categories, budgets, and preferences.
    func exportToCSV() -> URL? {
        let bundle = BackupExporter.buildBundle()
        return BackupExporter.write(bundle, as: .csv)
    }

    /// Write a v2 backup as a complete JSON file. This is the format that can
    /// fully restore the app state on a fresh install.
    func exportToJSON() -> URL? {
        let bundle = BackupExporter.buildBundle()
        return BackupExporter.write(bundle, as: .json)
    }

    /// Thread-safe helper kept for callers that need a quick subscription
    /// snapshot without touching the importer/exporter pipeline.
    func loadSubscriptionsForExport() -> [Subscription] {
        var result: [Subscription] = []
        viewContext.performAndWait {
            let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \SubscriptionEntity.isActive, ascending: false),
                NSSortDescriptor(keyPath: \SubscriptionEntity.nextDueDate, ascending: true)
            ]
            do {
                result = try viewContext.fetch(request).toSubscriptions()
            } catch {
                print("ExpenseViewModel: subscription fetch for export failed — \(error.localizedDescription)")
                result = []
            }
        }
        return result
    }
}
