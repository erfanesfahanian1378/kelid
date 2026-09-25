import CoreGraphics
import Foundation
import KelidSettings
@testable import KeyboardLayout
import Testing

@Suite("ProximityMap")
struct ProximityMapTests {
    @Test("adjacent keys in a single row are neighbors; far-apart keys are not")
    func adjacentKeysAreNeighbors() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        // 10 equal-width keys spanning the row — "a" and "b" are adjacent;
        // "a" and "j" are at opposite ends, clearly outside 1.6x key width.
        let page = PageDefinition(rows: [Array("abcdefghij").map { KeyDefinition(out: String($0)) }])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: KeyboardMetrics(sizeProfile: .portraitDefault), direction: .ltr)
        let map = ProximityMap.build(from: layout)
        #expect(map.neighbors["a"]?.contains("b") == true)
        #expect(map.neighbors["a"]?.contains("j") == false)
    }

    @Test("non-character keys (backspace, etc.) are excluded from the map")
    func nonCharacterKeysExcluded() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        let page = PageDefinition(rows: [["a", "b", KeyDefinition(label: "⌫", action: .backspace)]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: KeyboardMetrics(sizeProfile: .portraitDefault), direction: .ltr)
        let map = ProximityMap.build(from: layout)
        #expect(map.neighbors.keys.contains("⌫") == false)
        #expect(map.neighbors["a"]?.contains("⌫") != true)
    }

    @Test("is round-trip Codable (serializable for test fixtures)")
    func isCodable() throws {
        let map = ProximityMap(neighbors: ["a": ["b", "c"]])
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(ProximityMap.self, from: data)
        #expect(decoded == map)
    }

    @Test("fa.standard's real letters layout produces a plausible proximity map")
    func realFaStandardLayout() throws {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 224)
        let file = LayoutRepository().layout(id: "fa.standard")
        let layout = try LayoutEngine.compute(
            page: #require(file[.letters]),
            in: bounds,
            metrics: KeyboardMetrics(sizeProfile: .portraitDefault),
            direction: .rtl
        )
        let map = ProximityMap.build(from: layout)
        // ض and ص are adjacent in row 1 (visual order).
        #expect(map.neighbors["ض"]?.contains("ص") == true)
        // ض (row 1, far right visually) and و (row 3, far right-ish) are not
        // neighbors — different rows, not vertically aligned closely enough.
        #expect(map.neighbors["ض"]?.contains("گ") != true)
    }
}
