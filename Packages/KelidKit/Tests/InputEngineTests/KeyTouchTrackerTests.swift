import CoreGraphics
@testable import InputEngine
import KeyboardLayout
import Testing

@Suite("KeyTouchTracker")
@MainActor
struct KeyTouchTrackerTests {
    private func key(_ id: String, kind: TrackedKeyKind = .character(alternates: []), x: Double = 0, width: Double = 40) -> TrackedKey {
        TrackedKey(id: id, kind: kind, center: CGPoint(x: x, y: 0), width: width)
    }

    // MARK: - Tap

    @Test("a character key commits on touch-up")
    func characterKeyCommitsOnUp() {
        let tracker = KeyTouchTracker(settings: TouchSettings())
        let a = key("a")
        let began = tracker.touchBegan(touchID: 1, key: a, at: .zero, timestamp: 0)
        #expect(began.contains(.pressBegan(keyID: "a")))
        #expect(!began.contains(.commit(keyID: "a")))

        let ended = tracker.touchEnded(touchID: 1, at: .zero, timestamp: 0.05)
        #expect(ended.contains(.commit(keyID: "a")))
        #expect(ended.contains(.pressEnded(keyID: "a")))
    }

    @Test("backspace and shift act immediately on touch-down, not touch-up")
    func backspaceAndShiftActOnDown() {
        let tracker = KeyTouchTracker(settings: TouchSettings())
        let backspace = key("backspace", kind: .backspace)
        let began = tracker.touchBegan(touchID: 1, key: backspace, at: .zero, timestamp: 0)
        #expect(began.contains(.immediateAction(keyID: "backspace")))

        let ended = tracker.touchEnded(touchID: 1, at: .zero, timestamp: 0.05)
        #expect(!ended.contains(.commit(keyID: "backspace")))
    }

    // MARK: - Rollover (§6.4.12)

    @Test("rollover: A down, B down, A up, B up commits A then B")
    func rolloverCommitsInOrder() {
        let tracker = KeyTouchTracker(settings: TouchSettings())
        let a = key("a", x: 0)
        let b = key("b", x: 50)

        tracker.touchBegan(touchID: "A", key: a, at: CGPoint(x: 0, y: 0), timestamp: 0)
        let bDown = tracker.touchBegan(touchID: "B", key: b, at: CGPoint(x: 50, y: 0), timestamp: 0.05)
        // B going down while A is still pressed commits A immediately (rollover).
        #expect(bDown.contains(.commit(keyID: "a")))
        #expect(bDown.contains(.pressBegan(keyID: "b")))

        // A's own touch-up no longer commits anything (already committed via rollover).
        let aUp = tracker.touchEnded(touchID: "A", at: CGPoint(x: 0, y: 0), timestamp: 0.1)
        #expect(!aUp.contains(.commit(keyID: "a")))

        let bUp = tracker.touchEnded(touchID: "B", at: CGPoint(x: 50, y: 0), timestamp: 0.15)
        #expect(bUp.contains(.commit(keyID: "b")))
    }

    // MARK: - Long-press alternates, selection by x position (task 3.4)

    @Test("long-press past the delay shows alternates")
    func longPressShowsAlternates() {
        let tracker = KeyTouchTracker(settings: TouchSettings(longPressDelayMs: 350))
        let a = key("a", kind: .character(alternates: ["à", "á", "â"]), x: 100, width: 40)
        tracker.touchBegan(touchID: 1, key: a, at: CGPoint(x: 100, y: 0), timestamp: 0)
        let stillWaiting = tracker.touchMoved(touchID: 1, to: CGPoint(x: 100, y: 0), timestamp: 0.2)
        #expect(stillWaiting.isEmpty)
        let shown = tracker.touchMoved(touchID: 1, to: CGPoint(x: 100, y: 0), timestamp: 0.4)
        #expect(shown.contains(.alternatesShown(keyID: "a", alternates: ["à", "á", "â"])))
    }

