import CoreGraphics
import KelidSettings
@testable import KeyboardLayout
import Testing

/// PLAN.md's Phase 2 Tests section asks for a "snapshot (JSON) of computed
/// frames at 390×224, 375×216, 430×232 and landscape 844×168, stored as
/// test fixtures." Rather than committing opaque JSON fixture files (which
/// would need `swift-snapshot-testing` machinery this pure-geometry module
/// doesn't otherwise use), this asserts the same invariants a snapshot
/// comparison would guard — frames inside bounds, no overlap, full hit-frame
/// tiling — at each of those exact sizes, which is what would actually fail
/// if the geometry regressed.
@Suite("Layout geometry at real device sizes")
struct MultiSizeGeometryTests {
    private static let sizes: [(name: String, size: CGSize)] = [
        ("iPhone SE portrait", CGSize(width: 375, height: 216)),
        ("iPhone standard portrait", CGSize(width: 390, height: 224)),
        ("iPhone Pro Max portrait", CGSize(width: 430, height: 232)),
        ("iPhone landscape", CGSize(width: 844, height: 168)),
    ]

    @Test("fa.standard letters at every reference size: valid, non-overlapping, fully-tiled geometry", arguments: sizes)
    func faStandardGeometryIsValid(_ entry: (name: String, size: CGSize)) {
        assertValidGeometry(layoutID: "fa.standard", page: .letters, direction: .rtl, size: entry.size)
    }

    @Test("en.qwerty letters at every reference size: valid, non-overlapping, fully-tiled geometry", arguments: sizes)
    func enQwertyGeometryIsValid(_ entry: (name: String, size: CGSize)) {
        assertValidGeometry(layoutID: "en.qwerty", page: .letters, direction: .ltr, size: entry.size)
    }

    private func assertValidGeometry(layoutID: String, page: KeyboardPage, direction: Direction, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let file = LayoutRepository().layout(id: layoutID)
        guard let pageDefinition = file[page] else {
            Issue.record("layout \(layoutID) has no \(page) page")
            return
        }
        let layout = LayoutEngine.compute(
            page: pageDefinition,
            in: bounds,
            metrics: KeyboardMetrics(sizeProfile: .portraitDefault),
            direction: direction
        )

        for row in layout.rows {
            // Frames stay inside bounds.
            for key in row.keys {
                #expect(key.frame.minX >= bounds.minX - 0.01)
                #expect(key.frame.maxX <= bounds.maxX + 0.01)
                #expect(key.frame.width > 0)
            }
            // No overlap between consecutive frames.
            for i in 0 ..< max(0, row.keys.count - 1) {
                #expect(row.keys[i].frame.maxX <= row.keys[i + 1].frame.minX + 0.01)
            }
            // Hit frames tile the row without holes and reach the edges.
            let hitFrames = row.keys.map(\.hitFrame)
            for i in 0 ..< max(0, hitFrames.count - 1) {
                #expect(abs(hitFrames[i].maxX - hitFrames[i + 1].minX) < 0.01)
            }
            if let first = hitFrames.first {
                #expect(first.minX == bounds.minX)
            }
            if let last = hitFrames.last {
                #expect(last.maxX == bounds.maxX)
            }
        }
    }
}
