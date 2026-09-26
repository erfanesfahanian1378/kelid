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

/// A `(w1, w2) -> count` row from `out/<lang>.bigrams.tsv` (task 6.10's
/// export format).
public struct BigramEntry: Sendable, Equatable {
    public let w1: String
    public let w2: String
    public let count: UInt64

    public init(w1: String, w2: String, count: UInt64) {
        self.w1 = w1
        self.w2 = w2
        self.count = count
    }
}

/// A `(w1, w2, w3) -> count` row from `out/<lang>.trigrams.tsv`.
public struct TrigramEntry: Sendable, Equatable {
    public let w1: String
    public let w2: String
    public let w3: String
    public let count: UInt64

    public init(w1: String, w2: String, w3: String, count: UInt64) {
        self.w1 = w1
        self.w2 = w2
        self.w3 = w3
        self.count = count
    }
}

/// §6.7.2's builder caps and dequantization ranges — everything `klm build`
/// exposes as flags, bundled into one struct rather than a long parameter
/// list (`KLMWriter.build` already has enough positional inputs).
public struct KLMBuildOptions: Sendable {
    public var uniMinLog10: Double
    public var biMinLog10: Double
    public var triMinLog10: Double
    /// §6.7.2: "`--max-bigram-entries 1500000`" — a global cap across every
    /// context combined, enforced *after* per-context top-K trimming.
    public var maxBigramEntries: Int
    public var maxTrigramEntries: Int
    /// §6.7.2: "per-context top-K = 32 (bigram) / 16 (trigram)."
    public var bigramTopK: Int
    public var trigramTopK: Int
    /// §6.7.2: "Bigram minimum count 3, trigram minimum count 3."
    public var bigramMinCount: UInt64
    public var trigramMinCount: UInt64
    /// §6.7.2: "trigram contexts only if `c(w1 w2) ≥ 10`."
    public var trigramContextMinBigramCount: UInt64
    /// Words that must exist (for n-gram tables to reference) but must
    /// never be a completion — task 8.1's `<s>`, specifically; matched by
    /// exact surface, not `matchKey`, since `<s>` isn't real text a user
    /// could ever type.
    public var hiddenSurfaces: Set<String>
    public var offensiveWords: Set<String>
    public var buildUnixTime: UInt64

    public init(
        uniMinLog10: Double = KLMFormat.defaultUniMinLog10,
        biMinLog10: Double = KLMFormat.defaultBiMinLog10,
        triMinLog10: Double = KLMFormat.defaultTriMinLog10,
        maxBigramEntries: Int = 1_500_000,
        maxTrigramEntries: Int = 1_000_000,
        bigramTopK: Int = 32,
        trigramTopK: Int = 16,
        bigramMinCount: UInt64 = 3,
        trigramMinCount: UInt64 = 3,
        trigramContextMinBigramCount: UInt64 = 10,
        hiddenSurfaces: Set<String> = ["<s>"],
        offensiveWords: Set<String> = [],
        buildUnixTime: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) {
        self.uniMinLog10 = uniMinLog10
        self.biMinLog10 = biMinLog10
        self.triMinLog10 = triMinLog10
        self.maxBigramEntries = maxBigramEntries
        self.maxTrigramEntries = maxTrigramEntries
        self.bigramTopK = bigramTopK
        self.trigramTopK = trigramTopK
        self.bigramMinCount = bigramMinCount
        self.trigramMinCount = trigramMinCount
        self.trigramContextMinBigramCount = trigramContextMinBigramCount
        self.hiddenSurfaces = hiddenSurfaces
        self.offensiveWords = offensiveWords
        self.buildUnixTime = buildUnixTime
    }
}