    @Test("sliding right (LTR) over an alternate cell selects it by x position")
    func alternateSelectionByPositionLTR() {
        let tracker = KeyTouchTracker(settings: TouchSettings(longPressDelayMs: 100))
        let a = key("a", kind: .character(alternates: ["à", "á", "â"]), x: 100, width: 40)
        tracker.touchBegan(touchID: 1, key: a, at: CGPoint(x: 100, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 100, y: 0), timestamp: 0.2) // triggers alternates

        // Still over the primary key: no alternate selected.
        let overPrimary = tracker.touchMoved(touchID: 1, to: CGPoint(x: 110, y: 0), timestamp: 0.21)
        #expect(overPrimary.isEmpty || overPrimary.contains(.alternateSelectionChanged(index: nil)))

        // One key-width to the right: first alternate.
        let overFirst = tracker.touchMoved(touchID: 1, to: CGPoint(x: 100 + 40 + 5, y: 0), timestamp: 0.22)
        #expect(overFirst.contains(.alternateSelectionChanged(index: 0)))

        // Committing there inserts that alternate.
        let ended = tracker.touchEnded(touchID: 1, at: CGPoint(x: 100 + 40 + 5, y: 0), timestamp: 0.3)
        #expect(ended.contains(.commitAlternate(keyID: "a", alternate: "à")))
    }

    @Test("alternate selection follows the language direction: RTL slides left to select")
    func alternateSelectionByPositionRTL() {
        let tracker = KeyTouchTracker(settings: TouchSettings(longPressDelayMs: 100))
        let alef = key("ا", kind: .character(alternates: ["آ", "أ", "إ"]), x: 100, width: 40)
        tracker.touchBegan(touchID: 1, key: alef, at: CGPoint(x: 100, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 100, y: 0), timestamp: 0.2, direction: .rtl)

        // For RTL, moving LEFT (not right) reaches the first alternate.
        let overFirst = tracker.touchMoved(touchID: 1, to: CGPoint(x: 100 - 40 - 5, y: 0), timestamp: 0.22, direction: .rtl)
        #expect(overFirst.contains(.alternateSelectionChanged(index: 0)))

        let ended = tracker.touchEnded(touchID: 1, at: CGPoint(x: 100 - 40 - 5, y: 0), timestamp: 0.3)
        #expect(ended.contains(.commitAlternate(keyID: "ا", alternate: "آ")))
    }

    @Test("releasing without moving into an alternate commits the primary character")
    func releaseWithoutMovingCommitsPrimary() {
        let tracker = KeyTouchTracker(settings: TouchSettings(longPressDelayMs: 100))
        let a = key("a", kind: .character(alternates: ["à"]), x: 100, width: 40)
        tracker.touchBegan(touchID: 1, key: a, at: CGPoint(x: 100, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 100, y: 0), timestamp: 0.2)
        let ended = tracker.touchEnded(touchID: 1, at: CGPoint(x: 100, y: 0), timestamp: 0.2)
        #expect(ended.contains(.commit(keyID: "a")))
    }

    // MARK: - Trackpad step math, LTR and RTL (§6.4.4)

    @Test("space trackpad: dragging right past the threshold steps the cursor forward (LTR context)")
    func trackpadStepsForwardLTR() {
        let tracker = KeyTouchTracker(settings: TouchSettings(cursorSpeed: 1.0, rtlVisualCursor: true))
        let space = key("space", kind: .space, x: 100, width: 200)
        tracker.touchBegan(touchID: 1, key: space, at: CGPoint(x: 100, y: 0), timestamp: 0)
        // Enter trackpad mode (> 8pt), then one more 8pt step.
        let entered = tracker.touchMoved(touchID: 1, to: CGPoint(x: 109, y: 0), timestamp: 0.05, isRTLContext: false)
        #expect(entered.isEmpty) // entering trackpad mode itself isn't a step
        let stepped = tracker.touchMoved(touchID: 1, to: CGPoint(x: 117, y: 0), timestamp: 0.1, isRTLContext: false)
        #expect(stepped.contains(.trackpadStep(characters: 1)))
    }

    @Test("space trackpad: in RTL context with rtlVisualCursor, dragging right steps the cursor backward")
    func trackpadInvertsForRTLContext() {
        let tracker = KeyTouchTracker(settings: TouchSettings(cursorSpeed: 1.0, rtlVisualCursor: true))
        let space = key("space", kind: .space, x: 100, width: 200)
        tracker.touchBegan(touchID: 1, key: space, at: CGPoint(x: 100, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 109, y: 0), timestamp: 0.05, isRTLContext: true)
        let stepped = tracker.touchMoved(touchID: 1, to: CGPoint(x: 117, y: 0), timestamp: 0.1, isRTLContext: true)
        // Dragging right visually moves the cursor left in RTL text, i.e. a
        // *negative* logical step.
        #expect(stepped.contains(.trackpadStep(characters: -1)))
    }

