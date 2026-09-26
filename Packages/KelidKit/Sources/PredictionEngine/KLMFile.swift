#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif
import Foundation
import KelidCore

/// A decoded `TNOD` trie node (§6.7.2). `Lexicon` is the only real
/// consumer — exposed as `internal`, not `private`, so it can read directly
/// from the mapped file without `KLMFile` needing to expose raw pointers.
struct TrieNode: Equatable {
    let firstChild: UInt32
    let label: UInt16
    let childCount: UInt8
    let maxScore: UInt8
    let termList: UInt32

    var hasChildren: Bool {
        firstChild != KLMFormat.sentinelU32
    }

    var isTerminal: Bool {
        termList != KLMFormat.sentinelU32
    }
}

/// Opens a `.klm` file (§6.7.2) via `mmap(PROT_READ, MAP_PRIVATE)` — never
/// copied into heap `Data`, per the memory budget rule (CLAUDE.md, §6.13).
/// `@unchecked Sendable`: the mapped memory is opened read-only and never
/// mutated after `init`, so sharing the pointer across tasks/actors is safe
/// even though `UnsafeRawPointer` itself isn't `Sendable`.
public final class KLMFile: @unchecked Sendable {
    public enum OpenError: Error, Equatable {
        case cannotOpen(path: String)
        case cannotStat
        case mmapFailed
        case fileTooSmallForHeader
        case invalidMagic
        case unsupportedVersion(UInt16)
        case invalidSectionBounds
        case nonMonotonicWordOffsets
        case missingSection(String)
    }

    public let language: LanguageID?
    public let wordCount: Int
    public let nodeCount: Int
    public let hasBigrams: Bool
    public let hasTrigrams: Bool
    public let uniMinLog10: Double
    public let buildUnixTime: UInt64

    private let fileDescriptor: Int32
    private let base: UnsafeRawPointer
    private let mappedLength: Int
    /// Every required section's bounds, resolved and validated once at
    /// `init` — never force-unwrapped at access time (CLAUDE.md: "No force
    /// unwraps outside tests").
    private let wstrSection: Section
    private let woffSection: Section
    private let wscrSection: Section
    private let wflgSection: Section
    private let tnodSection: Section
    private let ttrmSection: Section?

    private struct Section {
        let offset: Int
        let length: Int
    }

    /// Everything decoded from the header/section directory before any
    /// stored property is assigned — split out purely to keep `init`
    /// itself under SwiftLint's initializer `function_body_length` limit;
    /// `init` is still the only place that owns cleanup (via its own
    /// `defer`), since a throwing static helper can't itself guarantee the
    /// caller unwinds the mapping.
    private struct ParsedFile {
        let languageString: String
        let wordCount: Int
        let nodeCount: Int
        let hasBigrams: Bool
        let hasTrigrams: Bool
        let uniMinLog10: Double
        let buildUnixTime: UInt64
        let wstrSection: Section
        let woffSection: Section
        let wscrSection: Section
        let wflgSection: Section
        let tnodSection: Section
        let ttrmSection: Section?
    }

