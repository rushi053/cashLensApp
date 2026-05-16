import Foundation
import UIKit

/// Disk-backed store for receipt images attached to expenses.
///
/// Layout — everything lives under `Documents/Receipts/`:
/// ```
/// Documents/
/// └─ Receipts/
///    ├─ <uuid>.jpg          full resolution, JPEG quality 0.7
///    └─ …
/// ```
///
/// Design notes:
///
/// * **Filename, not path.** `Expense.receiptImagePath` stores only the
///   filename (e.g. `"5BA1F2A0-…-9C3D.jpg"`). The Documents directory
///   itself moves between iOS versions, between iCloud restores, and
///   between sandbox identity changes — absolute paths break across all
///   three. Resolving the full URL on demand is cheap and guaranteed
///   correct.
/// * **JPEG, single-file per receipt, no thumbnails.** The current UI
///   never renders more than one receipt thumbnail at a time (only on the
///   open Add/Edit sheet), so per-image thumbnail caching adds complexity
///   without value. SwiftUI's `Image.resizable()` handles downscaling
///   well enough at the sizes we display. If we ever surface receipts in
///   a scrolling list, revisit and add a thumbnail file alongside.
/// * **Background-safe.** All save/load/delete methods are pure file IO
///   — no Core Data, no `@MainActor`, no shared mutable state — so they
///   can be called from any actor or detached `Task`. Callers are
///   responsible for hopping back to the main actor before updating the
///   view model.
/// * **Compression budget.** ~2400px max edge at JPEG 0.7 keeps a typical
///   receipt under 400 KB while preserving every digit of legibility on
///   a 4K-class display. A user with 500 receipts uses ~200 MB — well
///   within iOS's tolerance for app Documents data.
enum ReceiptStorage {

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case invalidImage
        case writeFailed(underlying: Swift.Error)
        case directoryUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Couldn't process the receipt image."
            case .writeFailed(let underlying):
                return "Failed to save receipt: \(underlying.localizedDescription)"
            case .directoryUnavailable:
                return "Couldn't access the app's documents folder."
            }
        }
    }

    // MARK: - Tunables

    /// Maximum edge length (in pixels) of the saved receipt image. Larger
    /// inputs are downscaled proportionally; smaller inputs are written
    /// at native size. 2400px keeps a typical 4×6 receipt under 400 KB
    /// at JPEG 0.7 and stays sharp on every iPhone display we ship to.
    private static let maxEdgePixels: CGFloat = 2400

    /// JPEG compression quality. 0.7 is the standard "good enough for
    /// photographs of paper" sweet spot — readable text, no visible
    /// artifacts, ~3× smaller than 0.9.
    private static let jpegQuality: CGFloat = 0.7

    // MARK: - Public API

    /// Compress, downscale, and write `image` to `Documents/Receipts/<filename>`.
    /// Returns the bare filename on success — exactly what should be
    /// stored in `Expense.receiptImagePath`.
    ///
    /// Safe to call from any thread. Synchronous; expects the caller
    /// already moved the work to a background `Task`.
    @discardableResult
    static func save(_ image: UIImage) throws -> String {
        let processed = downscaleIfNeeded(image)
        guard let data = processed.jpegData(compressionQuality: jpegQuality) else {
            throw Error.invalidImage
        }
        let filename = "\(UUID().uuidString).jpg"
        let url = try receiptsDirectory().appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Error.writeFailed(underlying: error)
        }
        return filename
    }

    /// Resolve the full URL for a stored receipt filename. Returns `nil`
    /// when `filename` is missing or the file is gone (deleted iCloud
    /// restore artefact, manual cleanup, etc.) — callers should treat
    /// `nil` as "no receipt to show" and never crash.
    static func url(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        guard let dir = try? receiptsDirectory() else { return nil }
        let url = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Load a `UIImage` for the given stored filename. Synchronous file
    /// IO — fine for the small sheet preview, but wrap in a background
    /// task before opening the full-screen viewer with very large files.
    static func loadImage(filename: String?) -> UIImage? {
        guard let url = url(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Delete a single receipt file. No-op if it doesn't exist — the
    /// goal is "this filename is gone after the call", and a missing
    /// file already satisfies that.
    static func delete(filename: String?) {
        guard let filename, !filename.isEmpty,
              let dir = try? receiptsDirectory() else { return }
        let url = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete every receipt file whose name isn't in `keep`. Designed
    /// for the once-per-launch orphan sweep — guards against the rare
    /// crash-between-write-and-delete window and any eventual zip
    /// import that referenced a file we never received. Cheap O(n)
    /// where n = files in the receipts directory; runs on a background
    /// task in practice.
    static func cleanupOrphans(keep: Set<String>) {
        guard let dir = try? receiptsDirectory() else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for filename in contents where !keep.contains(filename) {
            try? fm.removeItem(at: dir.appendingPathComponent(filename))
        }
    }

    /// Total bytes used by the receipts directory. Useful for a
    /// future "Storage" stat in Profile. Returns 0 if the directory
    /// doesn't exist yet (fresh install with no receipts).
    static func totalBytesUsed() -> Int64 {
        guard let dir = try? receiptsDirectory() else { return 0 }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return contents.reduce(0) { acc, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return acc + Int64(size)
        }
    }

    // MARK: - Internal helpers

    /// Documents/Receipts/, creating the directory on first access.
    /// Throws `directoryUnavailable` only in the contrived case where
    /// `urls(for: .documentDirectory…)` returns nothing — never seen in
    /// practice on a real device.
    private static func receiptsDirectory() throws -> URL {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw Error.directoryUnavailable
        }
        let dir = docs.appendingPathComponent("Receipts", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Resize so the longer edge ≤ `maxEdgePixels`. Returns the original
    /// untouched if already small enough. Uses `UIGraphicsImageRenderer`
    /// for honest device-scale-aware rendering — avoids the half-pixel
    /// blur that Core Graphics scaling can produce.
    private static func downscaleIfNeeded(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdgePixels else { return image }

        let scale = maxEdgePixels / longest
        let target = CGSize(
            width: floor(image.size.width * scale),
            height: floor(image.size.height * scale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        // We want the requested pixel dimensions — not "logical points × screen
        // scale" — so anchor scale to 1. Otherwise a 2400×3200 source on a
        // @3x device would produce a 7200×9600 buffer.
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