    @Test("space trackpad: without rtlVisualCursor, direction is never inverted")
    func trackpadNotInvertedWhenSettingOff() {
        let tracker = KeyTouchTracker(settings: TouchSettings(cursorSpeed: 1.0, rtlVisualCursor: false))
        let space = key("space", kind: .space, x: 100, width: 200)
        tracker.touchBegan(touchID: 1, key: space, at: CGPoint(x: 100, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 109, y: 0), timestamp: 0.05, isRTLContext: true)
        let stepped = tracker.touchMoved(touchID: 1, to: CGPoint(x: 117, y: 0), timestamp: 0.1, isRTLContext: true)
        #expect(stepped.contains(.trackpadStep(characters: 1)))
    }

    @Test("cursorSpeed scales the step distance")
    func cursorSpeedScalesStepDistance() {
        let tracker = KeyTouchTracker(settings: TouchSettings(cursorSpeed: 2.0))
        let space = key("space", kind: .space, x: 100, width: 200)
        tracker.touchBegan(touchID: 1, key: space, at: CGPoint(x: 100, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 109, y: 0), timestamp: 0.05) // enters trackpad mode
        // At 2x speed, a step is 4pt, not 8pt: moving another 5pt crosses one step.
        let stepped = tracker.touchMoved(touchID: 1, to: CGPoint(x: 114, y: 0), timestamp: 0.1)
        #expect(stepped.contains(.trackpadStep(characters: 1)))
    }

    // MARK: - Backspace swipe accumulate/restore (§6.4.6)

    @Test("swiping left from backspace accumulates word deletions every 24pt")
    func backspaceSwipeAccumulatesWords() {
        let tracker = KeyTouchTracker(settings: TouchSettings(backspaceSwipeDeletesWords: true))
        let backspace = key("backspace", kind: .backspace, x: 300, width: 60)
        tracker.touchBegan(touchID: 1, key: backspace, at: CGPoint(x: 300, y: 0), timestamp: 0)
        let firstWord = tracker.touchMoved(touchID: 1, to: CGPoint(x: 300 - 24, y: 0), timestamp: 0.1)
        #expect(firstWord.contains(.backspaceSwipeWordDelta(1)))
        let secondWord = tracker.touchMoved(touchID: 1, to: CGPoint(x: 300 - 48, y: 0), timestamp: 0.2)
        #expect(secondWord.contains(.backspaceSwipeWordDelta(1)))
    }

    @Test("moving back right after a swipe restores previously-deleted words")
    func backspaceSwipeRestoresOnMovingBack() {
        let tracker = KeyTouchTracker(settings: TouchSettings(backspaceSwipeDeletesWords: true))
        let backspace = key("backspace", kind: .backspace, x: 300, width: 60)
        tracker.touchBegan(touchID: 1, key: backspace, at: CGPoint(x: 300, y: 0), timestamp: 0)
        tracker.touchMoved(touchID: 1, to: CGPoint(x: 300 - 48, y: 0), timestamp: 0.1) // 2 words deleted
        let restored = tracker.touchMoved(touchID: 1, to: CGPoint(x: 300 - 24, y: 0), timestamp: 0.2) // back to 1 word
        #expect(restored.contains(.backspaceSwipeWordDelta(-1)))
    }

    @Test("backspace swipe is disabled by settings")
    func backspaceSwipeDisabledBySetting() {
        let tracker = KeyTouchTracker(settings: TouchSettings(backspaceSwipeDeletesWords: false))
        let backspace = key("backspace", kind: .backspace, x: 300, width: 60)
        tracker.touchBegan(touchID: 1, key: backspace, at: CGPoint(x: 300, y: 0), timestamp: 0)
        let moved = tracker.touchMoved(touchID: 1, to: CGPoint(x: 300 - 48, y: 0), timestamp: 0.1)
        #expect(moved.isEmpty)
    }

    // MARK: - Cancel

    @Test("touchCancelled discards without committing")
    func touchCancelledDiscardsWithoutCommit() {
        let tracker = KeyTouchTracker(settings: TouchSettings())
        let a = key("a")
        tracker.touchBegan(touchID: 1, key: a, at: .zero, timestamp: 0)
        let cancelled = tracker.touchCancelled(touchID: 1)
        #expect(cancelled.contains(.cancelled(keyID: "a")))
        #expect(!cancelled.contains(.commit(keyID: "a")))

        // A subsequent touch-up for the same (now-forgotten) touch ID does nothing.
        let ended = tracker.touchEnded(touchID: 1, at: .zero, timestamp: 0.1)
        #expect(ended.isEmpty)
    }
}
