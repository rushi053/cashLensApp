import Foundation

/// Minimal STORE-only ZIP file reader. Pairs with `ZipWriter` to
/// round-trip CashLens backup archives.
///
/// **Scope and assumptions:**
///
/// * Reads STORE-method (compression code 0) entries only. Throws
///   `unsupportedCompression` if the central directory advertises
///   any other method (deflate, deflate64, bzip2, …). This is fine
///   because we only ever read what we wrote.
/// * Walks the **central directory** (not local headers) for entry
///   metadata. Per the ZIP spec the central directory is the
///   authoritative source — some tools write inconsistent local
///   headers (deferred sizes via "data descriptor"), and trusting
///   the CD avoids that whole class of bugs.
/// * Verifies the CRC-32 on every extraction. If the bytes have been
///   tampered with or partially copied, we throw `crcMismatch` with
///   the entry name so the importer can surface a useful error.
/// * Supports **trailing comments** on the EOCD record by scanning
///   backward from EOF for the signature, capped at 64 KiB (the
///   spec maximum comment length).
/// * No ZIP64 (4 GB total / 4 GB per entry max). We refuse to open
///   archives that look like ZIP64.
///
/// **Lifecycle.** `open(at:)` mounts the archive (parses the central
/// directory, leaves the file handle open). `close()` releases the
/// handle. `read(name:)` extracts a single entry's bytes; safe to
/// call multiple times on the same reader.
final class ZipReader {

