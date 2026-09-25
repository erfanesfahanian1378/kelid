@testable import InputEngine
import Testing

@Suite("MockTextDocument")
@MainActor
struct MockTextDocumentTests {
    @Test("insertText inserts at the cursor and advances it")
    func insertAdvancesCursor() {
        let doc = MockTextDocument(text: "hello")
        doc.insertText(" world")
        #expect(doc.contextBefore == "hello world")
        #expect(doc.hasText)
    }

    @Test("deleteBackward removes one grapheme by default")
    func deleteBackwardRemovesOneGrapheme() {
        let doc = MockTextDocument(text: "abc")
        doc.deleteBackward()
        #expect(doc.contextBefore == "ab")
    }

    @Test("deleteBackward at the start of the buffer is a no-op")
    func deleteBackwardAtStartIsNoOp() {
        let doc = MockTextDocument(text: "")
        doc.deleteBackward()
        #expect(doc.contextBefore == "")
    }

    @Test("deleteBackward with a selection removes the selection instead")
    func deleteBackwardWithSelectionRemovesSelection() {
        let doc = MockTextDocument(text: "hello world")
        let range = doc.buffer.index(doc.buffer.startIndex, offsetBy: 6) ..< doc.buffer.endIndex
        doc.select(range)
        #expect(doc.selectedText == "world")
        doc.deleteBackward()
        #expect(doc.contextBefore == "hello ")
        #expect(doc.selectedText == nil)
    }

    @Test("adjustTextPosition moves the cursor and clears any selection")
    func adjustTextPositionMovesCursor() {
        let doc = MockTextDocument(text: "hello world")
        doc.selectAll()
        doc.adjustTextPosition(byCharacterOffset: -6)
        #expect(doc.selectedText == nil)
        #expect(doc.contextBefore == "hello")
        #expect(doc.contextAfter == " world")
    }

    @Test("adjustTextPosition clamps to the buffer's bounds")
    func adjustTextPositionClampsToBounds() {
        let doc = MockTextDocument(text: "hi")
        doc.adjustTextPosition(byCharacterOffset: -100)
        #expect(doc.contextBefore == "")
        doc.adjustTextPosition(byCharacterOffset: 100)
        #expect(doc.contextBefore == "hi")
    }

    @Test("contextLimit .characters(n) truncates both sides")
    func contextLimitCharacters() {
        let doc = MockTextDocument(text: "abcdefghij")
        doc.adjustTextPosition(byCharacterOffset: -5) // cursor after "abcde"
        doc.contextLimit = .characters(3)
        #expect(doc.contextBefore == "cde")
        #expect(doc.contextAfter == "fgh")
    }

    @Test("contextLimit .currentParagraphOnly stops at the nearest newline")
    func contextLimitCurrentParagraph() {
        let doc = MockTextDocument(text: "line one\nline two")
        doc.contextLimit = .currentParagraphOnly
        #expect(doc.contextBefore == "line two")
    }

    @Test("contextIsNil forces both context sides to nil")
    func contextIsNilForcesNil() {
        let doc = MockTextDocument(text: "hello")
        doc.contextIsNil = true
        #expect(doc.contextBefore == nil)
        #expect(doc.contextAfter == nil)
    }

    @Test("contextDelay serves the pre-mutation context until settleContext()")
    func contextDelaySimulatesLag() {
        let doc = MockTextDocument(text: "hello")
        doc.contextDelay = true
        doc.insertText(" world")
        // A real lagging host would still report the old value right after
        // the mutation that's supposed to have changed it.
        #expect(doc.contextBefore == "hello")
        doc.settleContext()
        #expect(doc.contextBefore == "hello world")
    }

    @Test("scalar deletion mode removes one Unicode scalar, not a whole grapheme")
    func scalarDeletionRemovesOneScalar() {
        // "a" + combining acute accent (U+0301) forms a single grapheme "á".
        let doc = MockTextDocument(text: "a\u{0301}")
        doc.deletionGranularity = .scalar
        doc.deleteBackward()
        // Only the combining mark is gone; the base "a" remains — unlike
        // grapheme mode, which would delete the whole "á" in one call.
        #expect(doc.contextBefore == "a")
    }

    @Test("grapheme deletion mode removes the whole combining-mark cluster in one call")
    func graphemeDeletionRemovesWholeCluster() {
        let doc = MockTextDocument(text: "a\u{0301}")
        doc.deletionGranularity = .grapheme
        doc.deleteBackward()
        #expect(doc.contextBefore == "")
    }
}