    public init(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw OpenError.cannotOpen(path: path) }
        var status = stat()
        guard fstat(fd, &status) == 0 else {
            close(fd)
            throw OpenError.cannotStat
        }
        let length = Int(status.st_size)
        guard length >= KLMFormat.headerSize else {
            close(fd)
            throw OpenError.fileTooSmallForHeader
        }
        guard let mapped = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0), mapped != MAP_FAILED else {
            close(fd)
            throw OpenError.mmapFailed
        }
        let base = UnsafeRawPointer(mapped)

        // From here on, any `throw` must still unmap/close — a `defer`
        // covers every exit path (including the success path, where
        // `didSucceed` is flipped so it becomes a no-op) instead of
        // repeating `munmap`/`close` at every validation `guard`.
        var didSucceed = false
        defer {
            if !didSucceed {
                munmap(mapped, length)
                close(fd)
            }
        }

        let parsed = try Self.parseFile(base: base, length: length)

        fileDescriptor = fd
        self.base = base
        mappedLength = length
        wstrSection = parsed.wstrSection
        woffSection = parsed.woffSection
        wscrSection = parsed.wscrSection
        wflgSection = parsed.wflgSection
        tnodSection = parsed.tnodSection
        ttrmSection = parsed.ttrmSection
        language = LanguageID(rawValue: parsed.languageString)
        wordCount = parsed.wordCount
        nodeCount = parsed.nodeCount
        hasBigrams = parsed.hasBigrams
        hasTrigrams = parsed.hasTrigrams
        uniMinLog10 = parsed.uniMinLog10
        buildUnixTime = parsed.buildUnixTime
        didSucceed = true
    }

    private static func parseFile(base: UnsafeRawPointer, length: Int) throws -> ParsedFile {
        guard (0 ..< 4).allSatisfy({ base.load(fromByteOffset: $0, as: UInt8.self) == KLMFormat.magic[$0] }) else {
            throw OpenError.invalidMagic
        }
        let version = base.loadUnaligned(fromByteOffset: 4, as: UInt16.self)
        guard version == KLMFormat.formatVersion else { throw OpenError.unsupportedVersion(version) }

        let flags = base.loadUnaligned(fromByteOffset: 6, as: UInt16.self)
        var languageBytes = [UInt8](repeating: 0, count: 8)
        for i in 0 ..< 8 {
            languageBytes[i] = base.load(fromByteOffset: 8 + i, as: UInt8.self)
        }
        let languageString = String(decoding: languageBytes.prefix { $0 != 0 }, as: UTF8.self)
        let wordCount = Int(base.loadUnaligned(fromByteOffset: 16, as: UInt32.self))
        let nodeCount = Int(base.loadUnaligned(fromByteOffset: 20, as: UInt32.self))
        let sectionCount = Int(base.loadUnaligned(fromByteOffset: 24, as: UInt32.self))
        let buildUnixTime = base.loadUnaligned(fromByteOffset: 32, as: UInt64.self)
        let uniMinLog10 = Double(base.loadUnaligned(fromByteOffset: 40, as: Float.self))

        let sections = try parseSectionDirectory(base: base, length: length, sectionCount: sectionCount)

        func requireSection(_ tag: UInt32, name: String) throws -> Section {
            guard let section = sections[tag] else { throw OpenError.missingSection(name) }
            return section
        }
        let wstrSection = try requireSection(KLMFormat.SectionTag.wstr, name: "WSTR")
        let woffSection = try requireSection(KLMFormat.SectionTag.woff, name: "WOFF")
        let wscrSection = try requireSection(KLMFormat.SectionTag.wscr, name: "WSCR")
        let wflgSection = try requireSection(KLMFormat.SectionTag.wflg, name: "WFLG")
        let tnodSection = try requireSection(KLMFormat.SectionTag.tnod, name: "TNOD")

        try validateWordOffsets(base: base, woffSection: woffSection, wstrSection: wstrSection, wordCount: wordCount)

        return ParsedFile(
            languageString: languageString,
            wordCount: wordCount,
            nodeCount: nodeCount,
            hasBigrams: flags & KLMFormat.Flags.hasBigrams != 0,
            hasTrigrams: flags & KLMFormat.Flags.hasTrigrams != 0,
            uniMinLog10: uniMinLog10,
            buildUnixTime: buildUnixTime,
            wstrSection: wstrSection,
            woffSection: woffSection,
            wscrSection: wscrSection,
            wflgSection: wflgSection,
            tnodSection: tnodSection,
            ttrmSection: sections[KLMFormat.SectionTag.ttrm]
        )
    }

    private static func parseSectionDirectory(base: UnsafeRawPointer, length: Int, sectionCount: Int) throws -> [UInt32: Section] {
        var sections: [UInt32: Section] = [:]
        let directoryStart = KLMFormat.headerSize
        for i in 0 ..< sectionCount {
            let entryOffset = directoryStart + i * KLMFormat.sectionDirectoryEntrySize
            guard entryOffset + KLMFormat.sectionDirectoryEntrySize <= length else {
                throw OpenError.invalidSectionBounds
            }
            let tag = base.loadUnaligned(fromByteOffset: entryOffset, as: UInt32.self)
            let sectionOffset = Int(base.loadUnaligned(fromByteOffset: entryOffset + 8, as: UInt64.self))
            let sectionLength = Int(base.loadUnaligned(fromByteOffset: entryOffset + 16, as: UInt64.self))
            guard sectionOffset >= 0, sectionLength >= 0, sectionOffset + sectionLength <= length else {
                throw OpenError.invalidSectionBounds
            }
            sections[tag] = Section(offset: sectionOffset, length: sectionLength)
        }
        return sections
    }

    /// §6.7.2: "Validation on open: ... WOFF monotonicity (cheap)" — also
    /// checks the final entry equals `WSTR`'s own length (the format's own
    /// "last entry = total length" rule).
    private static func validateWordOffsets(base: UnsafeRawPointer, woffSection: Section, wstrSection: Section, wordCount: Int) throws {
        guard woffSection.length == (wordCount + 1) * 4 else { throw OpenError.invalidSectionBounds }
        var previous: UInt32 = 0
        for i in 0 ... wordCount {
            let value = base.loadUnaligned(fromByteOffset: woffSection.offset + i * 4, as: UInt32.self)
            if i > 0, value < previous {
                throw OpenError.nonMonotonicWordOffsets
            }
            previous = value
        }
        guard Int(previous) == wstrSection.length else { throw OpenError.invalidSectionBounds }
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: base), mappedLength)
        close(fileDescriptor)
    }

    // MARK: - Word accessors

    public func surface(_ id: UInt32) -> String {
        boundsCheck(id, in: wordCount)
        let start = Int(base.loadUnaligned(fromByteOffset: woffSection.offset + Int(id) * 4, as: UInt32.self))
        let end = Int(base.loadUnaligned(fromByteOffset: woffSection.offset + Int(id + 1) * 4, as: UInt32.self))
        let slice = UnsafeRawBufferPointer(start: base + wstrSection.offset + start, count: end - start)
        return String(decoding: slice, as: UTF8.self)
    }

    /// Quantized `WSCR` byte (255 = most likely), for callers that just
    /// need a fast comparison; use `log10Probability(_:)` for the actual
    /// dequantized value.
    public func score(_ id: UInt32) -> UInt8 {
        boundsCheck(id, in: wordCount)
        return base.load(fromByteOffset: wscrSection.offset + Int(id), as: UInt8.self)
    }

    public func log10Probability(_ id: UInt32) -> Double {
        KLMFormat.dequantize(score(id), minLog10: uniMinLog10)
    }

    public func flags(_ id: UInt32) -> UInt8 {
        boundsCheck(id, in: wordCount)
        return base.load(fromByteOffset: wflgSection.offset + Int(id), as: UInt8.self)
    }

    public func isOffensive(_ id: UInt32) -> Bool {
        flags(id) & KLMFormat.WordFlags.offensive != 0
    }

    public func containsZWNJ(_ id: UInt32) -> Bool {
        flags(id) & KLMFormat.WordFlags.containsZWNJ != 0
    }

    // MARK: - Trie access (used by `Lexicon`)

    func node(at index: Int) -> TrieNode {
        #if DEBUG
            precondition(index >= 0 && index < nodeCount, "TNOD index \(index) out of bounds (nodeCount=\(nodeCount))")
        #endif
        let nodeBase = base + tnodSection.offset + index * 12
        return TrieNode(
            firstChild: nodeBase.loadUnaligned(fromByteOffset: 0, as: UInt32.self),
            label: nodeBase.loadUnaligned(fromByteOffset: 4, as: UInt16.self),
            childCount: nodeBase.load(fromByteOffset: 6, as: UInt8.self),
            maxScore: nodeBase.load(fromByteOffset: 7, as: UInt8.self),
            termList: nodeBase.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
        )
    }

    func terminalWordIDs(at byteOffset: UInt32) -> [UInt32] {
        guard let ttrm = ttrmSection else { return [] }
        let start = ttrm.offset + Int(byteOffset)
        let count = Int(base.load(fromByteOffset: start, as: UInt8.self))
        var ids: [UInt32] = []
        ids.reserveCapacity(count)
        for i in 0 ..< count {
            ids.append(base.loadUnaligned(fromByteOffset: start + 1 + i * 4, as: UInt32.self))
        }
        return ids
    }

    private func boundsCheck(_ id: UInt32, in count: Int) {
        #if DEBUG
            precondition(Int(id) < count, "word id \(id) out of bounds (count=\(count))")
        #endif
    }
}