/// Builds a §6.7.2 `.klm` binary from unigram (and, from Phase 8, bigram/
/// trigram) counts.
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
        bigrams: [BigramEntry] = [],
        trigrams: [TrigramEntry] = [],
        options: KLMBuildOptions = KLMBuildOptions()
    ) throws -> Data {
        let vocab = try prepareVocabulary(unigrams: unigrams, maxWords: maxWords, options: options)
        let wordSections = buildWordSections(vocab)
        let (tnod, ttrm) = try buildTrieSections(matchKeys: vocab.matchKeys, scores: vocab.scores, hiddenIDs: vocab.hiddenIDs)
        let ngrams = NGramSections.build(
            bigrams: bigrams,
            trigrams: trigrams,
            surfaceToID: vocab.surfaceToID,
            rawCountByID: vocab.rawCountByID,
            options: options
        )

        var sections: [(tag: UInt32, bytes: [UInt8])] = [
            (KLMFormat.SectionTag.wstr, wordSections.wstr),
            (KLMFormat.SectionTag.woff, wordSections.woff),
            (KLMFormat.SectionTag.wscr, wordSections.wscr),
            (KLMFormat.SectionTag.wflg, wordSections.wflg),
            (KLMFormat.SectionTag.tnod, tnod),
            (KLMFormat.SectionTag.ttrm, ttrm),
        ]
        var headerFlags: UInt16 = 0
        if !ngrams.bidx.isEmpty {
            sections.append((KLMFormat.SectionTag.bidx, ngrams.bidx))
            sections.append((KLMFormat.SectionTag.bent, ngrams.bent))
            headerFlags |= KLMFormat.Flags.hasBigrams
        }
        if !ngrams.tidx.isEmpty {
            sections.append((KLMFormat.SectionTag.tidx, ngrams.tidx))
            sections.append((KLMFormat.SectionTag.tent, ngrams.tent))
            headerFlags |= KLMFormat.Flags.hasTrigrams
        }

        return assembleFile(
            sections: sections,
            wordCount: vocab.surfaces.count,
            trieNodeCount: tnod.count / 12,
            language: language,
            options: options,
            headerFlags: headerFlags
        )
    }

    /// One prepared, frequency-sorted, id-assigned vocabulary — everything
    /// downstream (word sections, the trie, n-gram surface resolution)
    /// reads from this instead of re-deriving it.
    private struct PreparedVocabulary {
        let surfaces: [String]
        let matchKeys: [String]
        let scores: [UInt8]
        let flags: [UInt8]
        let hiddenIDs: Set<UInt32>
        let surfaceToID: [String: UInt32]
        let rawCountByID: [UInt32: UInt64]
    }

    /// Frequency-sorts and caps the vocabulary, folds `<s>` (task 8.1's
    /// hidden entry) back in outside the cap, and assigns final word ids —
    /// §6.7.2: "Word IDs are sorted by descending frequency, so ID 0 is the
    /// most frequent word" (ties broken by surface for determinism).
    private static func prepareVocabulary(
        unigrams: [UnigramEntry],
        maxWords: Int,
        options: KLMBuildOptions
    ) throws -> PreparedVocabulary {
        // Hidden entries don't compete for the frequency cap — they're not
        // "words" in the vocabulary-size sense — so the cap is applied to
        // real words only, then hidden entries are added back before final
        // id assignment.
        let hiddenInput = unigrams.filter { options.hiddenSurfaces.contains($0.surface) }
        let realInput = unigrams.filter { !options.hiddenSurfaces.contains($0.surface) }
        let sortedReal = realInput
            .sorted { $0.count == $1.count ? $0.surface < $1.surface : $0.count > $1.count }
            .prefix(maxWords)
        let combined = (Array(sortedReal) + hiddenInput)
            .sorted { $0.count == $1.count ? $0.surface < $1.surface : $0.count > $1.count }
        guard !combined.isEmpty else { throw BuildError.emptyVocabulary }

        let totalCount = sortedReal.reduce(0.0) { $0 + Double($1.count) } // hidden entries don't count toward P(w)
        let surfaces = combined.map(\.surface)
        let hiddenIDs = Set(combined.indices.filter { options.hiddenSurfaces.contains(surfaces[$0]) }.map(UInt32.init))
        let scores: [UInt8] = combined.map { entry in
            let probability = totalCount > 0 ? Double(entry.count) / totalCount : 0
            let log10P = log10(max(probability, .leastNormalMagnitude))
            return KLMFormat.quantize(log10P: log10P, minLog10: options.uniMinLog10)
        }
        let flags: [UInt8] = combined.enumerated().map { index, entry in
            var f: UInt8 = 0
            if PersianNormalization.containsZWNJ(entry.surface) {
                f |= KLMFormat.WordFlags.containsZWNJ
            }
            if options.offensiveWords.contains(PersianNormalization.matchKey(entry.surface)) {
                f |= KLMFormat.WordFlags.offensive
            }
            if hiddenIDs.contains(UInt32(index)) {
                f |= KLMFormat.WordFlags.hidden
            }
            return f
        }
        var surfaceToID: [String: UInt32] = [:]
        surfaceToID.reserveCapacity(surfaces.count)
        for (index, surface) in surfaces.enumerated() {
            // First (highest-frequency, since `combined` is sorted) wins —
            // surfaces are unique in well-formed input anyway.
            if surfaceToID[surface] == nil {
                surfaceToID[surface] = UInt32(index)
            }
        }
        let rawCountByID = Dictionary(uniqueKeysWithValues: combined.map(\.count).enumerated().map { (UInt32($0), $1) })

        return PreparedVocabulary(
            surfaces: surfaces,
            matchKeys: surfaces.map(PersianNormalization.matchKey),
            scores: scores,
            flags: flags,
            hiddenIDs: hiddenIDs,
            surfaceToID: surfaceToID,
            rawCountByID: rawCountByID
        )
    }

    private struct WordSections {
        let wstr: [UInt8]
        let woff: [UInt8]
        let wscr: [UInt8]
        let wflg: [UInt8]
    }

    private static func buildWordSections(_ vocab: PreparedVocabulary) -> WordSections {
        var wstr = ByteWriter()
        var woff = ByteWriter()
        var offset: UInt32 = 0
        for surface in vocab.surfaces {
            woff.u32(offset)
            let utf8 = Array(surface.utf8)
            wstr.raw(utf8)
            offset += UInt32(utf8.count)
        }
        woff.u32(offset) // final entry = total length

        var wscr = ByteWriter()
        for score in vocab.scores {
            wscr.u8(score)
        }
        var wflg = ByteWriter()
        for flag in vocab.flags {
            wflg.u8(flag)
        }
        return WordSections(wstr: wstr.bytes, woff: woff.bytes, wscr: wscr.bytes, wflg: wflg.bytes)
    }

    /// §6.7.2: "every section starts at an 8-byte-aligned offset" — lays out
    /// the section directory, pads and concatenates every section's bytes,
    /// then writes the fixed-size header in front of it all.
    private static func assembleFile(
        sections: [(tag: UInt32, bytes: [UInt8])],
        wordCount: Int,
        trieNodeCount: Int,
        language: LanguageID,
        options: KLMBuildOptions,
        headerFlags: UInt16
    ) -> Data {
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
        header.u16(headerFlags)
        var languageBytes = Array(language.rawValue.utf8)
        languageBytes.append(contentsOf: [UInt8](repeating: 0, count: max(0, 8 - languageBytes.count)))
        header.raw(Array(languageBytes.prefix(8)))
        header.u32(UInt32(wordCount))
        header.u32(UInt32(trieNodeCount))
        header.u32(UInt32(sections.count))
        header.u32(0) // reserved
        header.u64(options.buildUnixTime)
        header.f32(Float(options.uniMinLog10))
        header.f32(Float(options.biMinLog10))
        header.f32(Float(options.triMinLog10))
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

    private static func buildTrieSections(
        matchKeys: [String],
        scores: [UInt8],
        hiddenIDs: Set<UInt32>
    ) throws -> (tnod: [UInt8], ttrm: [UInt8]) {
        let root = TrieBuilder.build(matchKeys: matchKeys, scores: scores, hiddenIDs: hiddenIDs)

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

func littleEndianBytes(_ value: UInt32) -> [UInt8] {
    (0 ..< 4).map { UInt8((value >> ($0 * 8)) & 0xFF) }
}

func littleEndianBytes(_ value: UInt16) -> [UInt8] {
    (0 ..< 2).map { UInt8((value >> ($0 * 8)) & 0xFF) }
}
