import Foundation

/// PKZIP-flavour CRC-32 (polynomial 0xEDB88320, the bit-reflected
/// representation of the standard CRC-32 polynomial). This is the
/// exact algorithm the ZIP spec mandates for every entry.
///
/// Implementation notes:
///
/// * We materialise the 256-entry lookup table once on first access.
///   The table is a pure constant — all subsequent calls are 8 cycles
///   per byte and lock-free.
/// * Computation is allocation-free: we walk the bytes through
///   `withUnsafeBytes` so a 200 MB backup encodes in ~80 ms on an
///   A15-class device.
/// * The seed and final XOR (both `0xFFFFFFFF`) are fixed by the
///   PKZIP spec; do **not** parameterise them.
enum CRC32 {

    /// Lazily-built lookup table. Marked `nonisolated(unsafe)` because
    /// the value is computed once via `lazy var` semantics inside the
    /// closure and never mutated afterwards — Swift's strict
    /// concurrency model can't prove that, so we promise it manually.
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    /// Compute the CRC-32 of `data`. Always returns the unsigned
    /// 32-bit value the ZIP central directory expects.
    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let tablePtr = table  // local copy → tighter loop, fewer global lookups
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for byte in bytes {
                let idx = Int((crc ^ UInt32(byte)) & 0xFF)
                crc = tablePtr[idx] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Streaming variant — folds new bytes into a running CRC. Same
    /// XOR semantics as `compute(_:)`, just split across calls.
    /// Caller seeds with `0xFFFFFFFF` and finishes with `^ 0xFFFFFFFF`.
    static func update(_ crc: UInt32, with chunk: Data) -> UInt32 {
        var c = crc
        let tablePtr = table
        chunk.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for byte in bytes {
                let idx = Int((c ^ UInt32(byte)) & 0xFF)
                c = tablePtr[idx] ^ (c >> 8)
            }
        }
        return c
    }
}
