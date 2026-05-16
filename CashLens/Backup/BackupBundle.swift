import Foundation
import UIKit

/// `BackupBundle` is the **canonical, self-describing payload** for a CashLens
/// backup. A single JSON file containing one of these is sufficient to fully
/// restore an app install: every Core Data entity, every user preference, every
/// notification schedule.
///
/// ## Versioning
///
/// `schema.version` is semver-style. Readers compare against
/// `BackupBundle.currentSchemaVersion` and `minimumReaderVersion` to decide
/// whether the file can be safely consumed.
///
/// - Bumping `version` minor: additive fields only, older readers can still parse.
/// - Bumping `version` major: breaking schema, writers must update
///   `minimumReaderVersion` so older builds refuse the file gracefully.
///
/// ## Wire format (JSON)
///
/// ```json
/// {
///   "schema": {
///     "version": "2.0",
///     "minimumReaderVersion": "2.0",
///     "exportedAt": "2026-04-25T11:30:00Z",
///     "appVersion": "1.4 (231)",
///     "device": "iPhone16,2"
///   },
///   "data": {
///     "expenses":             [ ... Expense ],
///     "subscriptions":        [ ... Subscription ],
///     "customCategories":     [ ... CustomCategory ],
///     "budgets":              [ ... CodableBudget ],
///     "deletedDefaultCategories": [ "Health", ... ]
///   },
///   "preferences": {
///     "userName": "...",
///     "selectedCurrency": "USD",
///     "defaultHomeTimeFrame": "Month",
///     "appearanceMode": "system",
///     "preferredSummaryCategories": [ "Food", "custom:UUID", ... ],
///     "notifications": {
///       "weeklySummary":  { "enabled": true, "weekday": 2, "hour": 9, "minute": 0 },
///       "monthlyDigest":  { "enabled": true, "dayOfMonth": 1, "hour": 9, "minute": 0 },
///       "backupReminder": { "enabled": true, "dayOfMonth": 1, "hour": 9, "minute": 0 }
///     }
///   }
/// }
/// ```
///
/// Backup metadata such as `lastBackupDate` and `totalBackupCount` is
/// **intentionally not** in the bundle — it would be misleading to restore.
struct BackupBundle: Codable {

    static let currentSchemaVersion = "2.0"
    static let minimumReaderVersion = "2.0"

    var schema: Schema
    var data: Payload
    var preferences: Preferences

    // MARK: - Schema

    struct Schema: Codable {
        var version: String
        var minimumReaderVersion: String
        var exportedAt: Date
        var appVersion: String?
        var device: String?

        static func current() -> Schema {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? ""
            let build = info?["CFBundleVersion"] as? String ?? ""
            let appVersion = "\(version) (\(build))"
            return Schema(
                version: BackupBundle.currentSchemaVersion,
                minimumReaderVersion: BackupBundle.minimumReaderVersion,
                exportedAt: Date(),
                appVersion: appVersion.trimmingCharacters(in: .whitespaces).isEmpty ? nil : appVersion,
                device: UIDevice.current.model
            )
        }
    }

    // MARK: - Data Payload

    /// Everything that lives in Core Data plus the deleted-default-categories list.
    struct Payload: Codable {
        var expenses: [Expense]
        var subscriptions: [Subscription]
        var customCategories: [CustomCategory]
        var budgets: [CodableBudget]
        var deletedDefaultCategories: [String]

        static let empty = Payload(
            expenses: [],
            subscriptions: [],
            customCategories: [],
            budgets: [],
            deletedDefaultCategories: []
        )

        var isEmpty: Bool {
            expenses.isEmpty
                && subscriptions.isEmpty
                && customCategories.isEmpty
                && budgets.isEmpty
                && deletedDefaultCategories.isEmpty
        }
    }

    // MARK: - Preferences

    /// All user-visible preferences that survive a fresh install.
    /// Every field is optional so omission means "do not change current value".
    struct Preferences: Codable {
        var userName: String?
        var selectedCurrency: String?
        var defaultHomeTimeFrame: String?
        var appearanceMode: String?
        var preferredSummaryCategories: [String]?
        var notifications: NotificationPreferences?

        static let empty = Preferences()

        var hasAny: Bool {
            userName != nil
                || selectedCurrency != nil
                || defaultHomeTimeFrame != nil
                || appearanceMode != nil
                || preferredSummaryCategories != nil
                || notifications != nil
        }
    }

    struct NotificationPreferences: Codable {
        var weeklySummary: WeeklySchedule?
        var monthlyDigest: MonthlySchedule?
        var backupReminder: MonthlySchedule?
    }

    struct WeeklySchedule: Codable {
        var enabled: Bool
        var weekday: Int
        var hour: Int
        var minute: Int
    }

    struct MonthlySchedule: Codable {
        var enabled: Bool
        var dayOfMonth: Int
        var hour: Int
        var minute: Int
    }
}

// MARK: - CodableBudget

/// `Budget` uses an enum with associated values for `categoryFilter`. Swift's
/// auto-Codable for that produces noisy JSON like `{"customCategory": {"_0": "..."}}`.
/// `CodableBudget` is a thin DTO that mirrors how `BudgetEntity` actually stores
/// the filter (`type` + optional discriminator), giving us:
///
/// 1. A clean, human-readable JSON layout.
/// 2. A schema that matches Core Data 1:1, simplifying migration.
struct CodableBudget: Codable {
    var id: UUID
    var name: String
    var amount: Double
    var period: String
    var categoryFilter: FilterDTO
    var alertAtPercentages: [Double]
    var isActive: Bool
    var createdAt: Date

    struct FilterDTO: Codable {
        /// `"overall"`, `"default"`, or `"custom"`.
        var type: String
        /// For `"default"`: the `Expense.Category.rawValue`.
        var rawValue: String?
        /// For `"custom"`: the custom category UUID string.
        var id: String?
    }

    init(_ budget: Budget) {
        self.id = budget.id
        self.name = budget.name
        self.amount = budget.amount
        self.period = budget.period.rawValue
        self.alertAtPercentages = budget.alertAtPercentages
        self.isActive = budget.isActive
        self.createdAt = budget.createdAt

        switch budget.categoryFilter {
        case .overall:
            self.categoryFilter = FilterDTO(type: "overall", rawValue: nil, id: nil)
        case .defaultCategory(let raw):
            self.categoryFilter = FilterDTO(type: "default", rawValue: raw, id: nil)
        case .customCategory(let uuid):
            self.categoryFilter = FilterDTO(type: "custom", rawValue: nil, id: uuid.uuidString)
        }
    }

    /// Convert back to the in-app `Budget` value type. Returns `nil` if the
    /// data is malformed beyond reasonable repair.
    func toBudget() -> Budget? {
        guard amount.isFinite, amount >= 0 else { return nil }
        guard let period = Budget.Period(rawValue: period) else { return nil }

        let filter: Budget.CategoryFilter
        switch categoryFilter.type {
        case "default":
            filter = .defaultCategory(categoryFilter.rawValue ?? Expense.Category.other.rawValue)
        case "custom":
            if let s = categoryFilter.id, let uuid = UUID(uuidString: s) {
                filter = .customCategory(uuid)
            } else {
                return nil
            }
        default:
            filter = .overall
        }

        let percentages = alertAtPercentages.isEmpty ? Budget.defaultAlertPercentages : alertAtPercentages
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Budget(
            id: id,
            name: cleanName.isEmpty ? "Budget" : cleanName,
            amount: amount,
            period: period,
            categoryFilter: filter,
            alertAtPercentages: percentages,
            isActive: isActive,
            createdAt: createdAt
        )
    }
}
