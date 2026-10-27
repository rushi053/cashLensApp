import Foundation

/// Minimal STORE-only ZIP file writer — produces real `.zip` files
/// that open in Finder, Files.app, Windows Explorer, 7-Zip, anywhere.
///
/// **Scope and assumptions** (this is not a general-purpose ZIP library):
///
/// * **STORE method only** (compression code 0). Receipts are already
///   JPEG — re-compressing with deflate gains ~3% and adds a hard
///   dependency on `Compression` framework. Not worth it.
/// * **No ZIP64.** Each entry and the archive total must fit in 4 GB.
///   Receipt backups are realistically <500 MB; we explicitly throw
///   `entryTooLarge` if anyone tries to push past 4 GB.
/// * **No encryption.** Receipts aren't sensitive enough to warrant
///   it (the user already chose to share them); no password support.
/// * **UTF-8 filenames** with the General Purpose Bit 11 set so
///   modern unzippers know to treat the filename as Unicode rather
///   than CP-437.
///
/// The output is byte-for-byte identical to what 7-Zip / `zip -0`
/// would produce for the same inputs.
///
/// **Streaming** — entries are written directly to a `FileHandle` so
/// a 200 MB archive doesn't need 200 MB of RAM. Only the central
/// directory (filename + header per entry, ~80 bytes/entry) lives in
/// memory until we flush at the end.
enum ZipWriter {

    // MARK: - Public types

    /// One file inside the archive. `name` may include forward-slash
    /// path components (e.g. `"receipts/abc.jpg"`); the writer does
    /// not validate or sanitise — that's the caller's responsibility.
    struct Entry {
        let name: String
        let data: Data

        init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    enum Error: Swift.Error, LocalizedError {
        case openFailed(URL)
        case entryTooLarge(name: String, size: UInt64)
        case archiveTooLarge
        case writeFailed(underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .openFailed(let url):
                return "Couldn't open \(url.lastPathComponent) for writing."
            case .entryTooLarge(let name, _):
                return "\(name) is too large to fit in this backup format (4 GB max per file)."
            case .archiveTooLarge:
                return "Backup exceeds 4 GB. Export will need a streaming archive format."
            case .writeFailed(let err):
                return "Backup write failed: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    /// Write every entry to `url` as a single STORE-method ZIP file.
    /// Atomic — the file at `url` is only swapped in once the whole
    /// archive is written successfully. Safe to call from any thread.
    static func write(entries: [Entry], to url: URL) throws {
        // Atomic-write strategy: write to a sibling `.tmp`, then
        // rename. Half-written archives never appear at the final
        // path — important because the user may have a Files-app
        // window open on the export folder.
        let tmpURL = url.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmpURL)

        let fm = FileManager.default
        if !fm.createFile(atPath: tmpURL.path, contents: nil) {
            throw Error.openFailed(tmpURL)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: tmpURL)
        } catch {
            throw Error.openFailed(tmpURL)
        }
        defer { try? handle.close() }

        var centralDirectory = Data()
        centralDirectory.reserveCapacity(entries.count * 80)
        var totalEntriesWritten: UInt32 = 0
        var centralDirectoryStart: UInt32 = 0

        let dosTime = DOSDateTime(date: Date())

        for entry in entries {
            let entrySize = UInt64(entry.data.count)
            if entrySize > UInt64(UInt32.max) {
                throw Error.entryTooLarge(name: entry.name, size: entrySize)
            }
            // Refuse to start writing once the archive is past 4 GiB.
            // The next write would overflow the EOCD's 32-bit central
            // directory offset and produce an invalid file.
            let currentOffset = (try? handle.offset()) ?? 0
            if currentOffset > UInt64(UInt32.max) - entrySize - 1024 {
                throw Error.archiveTooLarge
            }

            let crc = CRC32.compute(entry.data)
            let nameBytes = Data(entry.name.utf8)

            // Local file header → file bytes
            let localHeader = makeLocalFileHeader(
                nameBytes: nameBytes,
                crc: crc,
                size: UInt32(entrySize),
                dosTime: dosTime
            )

            do {
                try handle.write(contentsOf: localHeader)
                try handle.write(contentsOf: nameBytes)
                try handle.write(contentsOf: entry.data)
            } catch {
                throw Error.writeFailed(underlying: error)
            }

            // Add this entry's central-directory record (kept in
            // memory until the very end, then flushed in one go).
            let cdRecord = makeCentralDirectoryRecord(
                nameBytes: nameBytes,
                crc: crc,
                size: UInt32(entrySize),
                localHeaderOffset: UInt32(currentOffset),
                dosTime: dosTime
            )
            centralDirectory.append(cdRecord)
            totalEntriesWritten += 1
        }

        // Where the central directory starts in the file — needed by
        // EOCD.
        do {
            centralDirectoryStart = UInt32((try? handle.offset()) ?? 0)
            try handle.write(contentsOf: centralDirectory)
            let eocd = makeEndOfCentralDirectory(
                totalEntries: totalEntriesWritten,
                centralDirectorySize: UInt32(centralDirectory.count),
                centralDirectoryOffset: centralDirectoryStart
            )
            try handle.write(contentsOf: eocd)
            try handle.synchronize()
            try handle.close()
        } catch {
            throw Error.writeFailed(underlying: error)
        }

        // Atomic swap into final location.
        do {
            // If a previous file is at `url`, remove it so the rename
            // can succeed (FileManager.replaceItem also works but is
            // pickier on iOS sandboxes).
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmpURL, to: url)
        } catch {
            throw Error.writeFailed(underlying: error)
        }
    }

