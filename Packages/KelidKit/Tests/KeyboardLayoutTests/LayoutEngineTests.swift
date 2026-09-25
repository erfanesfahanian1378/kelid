import CoreGraphics
import KelidSettings
@testable import KeyboardLayout
import Testing

@Suite("LayoutEngine")
struct LayoutEngineTests {
    private func metrics(rowHeight: CGFloat = 54, sidePadding: CGFloat = 3, keyGapH: CGFloat = 6,
                         keyGapV: CGFloat = 12) -> KeyboardMetrics
    {
        var profile = SizeProfile.portraitDefault
        profile.rowHeight = rowHeight
        profile.sidePadding = sidePadding
        profile.keyGapH = keyGapH
        profile.keyGapV = keyGapV
        return KeyboardMetrics(sizeProfile: profile)
    }

    @Test("frames lie inside bounds and are correctly spaced/sized")
    func framesLieInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 200)
        let page = PageDefinition(rows: [["a", "b", "c"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)
        let row = layout.rows[0]
        #expect(row.keys.count == 3)
        for key in row.keys {
            #expect(bounds.contains(CGPoint(x: key.frame.midX, y: key.frame.midY)))
            #expect(key.frame.minX >= bounds.minX)
            #expect(key.frame.maxX <= bounds.maxX)
        }
        // Equal-width keys (same unit) should have equal frame widths.
        #expect(abs(row.keys[0].frame.width - row.keys[1].frame.width) < 0.001)
        #expect(abs(row.keys[1].frame.width - row.keys[2].frame.width) < 0.001)
        // Gap between consecutive key frames matches keyGapH.
        let gap = row.keys[1].frame.minX - row.keys[0].frame.maxX
        #expect(abs(gap - 6) < 0.001)
    }

    @Test("frames don't overlap within a row")
    func framesDoNotOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 200)
        let page = PageDefinition(rows: [["a", "b", "c", "d", "e"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)
        let frames = layout.rows[0].keys.map(\.frame)
        for i in 0 ..< (frames.count - 1) {
            #expect(frames[i].maxX <= frames[i + 1].minX + 0.001)
        }
    }

    @Test("hit frames tile each row without holes: consecutive hit frames touch")
    func hitFramesTileWithoutHoles() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 200)
        let page = PageDefinition(rows: [["a", "b", "c"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)
        let hitFrames = layout.rows[0].keys.map(\.hitFrame)
        for i in 0 ..< (hitFrames.count - 1) {
            #expect(abs(hitFrames[i].maxX - hitFrames[i + 1].minX) < 0.001)
        }
        // First/last hit frames reach the view edges (no dead zone at the sides).
        #expect(hitFrames.first?.minX == bounds.minX)
        #expect(hitFrames.last?.maxX == bounds.maxX)
    }

    @Test("hit frames span the full row height, including vertical gaps")
    func hitFramesSpanFullRowHeight() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 200)
        let page = PageDefinition(rows: [["a", "b"], ["c", "d"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(rowHeight: 50), direction: .ltr)
        for row in layout.rows {
            for key in row.keys {
                #expect(key.hitFrame.height == 50)
            }
        }
    }

    @Test("key(at:) finds the key whose hit frame contains the point")
    func keyAtFindsContainingKey() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        let page = PageDefinition(rows: [["a", "b", "c"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)
        let middleKey = layout.rows[0].keys[1]
        let found = layout.key(at: CGPoint(x: middleKey.hitFrame.midX, y: middleKey.hitFrame.midY))
        #expect(found?.definition.out == "b")
    }

    @Test("key(at:) at the view edge resolves to the edge key (no dead zone)")
    func keyAtViewEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        let page = PageDefinition(rows: [["a", "b", "c"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)
        #expect(layout.key(at: CGPoint(x: 0, y: 27))?.definition.out == "a")
        #expect(layout.key(at: CGPoint(x: 389, y: 27))?.definition.out == "c")
    }

    @Test("key(at:) in a gap falls back to the nearest key center in the row")
    func keyAtInGapFallsBackToNearest() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        // A spacer creates a real gap with no hit frame at all.
        let page = PageDefinition(rows: [[KeyDefinition(out: "a"), KeyDefinition(spacer: 2), KeyDefinition(out: "b")]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)
        let spacerMidX = (layout.rows[0].keys[0].frame.maxX + layout.rows[0].keys[1].frame.minX) / 2
        let found = layout.key(at: CGPoint(x: spacerMidX, y: 27))
        #expect(found != nil) // nearest-in-row fallback, never nil inside the row's vertical span
    }

    @Test("a flex key (bottom row) absorbs the remaining width")
    func flexKeyAbsorbsRemainingWidth() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        let lettersPage = PageDefinition(rows: [Array(repeating: KeyDefinition(out: "a"), count: 10)])
        let bottomRow = BottomRowBuilder.build(BottomRowContext(page: .letters, language: .en, languagesCount: 1, needsGlobe: false))
        let page = PageDefinition(rows: lettersPage.rows + [bottomRow])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: metrics(), direction: .ltr)

        let bottomRowKeys = layout.rows[1].keys
        let spaceKey = bottomRowKeys.first { $0.definition.flex }
        #expect(spaceKey != nil)
        #expect((spaceKey?.frame.width ?? 0) > 0)
        // The flex key should be noticeably wider than a fixed 1-unit key
        // (the "." key here) once the space bar absorbs the leftover width.
        let dotKey = bottomRowKeys.first { $0.definition.out == "." }
        #expect((spaceKey?.frame.width ?? 0) > (dotKey?.frame.width ?? .infinity))
    }

    @Test("one-handed mode narrows the content rect and aligns it to the chosen side")
    func oneHandedNarrowsContentRect() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        var profile = SizeProfile.portraitDefault
        profile.oneHanded = .right
        profile.oneHandedWidthRatio = 0.8
        let m = KeyboardMetrics(sizeProfile: profile)
        let page = PageDefinition(rows: [["a"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: m, direction: .ltr)
        #expect(layout.contentRect.width == 320) // 400 * 0.8
        #expect(layout.contentRect.maxX == bounds.maxX) // right-aligned
    }
}
