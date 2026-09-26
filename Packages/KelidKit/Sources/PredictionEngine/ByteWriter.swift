import Foundation

/// A tiny little-endian byte-buffer builder shared by `KLMWriter`'s section
/// builders — not part of the public API, just a local convenience so the
/// writer itself doesn't repeat manual byte-shifting everywhere.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    var count: Int {
        bytes.count
    }

    mutating func u8(_ value: UInt8) {
        bytes.append(value)
    }

    mutating func u16(_ value: UInt16) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
    }

    mutating func u32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8((value >> shift) & 0xFF))
        }
    }

    mutating func u64(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8((value >> shift) & 0xFF))
        }
    }

    mutating func f32(_ value: Float) {
        u32(value.bitPattern)
    }

    mutating func raw(_ data: [UInt8]) {
        bytes.append(contentsOf: data)
    }

    /// Pads with zero bytes until `count` is a multiple of 8.
    mutating func padTo8ByteAlignment() {
        while bytes.count % 8 != 0 {
            bytes.append(0)
        }
    }

    /// Overwrites `newBytes.count` bytes starting at `offset` — used to fill
    /// in a fixed-size record's fields after its slot was reserved with
    /// zeroed placeholder bytes (`KLMWriter`'s trie-node flattening, where a
    /// node's byte offset is only known once earlier siblings/nodes have
    /// been appended).
    mutating func overwrite(at offset: Int, with newBytes: [UInt8]) {
        bytes.replaceSubrange(offset ..< offset + newBytes.count, with: newBytes)
    }
}
