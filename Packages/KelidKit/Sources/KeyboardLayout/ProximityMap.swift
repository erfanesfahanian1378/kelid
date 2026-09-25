import CoreGraphics

/// For each character key in a computed letters layout, the neighbor
/// characters whose centers are within 1.6× that key's width (task 2.8).
/// Feeds the typo model's key-proximity cost (Phase 8, §D-07) — built here
/// so it's derived from real geometry, not guessed adjacency.
public struct ProximityMap: Sendable, Equatable, Codable {
    public var neighbors: [String: [String]]

    public init(neighbors: [String: [String]]) {
        self.neighbors = neighbors
    }

    public static func build(from layout: ComputedLayout) -> ProximityMap {
        struct CharKey {
            let char: String
            let center: CGPoint
            let width: CGFloat
        }

        var charKeys: [CharKey] = []
        for row in layout.rows {
            for key in row.keys {
                guard key.definition.action == .char, let out = key.definition.out, !out.isEmpty else { continue }
                charKeys.append(CharKey(char: out, center: CGPoint(x: key.frame.midX, y: key.frame.midY), width: key.frame.width))
            }
        }

        var neighbors: [String: [String]] = [:]
        for keyA in charKeys {
            let threshold = keyA.width * 1.6
            let near = charKeys
                .filter { $0.char != keyA.char }
                .filter { distance($0.center, keyA.center) <= threshold }
                .map(\.char)
            neighbors[keyA.char] = near
        }
        return ProximityMap(neighbors: neighbors)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
