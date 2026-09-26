import Foundation
import KelidCore
import PersianText

/// One input row for `KLMWriter.build` — a surface form and its raw corpus
/// count (from `out/<lang>.unigrams.tsv`, tab-separated `word, count[,
/// flags]`).
public struct UnigramEntry: Sendable, Equatable {
    public let surface: String
    public let count: UInt64

    public init(surface: String, count: UInt64) {
        self.surface = surface
        self.count = count
    }
}

/// Builds a §7.2/§6.7.2 `.klm` binary from unigram counts. Bigram/trigram
/// sections aren't produced yet (`hasBigrams`/`hasTrigrams` stay unset) —
/// task 7.4 explicitly defers real n-gram building to Phase 8; the format
/// itself already reserves the section tags (`BIDX`/`BENT`/`TIDX`/`TENT`)
/// for when that lands.
public enum KLMWriter {
    public enum BuildError: Error, Equatable {
        case emptyVocabulary
        case tooManyChildren(atMatchKeyPrefix: String)
        case tooManyHomographs(matchKey: String)
    }

    public static func build(
        language: LanguageID,
        unigrams: [UnigramEntry],
        maxWords: Int,
        uniMinLog10: Double = KLMFormat.defaultUniMinLog10,
        offensiveWords: Set<String> = [],
        buildUnixTime: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) throws -> Data {
        // §6.7.2: "Word IDs are sorted by descending frequency, so ID 0 is
        // the most frequent word" — ties broken by surface for determinism
        // (a stable, reproducible build from the same input).
        let sorted = unigrams
            .sorted { $0.count == $1.count ? $0.surface < $1.surface : $0.count > $1.count }
            .prefix(maxWords)
        guard !sorted.isEmpty else { throw BuildError.emptyVocabulary }

        let totalCount = sorted.reduce(0.0) { $0 + Double($1.count) }
        let surfaces = sorted.map(\.surface)
        let scores: [UInt8] = sorted.map { entry in
            let probability = Double(entry.count) / totalCount
            let log10P = log10(max(probability, .leastNormalMagnitude))
            return KLMFormat.quantize(log10P: log10P, minLog10: uniMinLog10)
        }
        let flags: [UInt8] = surfaces.map { surface in
            var f: UInt8 = 0
            if PersianNormalization.containsZWNJ(surface) {
                f |= KLMFormat.WordFlags.containsZWNJ
            }
            if offensiveWords.contains(PersianNormalization.matchKey(surface)) {
                f |= KLMFormat.WordFlags.offensive
            }
            return f
        }
        let matchKeys = surfaces.map(PersianNormalization.matchKey)

        var wstr = ByteWriter()
        var woff = ByteWriter()
        var offset: UInt32 = 0
        for surface in surfaces {
            woff.u32(offset)
            let utf8 = Array(surface.utf8)
            wstr.raw(utf8)
            offset += UInt32(utf8.count)
        }
        woff.u32(offset) // final entry = total length

        var wscr = ByteWriter()
        for score in scores {
            wscr.u8(score)
        }
        var wflg = ByteWriter()
        for flag in flags {
            wflg.u8(flag)
        }

        let (tnod, ttrm) = try buildTrieSections(matchKeys: matchKeys, scores: scores)

        let sections: [(tag: UInt32, bytes: [UInt8])] = [
            (KLMFormat.SectionTag.wstr, wstr.bytes),
            (KLMFormat.SectionTag.woff, woff.bytes),
            (KLMFormat.SectionTag.wscr, wscr.bytes),
            (KLMFormat.SectionTag.wflg, wflg.bytes),
            (KLMFormat.SectionTag.tnod, tnod),
            (KLMFormat.SectionTag.ttrm, ttrm),
        ]

        // §6.7.2: "every section starts at an 8-byte-aligned offset."
        // `body` holds everything after the section directory, so a
        // section's absolute file offset is `sectionDirectoryEnd +
        // body.count` at the point it's appended.
        let sectionDirectoryEnd = KLMFormat.headerSize + sections.count * KLMFormat.sectionDirectoryEntrySize
        var directoryEntries: [(tag: UInt32, offset: UInt64, length: UInt64)] = []
        var body = ByteWriter()
        body.raw([UInt8](repeating: 0, count: KLMFormat.align8(sectionDirectoryEnd) - sectionDirectoryEnd))
        for section in sections {
            let absoluteOffset = sectionDirectoryEnd + body.count
            directoryEntries.append((section.tag, UInt64(absoluteOffset), UInt64(section.bytes.count)))
            body.raw(section.bytes)
            body.padTo8ByteAlignment()
        }

        var header = ByteWriter()
        header.raw(KLMFormat.magic)
        header.u16(KLMFormat.formatVersion)
        header.u16(0) // flags: no bigrams/trigrams yet
        var languageBytes = Array(language.rawValue.utf8)
        languageBytes.append(contentsOf: [UInt8](repeating: 0, count: max(0, 8 - languageBytes.count)))
        header.raw(Array(languageBytes.prefix(8)))
        header.u32(UInt32(surfaces.count))
        header.u32(UInt32(tnod.count / 12))
        header.u32(UInt32(sections.count))
        header.u32(0) // reserved
        header.u64(buildUnixTime)
        header.f32(Float(uniMinLog10))
        header.f32(Float(KLMFormat.defaultBiMinLog10))
        header.f32(Float(KLMFormat.defaultTriMinLog10))
        header.raw([UInt8](repeating: 0, count: 12))
        precondition(header.count == KLMFormat.headerSize, "header must be exactly \(KLMFormat.headerSize) bytes")

        var directory = ByteWriter()
        for entry in directoryEntries {
            directory.u32(entry.tag)
            directory.u32(0) // reserved
            directory.u64(entry.offset)
            directory.u64(entry.length)
        }

        var file = ByteWriter()
        file.raw(header.bytes)
        file.raw(directory.bytes)
        file.raw(body.bytes)
        return Data(file.bytes)
    }

