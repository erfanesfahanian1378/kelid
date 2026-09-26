import Collections
import PersianText

/// One completion result — a candidate word plus enough of the underlying
/// `KLMFile` data (`score`) for the ranker (§6.7.5, Phase 7 Session B) to
/// combine it with channel/completion-length terms.
public struct LexiconCompletion: Sendable, Equatable {
    public let wordID: UInt32
    public let surface: String
    public let score: UInt8
}

/// §6.7.3's lookup algorithms over a `KLMFile`'s trie (`TNOD`/`TTRM`).
/// Stateless beyond the file reference, so this is safely `Sendable` even
/// though it wraps a class — `KLMFile` itself does the `@unchecked
/// Sendable` read-only-memory reasoning.
public struct Lexicon: Sendable {
    private let file: KLMFile

    public init(file: KLMFile) {
        self.file = file
    }

    public var wordCount: Int {
        file.wordCount
    }

    public func surface(_ id: UInt32) -> String {
        file.surface(id)
    }

    public func score(_ id: UInt32) -> UInt8 {
        file.score(id)
    }

    public func log10Probability(_ id: UInt32) -> Double {
        file.log10Probability(id)
    }

    public func flags(_ id: UInt32) -> UInt8 {
        file.flags(id)
    }

    public func isOffensive(_ id: UInt32) -> Bool {
        file.isOffensive(id)
    }

    /// `matchKey(surface)` → walk the trie → terminal list → the id whose
    /// surface equals `canonical(surface)`, else the first (best) id
    /// sharing that match key (§6.7.2's own "Surface → word ID" rule).
    public func wordID(forSurface surface: String) -> UInt32? {
        let key = PersianNormalization.matchKey(surface)
        guard let termListOffset = walkToTerminalOffset(key) else { return nil }
        let ids = file.terminalWordIDs(at: termListOffset)
        let canonicalSurface = PersianNormalization.canonical(surface)
        return ids.first { file.surface($0) == canonicalSurface } ?? ids.first
    }

    /// Best-first completions for `prefixKey` (already a match key — callers
    /// normalize with `PersianNormalization.matchKey` first), up to `limit`
    /// results, ranked by `score` descending (ties broken by word id, i.e.
    /// frequency — lower id is more frequent).
    public func completions(prefixKey: String, limit: Int = 20) -> [LexiconCompletion] {
        guard let startIndex = walkToNodeIndex(prefixKey) else { return [] }

        var heap = Heap<HeapItem>()
        let startNode = file.node(at: startIndex)
        heap.insert(HeapItem(nodeIndex: startIndex, maxScore: startNode.maxScore))

        var collected: [LexiconCompletion] = []
        while let top = heap.popMax() {
            if collected.count >= limit {
                let worst = collected.map(\.score).min() ?? 0
                if top.maxScore < worst {
                    break
                }
            }
            let node = file.node(at: top.nodeIndex)
            if node.isTerminal {
                for id in file.terminalWordIDs(at: node.termList) {
                    collected.append(LexiconCompletion(wordID: id, surface: file.surface(id), score: file.score(id)))
                }
                // Bound growth on a pathological input (many terminals all
                // above the current cutoff) rather than trusting the loop
                // above to naturally stay small.
                if collected.count > limit * 4 {
                    collected = Self.sorted(collected).prefix(limit).map { $0 }
                }
            }
            if node.hasChildren {
                for offset in 0 ..< Int(node.childCount) {
                    let childIndex = Int(node.firstChild) + offset
                    let child = file.node(at: childIndex)
                    heap.insert(HeapItem(nodeIndex: childIndex, maxScore: child.maxScore))
                }
            }
        }
        return Array(Self.sorted(collected).prefix(limit))
    }

    private static func sorted(_ items: [LexiconCompletion]) -> [LexiconCompletion] {
        items.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
    }

    private struct HeapItem: Comparable {
        let nodeIndex: Int
        let maxScore: UInt8
        static func < (lhs: HeapItem, rhs: HeapItem) -> Bool {
            lhs.maxScore < rhs.maxScore
        }
    }

    private func walkToNodeIndex(_ key: String) -> Int? {
        var nodeIndex = 0
        for unit in key.utf16 {
            let node = file.node(at: nodeIndex)
            guard node.hasChildren, let childIndex = binarySearchChild(parent: node, label: unit) else { return nil }
            nodeIndex = childIndex
        }
        return nodeIndex
    }

    private func walkToTerminalOffset(_ key: String) -> UInt32? {
        guard let nodeIndex = walkToNodeIndex(key) else { return nil }
        let node = file.node(at: nodeIndex)
        return node.isTerminal ? node.termList : nil
    }

    /// Children are contiguous and sorted by label (§6.7.2) — binary search
    /// over `[parent.firstChild, parent.firstChild + parent.childCount)`.
    private func binarySearchChild(parent: TrieNode, label: UInt16) -> Int? {
        var low = Int(parent.firstChild)
        var high = low + Int(parent.childCount) - 1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = file.node(at: mid)
            if candidate.label == label {
                return mid
            } else if candidate.label < label {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }
}
