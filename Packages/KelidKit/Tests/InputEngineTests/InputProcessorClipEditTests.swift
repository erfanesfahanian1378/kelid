import Foundation
@testable import InputEngine
import KelidCore
import KelidSettings
import Testing

/// Clip insert / edit panel / undo tests (task 5.8/5.9, §6.4.9/§6.5.5) — split
/// out of `InputProcessorTests.swift` itself purely to keep that type's body
/// under SwiftLint's `type_body_length`.
@Suite("InputProcessor clip & edit actions")
@MainActor
struct InputProcessorClipEditTests {
    @Test("insertClip inserts the given text and adds a leading space when both sides are word characters")
    func insertClipAddsSmartSpace() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        processor.handle(.insertClip("world"), in: doc)
        #expect(doc.contextBefore == "hello world")
    }

    @Test("insertClip does not add a space when the cursor is at the start or after non-word characters")
    func insertClipNoSmartSpaceAtWordBoundary() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ")
        processor.handle(.insertClip("world"), in: doc)
        #expect(doc.contextBefore == "hello world")
    }

    @Test("insertClip respects clipSmartSpacing = false")
    func insertClipRespectsSmartSpacingSetting() {
        let processor = InputProcessor(settings: InputSettings(clipSmartSpacing: false), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        processor.handle(.insertClip("world"), in: doc)
        #expect(doc.contextBefore == "helloworld")
    }

    @Test("copySelection produces a requestCopyToPasteboard effect with the selected text, without modifying the document")
    func copySelectionProducesEffect() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello world")
        let range = doc.buffer.index(doc.buffer.startIndex, offsetBy: 6) ..< doc.buffer.endIndex
        doc.select(range)
        let effects = processor.handle(.copySelection, in: doc)
        #expect(effects.contains(.requestCopyToPasteboard("world")))
        #expect(doc.contextBefore == "hello world")
    }

    @Test("copySelection with no selection is a no-op")
    func copySelectionWithNoSelectionIsNoOp() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello world")
        let effects = processor.handle(.copySelection, in: doc)
        #expect(effects.isEmpty)
    }

    @Test("cutSelection removes the selection and produces a requestCopyToPasteboard effect")
    func cutSelectionRemovesSelectionAndCopies() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello world")
        let range = doc.buffer.index(doc.buffer.startIndex, offsetBy: 6) ..< doc.buffer.endIndex
        doc.select(range)
        let effects = processor.handle(.cutSelection, in: doc)
        #expect(effects.contains(.requestCopyToPasteboard("world")))
        #expect(doc.contextBefore == "hello ")
    }

    @Test("pasteClipboard produces a requestPasteFromPasteboard effect")
    func pasteClipboardProducesEffect() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        let effects = processor.handle(.pasteClipboard, in: doc)
        #expect(effects.contains(.requestPasteFromPasteboard))
        #expect(doc.contextBefore == "hello") // nothing inserted yet — the controller round-trips via insertClip
    }

    @Test("undo reverses the most recent clip insert")
    func undoReversesClipInsert() {
        let processor = InputProcessor(settings: InputSettings(clipSmartSpacing: false), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        processor.handle(.insertClip("world"), in: doc)
        #expect(doc.contextBefore == "helloworld")
        processor.handle(.undo, in: doc)
        #expect(doc.contextBefore == "hello")
    }

    @Test("undo reverses the most recent word deletion, restoring exactly what was removed")
    func undoReversesWordDeletion() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello world")
        processor.handle(.deleteWordBackward, in: doc)
        #expect(doc.contextBefore == "hello ")
        processor.handle(.undo, in: doc)
        #expect(doc.contextBefore == "hello world")
    }

    @Test("undo with an empty stack is a no-op")
    func undoWithEmptyStackIsNoOp() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        processor.handle(.undo, in: doc)
        #expect(doc.contextBefore == "hello")
    }

    @Test("undo stack is cleared when the document identifier changes")
    func undoStackClearedOnDocumentChange() {
        let processor = InputProcessor(settings: InputSettings(clipSmartSpacing: false), clock: TestClock())
        let firstDoc = MockTextDocument(text: "hello")
        processor.handle(.insertClip("world"), in: firstDoc)

        let secondDoc = MockTextDocument(text: "other field")
        processor.handle(.undo, in: secondDoc) // must not touch firstDoc's insertion
        #expect(secondDoc.contextBefore == "other field")
    }
}
