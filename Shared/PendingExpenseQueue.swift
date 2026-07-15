//
//  PendingExpenseQueue.swift
//  CashLens + CashLensWidgets (shared)
//
//  Cross-process handoff queue for expenses logged from the
//  interactive Quick Log widget.
//
//  Why this exists: interactive widget buttons run their App Intent in
//  the WIDGET EXTENSION process, which cannot reach the app-container
//  Core Data store (and we deliberately do NOT move the store into the
//  App Group — that's a risky data migration for thousands of live
//  installs). So the widget-side intent appends a lightweight record
//  here, and the main app drains the queue into Core Data on its next
//  launch / foreground.
//
//  Storage layout — one JSON file PER RECORD inside a directory in the
//  App Group container:
//
//      <AppGroup>/PendingExpenses-v1/<uuid>.json
//
//  Per-record files make the queue lock-free across processes:
//
//    • The widget only ever CREATES new files (atomic writes) — it
//      never rewrites a shared blob, so an append can't race the app's
//      drain and lose data.
//    • The app drains by listing the directory, inserting each record
//      into Core Data, and deleting that record's file only AFTER the
//      insert commits. A crash between insert and delete just replays
//      the record next time — and the Core Data insert dedups on the
//      record's stable `id`, so replays are harmless.
//    • Ordering comes from `createdAt` inside the record, not from
//      filesystem enumeration order.
//
//  The queue may accumulate for days if the user never opens the app —
//  that's fine, the drain handles any count.
//
import Foundation

/// One expense logged from the widget, waiting to be drained into the
/// app's Core Data store. Deliberately minimal — the app fills in the
/// currency and everything else at drain time.
struct PendingExpenseRecord: Codable, Hashable, Sendable, Identifiable {
    /// Stable identity — becomes the `ExpenseEntity.id`, which is what
    /// makes the drain idempotent (replays dedup on this).
    let id: UUID
    let amount: Double
    let title: String
    /// `Expense.Category.rawValue`. Stored as a raw string so the
    /// widget target doesn't need the full `Expense` model.
    let categoryRaw: String
    /// Set when the source template targeted a custom category.
    let customCategoryId: UUID?
    /// When the user tapped the widget button — becomes the expense
    /// date, so a record drained days later still lands on the right day.
    let createdAt: Date
}

enum PendingExpenseQueue {

    /// Directory name inside the App Group container. Versioned like
    /// the snapshot file so a future schema change can move to a new
    /// directory without confusing older binaries.
    static let directoryName = "PendingExpenses-v1"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Resolved queue directory, created on first use. `nil` only when
    /// the App Group container is unreachable (misconfigured
    /// entitlement) — callers treat that as "queue unavailable".
    static var directoryURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedAppGroup.identifier)
        else { return nil }
        let dir = container.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Widget side (append / read)

    /// Atomically write one record as its own file. Returns `false` on
    /// any failure — the widget shows its normal state and the tap is
    /// simply lost, which beats crashing the widget process.
    @discardableResult
    static func append(_ record: PendingExpenseRecord) -> Bool {
        guard let dir = directoryURL else { return false }
        let url = dir.appendingPathComponent("\(record.id.uuidString).json", isDirectory: false)
        do {
            let data = try encoder.encode(record)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Read every pending record, oldest first. Unreadable / corrupt
    /// files are skipped (never thrown) — a bad record must not wedge
    /// the whole queue.
    static func readAll() -> [PendingExpenseRecord] {
        guard let dir = directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              )
        else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> PendingExpenseRecord? in
                guard let data = try? Data(contentsOf: url),
                      let record = try? decoder.decode(PendingExpenseRecord.self, from: data)
                else {
                    // A file that exists but can't be decoded will never
                    // become readable — delete it so it doesn't sit in
                    // the App Group forever being re-read on every drain.
                    // (A racing half-written file can't appear here:
                    // `append` writes atomically.)
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return record
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - App side (remove after drain)

    /// Delete one record's file after its expense has been committed
    /// to Core Data.
    static func remove(id: UUID) {
        guard let dir = directoryURL else { return }
        let url = dir.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
        try? FileManager.default.removeItem(at: url)
    }
}