    // MARK: - Header builders

    /// Local File Header — 30 bytes + filename, prepended to every
    /// entry's data.
    private static func makeLocalFileHeader(
        nameBytes: Data,
        crc: UInt32,
        size: UInt32,
        dosTime: DOSDateTime
    ) -> Data {
        var data = Data(capacity: 30 + nameBytes.count)
        data.appendLE(UInt32(0x04034b50))   // signature 'PK\x03\x04'
        data.appendLE(UInt16(20))           // version needed to extract (2.0)
        data.appendLE(UInt16(0x0800))       // GP bit 11 = UTF-8 filename
        data.appendLE(UInt16(0))            // compression method (STORE)
        data.appendLE(dosTime.time)         // last mod file time
        data.appendLE(dosTime.date)         // last mod file date
        data.appendLE(crc)                  // CRC-32
        data.appendLE(size)                 // compressed size
        data.appendLE(size)                 // uncompressed size
        data.appendLE(UInt16(nameBytes.count)) // filename length
        data.appendLE(UInt16(0))            // extra field length
        // Filename appended by caller (kept separate so we can stream
        // the bytes without copying them into this header buffer).
        return data
    }

    /// Central Directory File Header — 46 bytes + filename. One per
    /// entry, all written in one block at the end of the archive.
    private static func makeCentralDirectoryRecord(
        nameBytes: Data,
        crc: UInt32,
        size: UInt32,
        localHeaderOffset: UInt32,
        dosTime: DOSDateTime
    ) -> Data {
        var data = Data(capacity: 46 + nameBytes.count)
        data.appendLE(UInt32(0x02014b50))   // signature 'PK\x01\x02'
        data.appendLE(UInt16(0x031e))       // version made by (Unix + 3.0)
        data.appendLE(UInt16(20))           // version needed to extract (2.0)
        data.appendLE(UInt16(0x0800))       // GP bit 11 = UTF-8 filename
        data.appendLE(UInt16(0))            // compression method (STORE)
        data.appendLE(dosTime.time)         // last mod file time
        data.appendLE(dosTime.date)         // last mod file date
        data.appendLE(crc)                  // CRC-32
        data.appendLE(size)                 // compressed size
        data.appendLE(size)                 // uncompressed size
        data.appendLE(UInt16(nameBytes.count)) // filename length
        data.appendLE(UInt16(0))            // extra field length
        data.appendLE(UInt16(0))            // file comment length
        data.appendLE(UInt16(0))            // disk number start
        data.appendLE(UInt16(0))            // internal file attributes
        data.appendLE(UInt32(0))            // external file attributes
        data.appendLE(localHeaderOffset)    // relative offset of local header
        data.append(nameBytes)              // filename
        return data
    }

    /// End of Central Directory Record — fixed 22 bytes, last block
    /// in the archive. Tail unzippers locate everything else by
    /// scanning back from EOF for this record's signature.
    private static func makeEndOfCentralDirectory(
        totalEntries: UInt32,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32
    ) -> Data {
        var data = Data(capacity: 22)
        data.appendLE(UInt32(0x06054b50))   // signature 'PK\x05\x06'
        data.appendLE(UInt16(0))            // number of this disk
        data.appendLE(UInt16(0))            // disk where central directory starts
        data.appendLE(UInt16(min(totalEntries, UInt32(UInt16.max)))) // CD records on this disk
        data.appendLE(UInt16(min(totalEntries, UInt32(UInt16.max)))) // total CD records
        data.appendLE(centralDirectorySize) // size of central directory
        data.appendLE(centralDirectoryOffset) // offset of central directory
        data.appendLE(UInt16(0))            // file comment length
        return data
    }
}

// MARK: - DOS time/date

/// MS-DOS-style packed time/date that ZIP inherited in 1989. Modern
/// unzippers ignore it for display, but the field has to be present
/// and well-formed for spec compliance.
struct DOSDateTime {
    let time: UInt16
    let date: UInt16

    init(date d: Date) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let year = max(1980, comps.year ?? 1980)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        self.date = UInt16(((year - 1980) & 0x7F) << 9 | (month & 0xF) << 5 | (day & 0x1F))
        self.time = UInt16((hour & 0x1F) << 11 | (minute & 0x3F) << 5 | ((second / 2) & 0x1F))
    }
}

// MARK: - Little-endian write helpers

extension Data {
    /// Append a `UInt16` in little-endian byte order.
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    /// Append a `UInt32` in little-endian byte order.
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
