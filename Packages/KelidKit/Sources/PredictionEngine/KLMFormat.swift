import KelidCore

/// §6.7.2's KLM binary format (v1) — shared constants between `KLMWriter`
/// and `KLMFile`. Little-endian throughout (the format is fixed at `Int`
/// widths below rather than platform-native, so it's portable regardless of
/// host byte order — Darwin platforms are little-endian anyway, but nothing
/// here should quietly assume that).
public enum KLMFormat {
    public static let magic: [UInt8] = Array("KLM1".utf8)
    public static let formatVersion: UInt16 = 1
    public static let headerSize = 64
    public static let sectionDirectoryEntrySize = 24 // tag u32, reserved u32, offset u64, length u64

    /// Word IDs are `UInt32`; `noWordID`/`noChild`/`noTermList` all reuse
    /// `UInt32.max` as "absent" per §6.7.2's node layout (`firstChild u32
    /// (0xFFFFFFFF = leaf)`, `termList u32 (... or 0xFFFFFFFF)`).
    public static let sentinelU32: UInt32 = 0xFFFF_FFFF

    public enum Flags {
        public static let hasBigrams: UInt16 = 1 << 0
        public static let hasTrigrams: UInt16 = 1 << 1
    }

    /// Word flags (`WFLG`, one byte per word).
    public enum WordFlags {
        public static let offensive: UInt8 = 1 << 0
        public static let containsZWNJ: UInt8 = 1 << 1
    }

    /// Section FourCC tags, stored as their 4 ASCII bytes packed
    /// little-endian into a `UInt32` (so `"WSTR"` reads as `W` in the low
    /// byte) — matches how a hex/text dump of the file would show them.
    public enum SectionTag {
        public static let wstr = fourCC("WSTR")
        public static let woff = fourCC("WOFF")
        public static let wscr = fourCC("WSCR")
        public static let wflg = fourCC("WFLG")
        public static let tnod = fourCC("TNOD")
        public static let ttrm = fourCC("TTRM")
        public static let bidx = fourCC("BIDX")
        public static let bent = fourCC("BENT")
        public static let tidx = fourCC("TIDX")
        public static let tent = fourCC("TENT")
    }

    public static func fourCC(_ tag: String) -> UInt32 {
        let bytes = Array(tag.utf8)
        precondition(bytes.count == 4, "FourCC tag must be exactly 4 ASCII bytes")
        return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
    }

    /// Default dequantization ranges (§6.7.2) — `klm build` can override
    /// these per invocation, but the reader always trusts what's actually
    /// in the header rather than assuming these constants. `Double` for
    /// precision in the writer's own math; narrowed to `Float` only when
    /// written into the header's `f32` fields.
    public static let defaultUniMinLog10: Double = -8
    public static let defaultBiMinLog10: Double = -6
    public static let defaultTriMinLog10: Double = -6

    /// `q = round(255 * (log10P - minLog) / (-minLog))`, clamped to
    /// `0...255` — a candidate right at (or numerically below, from
    /// floating-point rounding) `minLog` must still quantize to `0`, not
    /// underflow to a huge unsigned value.
    public static func quantize(log10P: Double, minLog10: Double) -> UInt8 {
        guard minLog10 < 0 else { return 0 }
        let q = (255 * (log10P - minLog10) / -minLog10).rounded()
        return UInt8(q.clamped(to: 0 ... 255))
    }

    /// `log10P = minLog * (1 - q/255)`.
    public static func dequantize(_ q: UInt8, minLog10: Double) -> Double {
        minLog10 * (1 - Double(q) / 255)
    }

    /// Rounds `offset` up to the next multiple of 8 (§6.7.2: "every section
    /// starts at an 8-byte-aligned offset").
    public static func align8(_ offset: Int) -> Int {
        (offset + 7) & ~7
    }
}
