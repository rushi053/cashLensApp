//
//  SharedAppGroup.swift
//  CashLens + CashLensWidgets (shared)
//
//  Single source of truth for the App Group identifier and the on-disk
//  layout the main app and the widget extension use to exchange data.
//
//  The widget extension cannot reach the main app's Core Data store
//  directly. Instead, the main app projects the data the widgets need
//  into a small JSON snapshot file inside the App Group container, and
//  the widgets read that file. This keeps the widget surface narrow
//  (no NSManagedObjectContext gymnastics in extensions, no concurrency
//  hazards) and makes the contract trivially auditable: one struct,
//  one file path.
//

import Foundation

enum SharedAppGroup {

    // MARK: - Identity

    /// App Group identifier shared by the main app and the widget
    /// extension. Must match the entitlement on BOTH targets:
    /// `CashLens.entitlements` and `CashLensWidgetsExtension.entitlements`.
    /// If you ever change this, you must update both entitlements files
    /// AND re-provision the app — the App Group is part of the cert chain.
    static let identifier = "group.com.rushi.CashLens.shared"

    // MARK: - Snapshot file

    /// Filename for the widget snapshot JSON inside the App Group
    /// container. Versioned in the name (`-v1`) so a future schema change
    /// can ship a new file without confusing older widget binaries that
    /// might still be installed during a staged rollout.
    static let snapshotFilename = "WidgetSnapshot-v1.json"

    /// Resolved file URL for the widget snapshot inside the App Group
    /// container. Returns `nil` only in the pathological case where the
    /// App Group entitlement is missing or misconfigured — callers in
    /// the main app should treat that as a non-fatal "skip the widget
    /// update" rather than crashing the user-visible flow.
    static var snapshotFileURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return container.appendingPathComponent(snapshotFilename, isDirectory: false)
    }
}