    private static func buildTrieSections(matchKeys: [String], scores: [UInt8]) throws -> (tnod: [UInt8], ttrm: [UInt8]) {
        let root = TrieBuilder.build(matchKeys: matchKeys, scores: scores)

        struct PendingNode {
            let index: Int
            let node: TrieBuildNode
        }

        var tnod = ByteWriter()
        var ttrm = ByteWriter()

        /// Reserve the root's own 12-byte slot (node 0); its real fields are
        /// written once dequeued, same as every other node.
        func reserveNode() {
            tnod.u32(KLMFormat.sentinelU32)
            tnod.u16(0)
            tnod.u8(0)
            tnod.u8(0)
            tnod.u32(KLMFormat.sentinelU32)
        }
        func writeNodeFields(
            atByteOffset byteOffset: Int,
            firstChild: UInt32,
            label: UInt16,
            childCount: UInt8,
            maxScore: UInt8,
            termList: UInt32
        ) {
            tnod.overwrite(at: byteOffset, with: littleEndianBytes(firstChild))
            tnod.overwrite(at: byteOffset + 4, with: littleEndianBytes(label))
            tnod.overwrite(at: byteOffset + 6, with: [childCount])
            tnod.overwrite(at: byteOffset + 7, with: [maxScore])
            tnod.overwrite(at: byteOffset + 8, with: littleEndianBytes(termList))
        }

        reserveNode()
        var queue = [PendingNode(index: 0, node: root)]
        var head = 0
        while head < queue.count {
            let pending = queue[head]
            head += 1
            let sortedChildren = pending.node.children.values.sorted { $0.label < $1.label }
            guard sortedChildren.count <= Int(UInt8.max) else {
                throw BuildError.tooManyChildren(atMatchKeyPrefix: "\(pending.node.label)")
            }
            var firstChild = KLMFormat.sentinelU32
            if !sortedChildren.isEmpty {
                firstChild = UInt32(tnod.count / 12)
                for child in sortedChildren {
                    let childIndex = tnod.count / 12
                    reserveNode()
                    queue.append(PendingNode(index: childIndex, node: child))
                }
            }
            var termList = KLMFormat.sentinelU32
            if !pending.node.wordIDs.isEmpty {
                guard pending.node.wordIDs.count <= Int(UInt8.max) else {
                    throw BuildError.tooManyHomographs(matchKey: "id\(pending.node.wordIDs.first ?? 0)")
                }
                termList = UInt32(ttrm.count)
                ttrm.u8(UInt8(pending.node.wordIDs.count))
                for id in pending.node.wordIDs {
                    ttrm.u32(id)
                }
            }
            writeNodeFields(
                atByteOffset: pending.index * 12,
                firstChild: firstChild,
                label: pending.node.label,
                childCount: UInt8(sortedChildren.count),
                maxScore: pending.node.maxScore,
                termList: termList
            )
        }

        return (tnod.bytes, ttrm.bytes)
    }
}

private func littleEndianBytes(_ value: UInt32) -> [UInt8] {
    (0 ..< 4).map { UInt8((value >> ($0 * 8)) & 0xFF) }
}

private func littleEndianBytes(_ value: UInt16) -> [UInt8] {
    (0 ..< 2).map { UInt8((value >> ($0 * 8)) & 0xFF) }
}
