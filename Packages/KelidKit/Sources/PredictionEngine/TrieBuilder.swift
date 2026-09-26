/// Builds the in-memory trie `KLMWriter` flattens into `TNOD`/`TTRM`
/// (§6.7.2). Not part of the public API.
final class TrieBuildNode {
    let label: UInt16
    var children: [UInt16: TrieBuildNode] = [:]
    /// Word IDs whose match key ends exactly at this node, sorted
    /// best-first (highest `WSCR` first, tie-broken by ascending word ID —
    /// §6.7.2's "all surface forms sharing this match key, best first").
    var wordIDs: [UInt32] = []
    var maxScore: UInt8 = 0

    init(label: UInt16) {
        self.label = label
    }
}

enum TrieBuilder {
    /// `matchKeys[i]`/`scores[i]` are indexed by word ID `i`.
    static func build(matchKeys: [String], scores: [UInt8]) -> TrieBuildNode {
        let root = TrieBuildNode(label: 0)
        for id in 0 ..< matchKeys.count {
            var node = root
            for unit in matchKeys[id].utf16 {
                if let existing = node.children[unit] {
                    node = existing
                } else {
                    let created = TrieBuildNode(label: unit)
                    node.children[unit] = created
                    node = created
                }
            }
            node.wordIDs.append(UInt32(id))
        }
        for node in allNodes(from: root) {
            node.wordIDs.sort { lhs, rhs in
                let lhsScore = scores[Int(lhs)]
                let rhsScore = scores[Int(rhs)]
                return lhsScore == rhsScore ? lhs < rhs : lhsScore > rhsScore
            }
        }
        computeMaxScore(root, scores: scores)
        return root
    }

    @discardableResult
    private static func computeMaxScore(_ node: TrieBuildNode, scores: [UInt8]) -> UInt8 {
        var best: UInt8 = node.wordIDs.reduce(0) { max($0, scores[Int($1)]) }
        for child in node.children.values {
            best = max(best, computeMaxScore(child, scores: scores))
        }
        node.maxScore = best
        return best
    }

    private static func allNodes(from root: TrieBuildNode) -> [TrieBuildNode] {
        var result: [TrieBuildNode] = []
        var stack = [root]
        while let node = stack.popLast() {
            result.append(node)
            stack.append(contentsOf: node.children.values)
        }
        return result
    }
}
