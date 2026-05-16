//
//  WidgetSnapshotIO.swift
//  CashLens + CashLensWidgets (shared)
//
//  Atomic read / write helpers for the WidgetSnapshot JSON file in the
//  App Group container. Both targets use the same encoder/decoder so
//  the wire format is symmetric and a future schema change touches one
//  place.
//
//  The reader (used by the widget extension) is fully synchronous and
//  failure-safe: a missing/corrupt file falls back to `WidgetSnapshot.placeholder`
//  so the widget can still render *something* on a fresh install.
//
//  The writer (used by the main app) is also synchronous because callers
//  always invoke it from a background `Task.detached`. Atomic writes
//  guarantee a partially-written file is never observable by the widget
//  process — important because WidgetKit may schedule a read at any
//  arbitrary moment.
//

import Foundation

enum WidgetSnapshotIO {

    // MARK: - Coders

    /// Shared encoder. ISO-8601 dates so the JSON file is human-readable
    /// during debugging without losing precision.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys] // Stable diffs across runs.
        return e
    }()

    /// Shared decoder. Mirrors the encoder so round-tripping is lossless.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Read

    /// Read the latest snapshot from the App Group container. Returns
    /// `WidgetSnapshot.placeholder` on any failure mode (no file, bad
    /// JSON, no App Group container, schema mismatch). The widget should
    /// NEVER crash because of a snapshot read.
    static func read() -> WidgetSnapshot {
        guard let url = SharedAppGroup.snapshotFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let decoded = try? decoder.decode(WidgetSnapshot.self, from: data),
              decoded.schemaVersion == WidgetSnapshot.placeholder.schemaVersion
        else {
            return WidgetSnapshot.placeholder
        }
        return decoded
    }

    // MARK: - Write

    /// Atomically write the snapshot to the App Group container. Returns
    /// `true` on success, `false` on any failure mode. Callers in the
    /// main app should silently ignore failures (the widget will simply
    /// render last-known-good or placeholder data on the next refresh).
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = SharedAppGroup.snapshotFileURL else { return false }
        do {
            let data = try encoder.encode(snapshot)
            // `.atomic` writes to a tmp file and renames into place — a
            // crash mid-write leaves the previous snapshot intact.
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
