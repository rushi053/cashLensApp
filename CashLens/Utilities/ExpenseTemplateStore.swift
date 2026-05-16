import Foundation
import Combine

/// Persistent store for `ExpenseTemplate` records, backed by `UserDefaults`.
///
/// Why `UserDefaults` and not Core Data:
/// - Templates are tiny (≤ a few KB total even at the cap) and read on every
///   open of `AddExpenseView`, so the lower-overhead path wins.
/// - Skipping a Core Data migration keeps Phase 10 strictly additive —
///   nothing about `ExpenseEntity`, `BudgetEntity`, or
///   `CustomCategoryEntity` changes.
/// - Backups: templates are intentionally **not** included in JSON / CSV
///   exports today. They are local-only "shortcuts" and are easy to recreate;
///   shipping them in backups would force the import path to learn another
///   schema for very little user benefit.
///
/// The store is a singleton `ObservableObject` so any view that needs to
/// observe template changes (`AddExpenseView` chip strip, future "Manage
/// Templates" surface) can subscribe without copying state around.
@MainActor
final class ExpenseTemplateStore: ObservableObject {
    static let shared = ExpenseTemplateStore()

    /// Hard cap so the chip strip never explodes in size and the persisted
    /// blob stays small. The oldest unused template is evicted when the user
    /// crosses this limit.
    static let maxTemplates: Int = 12

    /// Storage key. Kept private to this type — adding it to
    /// `UserDefaultsKeys` would tempt callers to read the raw blob and bypass
    /// the JSON encoding contract.
    private static let storageKey = "expense_templates_v1"

    @Published private(set) var templates: [ExpenseTemplate] = []

    private let defaults: UserDefaults
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.templates = load()
    }

    // MARK: - CRUD

    /// Returns the template list ordered for display: most-recently-used
    /// first, then by creation date for fresh templates that haven't been
    /// applied yet.
    var displayOrder: [ExpenseTemplate] {
        templates.sorted { lhs, rhs in
            let lKey = lhs.lastUsedAt ?? lhs.createdAt
            let rKey = rhs.lastUsedAt ?? rhs.createdAt
            return lKey > rKey
        }
    }

    func add(_ template: ExpenseTemplate) {
        // De-dupe: if a template already exists with the same id, treat it as
        // an update. We don't dedupe on title+amount because two presets with
        // the same name but different categories are perfectly valid
        // (e.g. "Tip · $5 · Food" vs "Tip · $5 · Other").
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx] = template
        } else {
            templates.append(template)
        }
        enforceCap()
        persist()
    }

    func remove(id: UUID) {
        templates.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        templates.removeAll()
        persist()
    }

    /// Bumps `lastUsedAt` so the chip strip reorders to surface the just-used
    /// template at the top.
    func markUsed(id: UUID, at date: Date = Date()) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].lastUsedAt = date
        persist()
    }

    /// Returns true when a template with the same effective signature
    /// (title + amount + category + custom category) already exists. Used by
    /// `AddExpenseView` to flip the "Save as template" affordance off when
    /// the current form would just create a duplicate.
    func containsTemplate(matching template: ExpenseTemplate) -> Bool {
        let normTitle = template.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return templates.contains { other in
            other.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normTitle
                && abs(other.amount - template.amount) < 0.005
                && other.category == template.category
                && other.customCategoryId == template.customCategoryId
        }
    }

    // MARK: - Private

    private func enforceCap() {
        guard templates.count > Self.maxTemplates else { return }
        // Drop the least-recently-used (or oldest, when never used) until we
        // are back under the cap. We never auto-delete templates the user
        // recently applied — that would feel arbitrary.
        templates.sort { lhs, rhs in
            let lKey = lhs.lastUsedAt ?? lhs.createdAt
            let rKey = rhs.lastUsedAt ?? rhs.createdAt
            return lKey > rKey
        }
        templates = Array(templates.prefix(Self.maxTemplates))
    }

    private func load() -> [ExpenseTemplate] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        do {
            return try decoder.decode([ExpenseTemplate].self, from: data)
        } catch {
            // Corrupt / out-of-date payload — discard quietly. Templates are
            // recoverable user data; we'd rather start clean than crash.
            return []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(templates)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Persistence failures should never propagate — the in-memory
            // copy is still the source of truth for the session.
        }
    }
}