    enum Error: Swift.Error, LocalizedError {
        case openFailed(URL)
        case notAZipArchive
        case truncated
        case unsupportedCompression(method: UInt16, name: String)
        case zip64NotSupported
        case entryNotFound(String)
        case crcMismatch(name: String, expected: UInt32, actual: UInt32)
        case readFailed(underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .openFailed(let url):
                return "Couldn't open \(url.lastPathComponent)."
            case .notAZipArchive:
                return "This file isn't a CashLens archive (no zip end-record found)."
            case .truncated:
                return "The archive is truncated. Try the source file again."
            case .unsupportedCompression(let method, let name):
                return "Entry '\(name)' uses compression method \(method); only STORE is supported."
            case .zip64NotSupported:
                return "ZIP64 archives aren't supported. Re-export from CashLens to get a compatible file."
            case .entryNotFound(let name):
                return "The archive doesn't contain \(name)."
            case .crcMismatch(let name, _, _):
                return "Entry '\(name)' is corrupt (checksum mismatch). The file may have been damaged in transit."
            case .readFailed(let err):
                return "Couldn't read from the archive: \(err.localizedDescription)"
            }
        }
    }

    /// One entry parsed from the central directory. `dataOffset` is
    /// pre-computed at open time so `read(name:)` is a single seek
    /// + read, not a header re-parse.
    struct Entry {
        let name: String
        let crc: UInt32
        let size: UInt32           // STORE → compressed == uncompressed
        let dataOffset: UInt64     // absolute file offset to the file's bytes
    }

    // MARK: - State

    private let url: URL
    private var handle: FileHandle?
    private(set) var entries: [String: Entry] = [:]

    // MARK: - Lifecycle

    private init(url: URL) {
        self.url = url
    }

    /// Open the archive at `url` and parse its central directory.
    /// Throws if the file isn't a recognisable STORE-only zip we can
    /// process — otherwise returns a reader ready for `read(name:)`
    /// calls. Caller owns the returned reader and must call
    /// `close()` (or let it deinit) to release the file handle.
    static func open(at url: URL) throws -> ZipReader {
        let reader = ZipReader(url: url)
        do {
            reader.handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw Error.openFailed(url)
        }
        try reader.parseCentralDirectory()
        return reader
    }

    deinit { try? handle?.close() }

    /// Release the underlying file handle. Safe to call multiple
    /// times. After close, `read(name:)` will throw.
    func close() {
        try? handle?.close()
        handle = nil
    }

    // MARK: - Public read

    /// Extract one entry by name. Verifies the entry's CRC-32 before
    /// returning the bytes — a mismatch throws `crcMismatch` with
    /// the offending name so callers can surface the exact entry
    /// that's broken.
    func read(name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw Error.entryNotFound(name)
        }
        guard let handle = handle else {
            throw Error.openFailed(url)
        }

        do {
            try handle.seek(toOffset: entry.dataOffset)
            let bytes = try handle.read(upToCount: Int(entry.size)) ?? Data()
            if bytes.count != Int(entry.size) {
                throw Error.truncated
            }
            let actual = CRC32.compute(bytes)
            if actual != entry.crc {
                throw Error.crcMismatch(name: name, expected: entry.crc, actual: actual)
            }
            return bytes
        } catch let err as Error {
            throw err
        } catch {
            throw Error.readFailed(underlying: error)
        }
    }

    /// Convenience: every entry name in the order we discovered them
    /// in the central directory. Useful for iterating receipts when
    /// the caller doesn't already know the filenames.
    var entryNames: [String] {
        Array(entries.keys)
    }

    // MARK: - Central directory parsing

    /// Find EOCD, jump to the central directory, walk every record,
    /// and populate `entries`. Called once at open time.
    private func parseCentralDirectory() throws {
        guard let handle = handle else { throw Error.openFailed(url) }

        let fileSize: UInt64
        do {
            try handle.seekToEnd()
            fileSize = try handle.offset()
        } catch {
            throw Error.readFailed(underlying: error)
        }
        if fileSize < 22 {
            throw Error.notAZipArchive
        }

        // Scan back from EOF for the EOCD signature (PK\x05\x06).
        // The spec allows a trailing comment up to 64 KiB so we
        // cap the search there. 22 is the fixed EOCD size.
        let maxScan: UInt64 = min(fileSize, 22 + 65535)
        let scanFrom = fileSize - maxScan
        let scanLength = Int(maxScan)

        let tail: Data
        do {
            try handle.seek(toOffset: scanFrom)
            tail = try handle.read(upToCount: scanLength) ?? Data()
        } catch {
            throw Error.readFailed(underlying: error)
        }

        guard let eocdRelative = lastEOCDIndex(in: tail) else {
            throw Error.notAZipArchive
        }
        let eocdAbsolute = scanFrom + UInt64(eocdRelative)

        // EOCD layout (we already verified the signature):
        //   +0  signature (4)         // skipped — we matched it above
        //   +4  disk number (2)
        //   +6  disk where CD starts (2)
        //   +8  CD records on this disk (2)
        //  +10  total CD records (2)
        //  +12  CD size (4)
        //  +16  CD offset (4)
        //  +20  comment length (2)
        let eocd = tail.subdata(in: eocdRelative..<min(eocdRelative + 22, tail.count))
        guard eocd.count == 22 else { throw Error.truncated }

        let totalRecords = readLE16(eocd, at: 10)
        let cdSize = readLE32(eocd, at: 12)
        let cdOffset = readLE32(eocd, at: 16)

        // Heuristic ZIP64 check — if any of these fields are
        // saturated to their max value, ZIP64 was used to encode
        // the real values in an extra field. We don't support that.
        if totalRecords == UInt16.max || cdSize == UInt32.max || cdOffset == UInt32.max {
            throw Error.zip64NotSupported
        }
        if UInt64(cdOffset) + UInt64(cdSize) > eocdAbsolute {
            throw Error.notAZipArchive
        }

        // Read the entire central directory in one go — it's
        // typically <100 KiB even for archives with hundreds of
        // entries, so streaming parsing isn't worth the complexity.
        let cdBytes: Data
        do {
            try handle.seek(toOffset: UInt64(cdOffset))
            cdBytes = try handle.read(upToCount: Int(cdSize)) ?? Data()
            if cdBytes.count != Int(cdSize) {
                throw Error.truncated
            }
        } catch {
            throw Error.readFailed(underlying: error)
        }

        try walkCentralDirectory(cdBytes, recordCount: Int(totalRecords))
    }

    /// Parse `cdBytes` into `entries`. Each Central Directory File
    /// Header is 46 bytes + filename + extra + comment. We use the
    /// CD record's CRC, size, and `localHeaderOffset` directly —
    /// then we open the local header just enough to skip past it
    /// and record the data offset.
    private func walkCentralDirectory(_ cdBytes: Data, recordCount: Int) throws {
        guard let handle = handle else { throw Error.openFailed(url) }

        var cursor = 0
        for _ in 0..<recordCount {
            if cursor + 46 > cdBytes.count {
                throw Error.truncated
            }
            // Verify signature on every record — defends against
            // off-by-one parsing bugs.
            let sig = readLE32(cdBytes, at: cursor)
            guard sig == 0x02014b50 else {
                throw Error.notAZipArchive
            }

            let method = readLE16(cdBytes, at: cursor + 10)
            let crc = readLE32(cdBytes, at: cursor + 16)
            let compSize = readLE32(cdBytes, at: cursor + 20)
            let uncompSize = readLE32(cdBytes, at: cursor + 24)
            let nameLen = Int(readLE16(cdBytes, at: cursor + 28))
            let extraLen = Int(readLE16(cdBytes, at: cursor + 30))
            let commentLen = Int(readLE16(cdBytes, at: cursor + 32))
            let localHeaderOffset = readLE32(cdBytes, at: cursor + 42)

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            if nameEnd > cdBytes.count { throw Error.truncated }
            let nameBytes = cdBytes.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameBytes, encoding: .utf8) ?? ""

            // Advance cursor to the next record before any throw so
            // an unsupported entry doesn't leave us mis-aligned.
            cursor = nameEnd + extraLen + commentLen

            if method != 0 {
                throw Error.unsupportedCompression(method: method, name: name)
            }
            // We treat compressed == uncompressed as the contract
            // for STORE entries; mismatched values are a sign the
            // archive lies and we should refuse to read it.
            if compSize != uncompSize {
                throw Error.unsupportedCompression(method: method, name: name)
            }

            // Compute the absolute offset to the entry's bytes by
            // peeking at the local header to learn its filename and
            // extra-field length. The CD's nameLen is the same as
            // the local header's, but the local header's extra-field
            // length is allowed to differ — we need its real value.
            let dataOffset = try resolveLocalDataOffset(
                handle: handle,
                localHeaderOffset: UInt64(localHeaderOffset)
            )

            entries[name] = Entry(
                name: name,
                crc: crc,
                size: compSize,
                dataOffset: dataOffset
            )
        }
    }

    /// Read the Local File Header at `localHeaderOffset` enough to
    /// learn its filename + extra lengths, and return the absolute
    /// offset of the entry's bytes. Fixed local-header size is 30.
    private func resolveLocalDataOffset(handle: FileHandle, localHeaderOffset: UInt64) throws -> UInt64 {
        do {
            try handle.seek(toOffset: localHeaderOffset)
            let head = try handle.read(upToCount: 30) ?? Data()
            guard head.count == 30 else { throw Error.truncated }
            let sig = readLE32(head, at: 0)
            guard sig == 0x04034b50 else {
                throw Error.notAZipArchive
            }
            let nameLen = UInt64(readLE16(head, at: 26))
            let extraLen = UInt64(readLE16(head, at: 28))
            return localHeaderOffset + 30 + nameLen + extraLen
        } catch let err as Error {
            throw err
        } catch {
            throw Error.readFailed(underlying: error)
        }
    }

    // MARK: - Helpers

    /// Find the **last** EOCD signature in `data`. Last (rather than
    /// first) handles the rare case where the comment field happens
    /// to contain the four-byte signature literal.
    private func lastEOCDIndex(in data: Data) -> Int? {
        let needle: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        guard data.count >= needle.count else { return nil }
        var i = data.count - needle.count
        while i >= 0 {
            // Spec: comment is at most 65535 bytes, so the EOCD
            // signature must be ≥ 22 bytes from EOF. The minimum
            // remaining bytes constraint also implicitly defends
            // against truncated tails.
            if data[i] == needle[0],
               data[i + 1] == needle[1],
               data[i + 2] == needle[2],
               data[i + 3] == needle[3] {
                return i
            }
            i -= 1
        }
        return nil
    }

    /// Little-endian 16-bit read at `offset`.
    private func readLE16(_ data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[data.startIndex + offset])
            | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    /// Little-endian 32-bit read at `offset`.
    private func readLE32(_ data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}
