import Collections
import PersianText

/// A minimal key-adjacency map for fuzzy search's "0.6 if the keys are
/// adjacent" substitution cost (§6.7.3) — `KeyboardUI` builds this from the
/// real `KeyboardLayout.ProximityMap` (task 8.4) and passes it in;
/// `PredictionEngine` can't depend on `KeyboardLayout` directly (§4.2), same
/// "narrow slice" reasoning as `SuggestionContext`/`PredictionEngineSettings`
/// in Phase 7.
public struct FuzzyProximityMap: Sendable {
    private let adjacency: [Character: Set<Character>]

    public init(adjacency: [Character: Set<Character>] = [:]) {
        self.adjacency = adjacency
    }

    public func isAdjacent(_ a: Character, _ b: Character) -> Bool {
        adjacency[a]?.contains(b) ?? false
    }

    public static let empty = FuzzyProximityMap()
}

/// One fuzzy-search hit — `editCost` is the weighted Damerau–Levenshtein
/// distance (§6.7.3/§6.6.6), always `≤ maxCost(forTypedLength:)`.
public struct FuzzyMatch: Sendable, Equatable {
    public let wordID: UInt32
    public let surface: String
    public let score: UInt8
    public let editCost: Double
}

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
    /// Exact surface → word id, built once at load time (§6.13's memory
    /// budget is about the mapped `.klm` file itself, not this — a few MB
    /// at most for 200k short strings). Needed because n-gram contexts
    /// (task 8.1/8.2) are exact corpus tokens, including hidden entries
    /// like `<s>` that were never inserted into the trie at all, so the
    /// trie-based `wordID(forSurface:)` can't find them.
    private let surfaceToID: [String: UInt32]

    public init(file: KLMFile) {
        self.file = file
        var map: [String: UInt32] = [:]
        map.reserveCapacity(file.wordCount)
        for id in 0 ..< UInt32(file.wordCount) where map[file.surface(id)] == nil {
            map[file.surface(id)] = id
        }
        surfaceToID = map
    }

    public var wordCount: Int {
        file.wordCount
    }

    public var hasBigrams: Bool {
        file.hasBigrams
    }

    public var hasTrigrams: Bool {
        file.hasTrigrams
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

    /// Exact-surface lookup (bypasses the trie entirely) — the only way to
    /// resolve a hidden entry like `<s>` to its word id, and the correct
    /// way to resolve an n-gram context word in general (contexts are exact
    /// corpus tokens, not something to fuzzy-match).
    public func wordID(forExactSurface surface: String) -> UInt32? {
        surfaceToID[surface]
    }

    // MARK: - N-grams (task 8.1/8.2)

    /// `(next word id, quantized score)` pairs for the bigram context `w1`,
    /// best-first — empty if the file has no bigrams or `w1` was never a
    /// bigram context.
    public func bigramCandidates(forContext w1: UInt32) -> [(next: UInt32, score: UInt8)] {
        file.bigramCandidates(forContext: w1)
    }

    public func trigramCandidates(forContext w1: UInt32, _ w2: UInt32) -> [(next: UInt32, score: UInt8)] {
        file.trigramCandidates(forContext: w1, w2)
    }

    public func log10BigramProbability(_ quantizedScore: UInt8) -> Double {
        file.log10BigramProbability(quantizedScore)
    }

    public func log10TrigramProbability(_ quantizedScore: UInt8) -> Double {
        file.log10TrigramProbability(quantizedScore)
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

    // MARK: - Fuzzy search (task 8.4, §6.7.3)

    /// `maxCost` per §6.7.3: `1.0` for a short typed key (≤3 characters,
    /// where a fuzzy match risks drowning out real short words), `2.0`
    /// otherwise.
    public static func fuzzyMaxCost(forTypedLength length: Int) -> Double {
        length <= 3 ? 1.0 : 2.0
    }

    /// DFS over the trie carrying a weighted Damerau–Levenshtein DP row
    /// (§6.7.3) — pruned whenever a node's row can no longer reach
    /// `maxCost`, and hard-capped at a 30,000-node visit budget regardless.
    /// `prefixMode` additionally treats *any* node (not just terminals)
    /// whose row value at the full typed length is within budget as a hit,
    /// pulling its best completions in with a length-based penalty added —
    /// "typed `سلا` with `n` as a fat-fingered `ا`" should still surface
    /// `سلام`, not just exact-length fuzzy matches.
    public func fuzzyMatches(
        typedKey: String,
        proximity: FuzzyProximityMap = .empty,
        prefixMode: Bool = true,
        limit: Int = 20
    ) -> [FuzzyMatch] {
        let typed = Array(typedKey.utf16)
        guard !typed.isEmpty else { return [] }
        let maxCost = Self.fuzzyMaxCost(forTypedLength: typed.count)
        let visitBudget = 30000

        struct StackItem {
            let nodeIndex: Int
            let row: [Double] // dp[depth][0...typed.count]
            let parentRow: [Double]? // dp[depth-1][*], for transposition
            let edgeChar: UInt16? // the label on the edge into this node
        }

        var results: [FuzzyMatch] = []
        var visited = 0
        var stack = [StackItem(nodeIndex: 0, row: (0 ... typed.count).map(Double.init), parentRow: nil, edgeChar: nil)]

        while let item = stack.popLast(), visited < visitBudget {
            visited += 1
            let node = file.node(at: item.nodeIndex)
            let costAtFullLength = item.row[typed.count]
            let withinBudget = costAtFullLength <= maxCost

            // A node can be *both* a complete word and a prefix of longer
            // ones (e.g. "می" inside "میخواهم") — the two contributions
            // below are independent, not mutually exclusive.
            if node.isTerminal, withinBudget {
                for id in file.terminalWordIDs(at: node.termList) {
                    results.append(FuzzyMatch(wordID: id, surface: file.surface(id), score: file.score(id), editCost: costAtFullLength))
                }
            }
            // `item.nodeIndex != 0` excludes the untouched root: its row is
            // always exactly `[0, 1, 2, ..., typed.count]` (pure insertion,
            // using none of the typed characters at all), so for a short
            // typed key (`typed.count <= maxCost`) it's trivially "within
            // budget" regardless of what was actually typed. Any candidate
            // this would surface is already found (with a real, typed-
            // character-informed cost) via each depth-1 child's own
            // substitution path — every single-character substitution costs
            // exactly `1.0` generically, so a short typed key already
            // explores every first letter's own best completions on its
            // own. Skipping the root just avoids a redundant `bestCompletions`
            // search over the *entire* trie (a real, if usually invisible,
            // performance cost) on top of that.
            if prefixMode, item.nodeIndex != 0, node.hasChildren, withinBudget {
                // A completion penalty (§6.7.5's own "mild preference for
                // shorter completions" idea, reapplied here at 0.1/char so
                // fuzzy-prefix hits don't outrank exact fuzzy matches).
                for completion in bestCompletions(fromNodeIndex: item.nodeIndex, limit: 5) {
                    let penalty = 0.1 * Double(PersianNormalization.matchKey(completion.surface).count - typed.count)
                    results.append(FuzzyMatch(
                        wordID: completion.wordID,
                        surface: completion.surface,
                        score: completion.score,
                        editCost: costAtFullLength + max(penalty, 0)
                    ))
                }
            }

            guard item.row.min() ?? 0 <= maxCost, node.hasChildren else { continue }
            for offset in 0 ..< Int(node.childCount) {
                let childIndex = Int(node.firstChild) + offset
                let child = file.node(at: childIndex)
                var newRow = [Double](repeating: 0, count: typed.count + 1)
                newRow[0] = item.row[0] + 1
                for j in 1 ... typed.count {
                    let targetChar = typed[j - 1]
                    let isDoubledInTyped = j >= 2 && typed[j - 1] == typed[j - 2]
                    let insertionCost = newRow[j - 1] + (isDoubledInTyped ? 0.5 : 1.0)
                    let deletionCost = item.row[j] + 1.0
                    let subCost = Self.substitutionCost(child.label, targetChar, proximity: proximity)
                    var best = min(insertionCost, deletionCost, item.row[j - 1] + subCost)
                    if j >= 2, let parentRow = item.parentRow, let edgeChar = item.edgeChar,
                       edgeChar == targetChar, child.label == typed[j - 2]
                    {
                        best = min(best, parentRow[j - 2] + 0.8) // transposition
                    }
                    newRow[j] = best
                }
                stack.append(StackItem(nodeIndex: childIndex, row: newRow, parentRow: item.row, edgeChar: child.label))
            }
        }

        // A node can contribute the same word twice (its own terminal entry,
        // and again via `bestCompletions` if it's also a completable
        // prefix) — keep whichever occurrence has the lower edit cost.
        var bestByID: [UInt32: FuzzyMatch] = [:]
        for match in results {
            if let existing = bestByID[match.wordID], existing.editCost <= match.editCost {
                continue
            }
            bestByID[match.wordID] = match
        }
        let ranked = bestByID.values.sorted { lhs, rhs in
            lhs.editCost == rhs.editCost ? lhs.score > rhs.score : lhs.editCost < rhs.editCost
        }
        return Array(ranked.prefix(limit))
    }

    /// Best-first completions starting from an arbitrary trie node (fuzzy
    /// search's `prefixMode` branch) — the same heap-based algorithm as
    /// `completions(prefixKey:limit:)`, just seeded at a node already found
    /// by the fuzzy walk instead of by matching a literal prefix.
    private func bestCompletions(fromNodeIndex startIndex: Int, limit: Int) -> [LexiconCompletion] {
        var heap = Heap<HeapItem>()
        let startNode = file.node(at: startIndex)
        heap.insert(HeapItem(nodeIndex: startIndex, maxScore: startNode.maxScore))
        var collected: [LexiconCompletion] = []
        // Real device bug: a short typed prefix leaves every first letter
        // "within budget" (see `prefixMode` above), so this runs once per
        // letter — and unlike `completions(prefixKey:)` above, it had no
        // visit cap or periodic `collected` truncation. Ties on the same
        // quantized `maxScore` defeat the `<` early-exit below, degrading to
        // a near-exhaustive walk whose O(`collected.count`) `min()` per pop
        // hung the whole actor for tens of seconds. Fixes mirror
        // `completions(prefixKey:)`'s own mitigation.
        var visited = 0
        let visitBudget = 2000
        while let top = heap.popMax(), visited < visitBudget {
            visited += 1
            if collected.count >= limit, top.maxScore < (collected.map(\.score).min() ?? 0) {
                break
            }
            let node = file.node(at: top.nodeIndex)
            if node.isTerminal {
                for id in file.terminalWordIDs(at: node.termList) {
                    collected.append(LexiconCompletion(wordID: id, surface: file.surface(id), score: file.score(id)))
                }
                if collected.count > limit * 4 {
                    collected = Self.sorted(collected).prefix(limit).map { $0 }
                }
            }
            if node.hasChildren {
                for offset in 0 ..< Int(node.childCount) {
                    let childIndex = Int(node.firstChild) + offset
                    heap.insert(HeapItem(nodeIndex: childIndex, maxScore: file.node(at: childIndex).maxScore))
                }
            }
        }
        return Array(Self.sorted(collected).prefix(limit))
    }

    /// §6.6.6's Persian confusion groups, then proximity, then the plain
    /// 1.0 default — §6.7.3's own ordering.
    private static func substitutionCost(_ sourceUnit: UInt16, _ targetUnit: UInt16, proximity: FuzzyProximityMap) -> Double {
        guard sourceUnit != targetUnit else { return 0 }
        guard let sourceScalar = Unicode.Scalar(sourceUnit), let targetScalar = Unicode.Scalar(targetUnit) else { return 1.0 }
        let sourceChar = Character(sourceScalar)
        let targetChar = Character(targetScalar)
        if let groupCost = PersianConfusionGroups.substitutionCost(sourceChar, targetChar) {
            return groupCost
        }
        if proximity.isAdjacent(sourceChar, targetChar) {
            return 0.6
        }
        return 1.0
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
