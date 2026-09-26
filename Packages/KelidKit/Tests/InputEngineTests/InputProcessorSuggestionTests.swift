@testable import InputEngine
import KelidCore
import KelidSettings
import Testing

/// Task 7.8's required tests: "Suggestion accept with MockTextDocument
/// (plain, ZWNJ word, diacritics, English apostrophe); stale generations
/// dropped [SuggestionServiceTests]; casing [RankerTests/SuggestionServiceTests];
/// RTL slot order [KeyboardUI, deferred — no snapshot infra change this
/// phase]." Split into its own file/suite, matching the established pattern
/// (`InputProcessorClipEditTests.swift`), to keep `InputProcessorTests`
/// under SwiftLint's `type_body_length`.
@Suite("InputProcessor suggestion accept (task 7.8, §6.4.8)")
@MainActor
struct InputProcessorSuggestionTests {
    @Test("accepting a plain-word suggestion replaces the typed prefix and adds a trailing space")
    func acceptsPlainWordSuggestion() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello wor")
        _ = processor.textDidChange(in: doc) // populate context.prefix = "wor"
        processor.handle(.insertSuggestion(Suggestion(text: "world")), in: doc)
        #expect(doc.contextBefore == "hello world ")
    }

    @Test("accepting a suggestion for a ZWNJ-containing typed prefix replaces the whole prefix")
    func acceptsSuggestionOverZWNJPrefix() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "می\u{200C}خوا")
        _ = processor.textDidChange(in: doc)
        processor.handle(.insertSuggestion(Suggestion(text: "می\u{200C}خواهم")), in: doc)
        #expect(doc.contextBefore == "می\u{200C}خواهم ")
    }

    @Test("accepting a suggestion over a diacritic-containing typed prefix replaces the whole prefix")
    func acceptsSuggestionOverDiacritics() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "بِسم")
        _ = processor.textDidChange(in: doc)
        processor.handle(.insertSuggestion(Suggestion(text: "بسمله")), in: doc)
        #expect(doc.contextBefore == "بسمله ")
    }

    @Test("accepting a suggestion for an English contraction prefix works")
    func acceptsSuggestionForEnglishApostropheWord() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "don")
        _ = processor.textDidChange(in: doc)
        processor.handle(.insertSuggestion(Suggestion(text: "don't")), in: doc)
        #expect(doc.contextBefore == "don't ")
    }

    @Test("accepting a suggestion sets autoSpacePending so smart punctuation spacing still applies")
    func acceptingSuggestionSetsAutoSpacePending() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hel")
        _ = processor.textDidChange(in: doc)
        processor.handle(.insertSuggestion(Suggestion(text: "hello")), in: doc)
        #expect(doc.contextBefore == "hello ")
        processor.handle(.character("."), in: doc)
        #expect(doc.contextBefore == "hello.")
    }

    @Test("undo reverses a suggestion accept in a single tap")
    func undoReversesSuggestionAcceptInOneTap() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hel")
        _ = processor.textDidChange(in: doc)
        processor.handle(.insertSuggestion(Suggestion(text: "hello")), in: doc)
        #expect(doc.contextBefore == "hello ")
        processor.handle(.undo, in: doc)
        #expect(doc.contextBefore == "hel")
    }

    @Test("accepting a suggestion with an empty typed prefix only inserts the suggestion")
    func acceptsSuggestionWithEmptyPrefix() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ")
        _ = processor.textDidChange(in: doc)
        processor.handle(.insertSuggestion(Suggestion(text: "world")), in: doc)
        #expect(doc.contextBefore == "hello world ")
    }
}
