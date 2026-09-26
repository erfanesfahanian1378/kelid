@testable import InputEngine
import KelidCore
import KelidSettings
import Testing

/// Task 8.6's required tests (the `InputEngine` half — the decision itself
/// is `PredictionEngineTests/AutocorrectEngineTests.swift`): applying a
/// correction on a separator, and reverting it with a single backspace tap
/// right after (§6.4.6/§6.7.9 rule 6). Split into its own file, matching
/// `InputProcessorSuggestionTests.swift`'s established pattern.
@Suite("InputProcessor autocorrect apply/revert (task 8.6, §6.7.9)")
@MainActor
struct InputProcessorAutocorrectTests {
    @Test("applying an autocorrect replaces the typed word with the correction, then the separator")
    func appliesCorrectionWithSeparator() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello teh")
        _ = processor.textDidChange(in: doc) // populate context.prefix = "teh"
        processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        #expect(doc.contextBefore == "hello the ")
    }

    @Test("applying an autocorrect works with a non-space separator (punctuation/return)")
    func appliesCorrectionWithPunctuationSeparator() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        processor.handle(.applyAutocorrect(corrected: "the", separator: "."), in: doc)
        #expect(doc.contextBefore == "the.")
    }

    @Test("applying an autocorrect emits an .autocorrected effect with the original, corrected and separator")
    func appliesCorrectionEmitsEffect() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        #expect(effects.contains(.autocorrected(Autocorrection(original: "teh", corrected: "the", separator: " "))))
    }

    @Test(
        "a backspace right after an autocorrect reverts it: deletes the correction and separator, restores the typed word with no separator"
    )
    func backspaceRightAfterRevertsAutocorrect() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello teh")
        _ = processor.textDidChange(in: doc)
        processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        #expect(doc.contextBefore == "hello the ")
        processor.handle(.backspace, in: doc)
        #expect(doc.contextBefore == "hello teh") // restored, no trailing separator (§6.7.9 rule 6)
    }

    @Test("a second backspace after the revert behaves as a plain delete, not a second revert")
    func secondBackspaceAfterRevertIsPlainDelete() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        processor.handle(.backspace, in: doc) // reverts to "teh"
        #expect(doc.contextBefore == "teh")
        processor.handle(.backspace, in: doc) // plain delete now
        #expect(doc.contextBefore == "te")
    }

    @Test("typing another character between the autocorrect and backspace cancels the revert (nothing changed since = false)")
    func interveningActionCancelsRevert() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        processor.handle(.character("x"), in: doc)
        #expect(doc.contextBefore == "the x")
        processor.handle(.backspace, in: doc) // plain delete of "x", not a revert
        #expect(doc.contextBefore == "the ")
    }

    @Test("applying an autocorrect with a space separator sets autoSpacePending so smart punctuation spacing still applies")
    func appliesCorrectionSetsAutoSpacePending() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        processor.handle(.character("."), in: doc)
        #expect(doc.contextBefore == "the.")
    }
}
