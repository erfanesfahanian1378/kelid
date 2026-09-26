@testable import InputEngine
import KelidCore
import Testing

/// Task 9.3's required tests: commit detection sequences (type → space;
/// type → suggestion; punctuation; newline; autocorrect apply/revert) and
/// §6.7.8's privacy/learnability filters. Split into its own file, matching
/// the established pattern (`InputProcessorSuggestionTests.swift`,
/// `InputProcessorAutocorrectTests.swift`).
@Suite("InputProcessor commit detection (task 9.3, §6.7.8)")
@MainActor
struct InputProcessorLearningTests {
    private func learnedEvent(in effects: [InputEffect]) -> CommitEvent? {
        for effect in effects {
            if case let .learn(event) = effect {
                return event
            }
        }
        return nil
    }

    @Test("a space after a typed word emits .learn with source .typed and the right previous words")
    func spaceCommitsTypedWord() throws {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hi hello")
        _ = processor.textDidChange(in: doc) // populate context.prefix = "hello", previousWords = ["hi"]
        let effects = processor.handle(.space, in: doc)
        let event = try #require(learnedEvent(in: effects))
        #expect(event.word == "hello")
        #expect(event.source == .typed)
        #expect(event.previousWords == ["hi"])
    }

    @Test("punctuation right after a typed word also commits it")
    func punctuationCommitsTypedWord() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.character("."), in: doc)
        #expect(learnedEvent(in: effects)?.word == "hello")
    }

    @Test("return right after a typed word also commits it")
    func returnCommitsTypedWord() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.returnKey, in: doc)
        #expect(learnedEvent(in: effects)?.word == "hello")
    }

    @Test("typing a word character never commits anything")
    func typingWordCharacterDoesNotCommit() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hell")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.character("o"), in: doc)
        #expect(learnedEvent(in: effects) == nil)
    }

    @Test("a space with nothing typed yet commits nothing")
    func spaceWithEmptyPrefixCommitsNothing() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.space, in: doc)
        #expect(learnedEvent(in: effects) == nil)
    }

    @Test("accepting a regular suggestion commits it with source .accepted")
    func acceptingSuggestionCommitsWithAcceptedSource() throws {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hel")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.insertSuggestion(Suggestion(text: "hello")), in: doc)
        let event = try #require(learnedEvent(in: effects))
        #expect(event.word == "hello")
        #expect(event.source == .accepted)
    }

    @Test("tapping the verbatim slot commits it with source .verbatim, not .accepted")
    func tappingVerbatimCommitsWithVerbatimSource() throws {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hel")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.insertSuggestion(Suggestion(text: "hel", isVerbatim: true)), in: doc)
        let event = try #require(learnedEvent(in: effects))
        #expect(event.word == "hel")
        #expect(event.source == .verbatim)
    }

    @Test("applying an autocorrect commits the corrected word with source .typed")
    func applyingAutocorrectCommitsCorrectedWord() throws {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        let event = try #require(learnedEvent(in: effects))
        #expect(event.word == "the")
        #expect(event.source == .typed)
    }

    @Test("reverting an autocorrect commits the original word with source .revert")
    func revertingAutocorrectCommitsOriginalWord() throws {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "teh")
        _ = processor.textDidChange(in: doc)
        processor.handle(.applyAutocorrect(corrected: "the", separator: " "), in: doc)
        let effects = processor.handle(.backspace, in: doc)
        let event = try #require(learnedEvent(in: effects))
        #expect(event.word == "teh")
        #expect(event.source == .revert)
    }

    @Test("a sensitive field (e.g. a password field) never emits .learn")
    func sensitiveFieldNeverCommits() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello", traits: FieldTraits(isSensitive: true))
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.space, in: doc)
        #expect(learnedEvent(in: effects) == nil)
    }

    @Test("inserting a clip never emits .learn")
    func insertingClipNeverCommits() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "")
        _ = processor.textDidChange(in: doc)
        let effects = processor.handle(.insertClip("hello world"), in: doc)
        #expect(learnedEvent(in: effects) == nil)
    }

    // MARK: - §6.7.8's word-shape learnability filters

    @Test("a word containing a digit is not learnable")
    func wordWithDigitIsNotLearnable() {
        #expect(CommitLearnability.isLearnable("hell0") == false)
    }

    @Test("a plain word is learnable")
    func plainWordIsLearnable() {
        #expect(CommitLearnability.isLearnable("hello"))
        #expect(CommitLearnability.isLearnable("سلام"))
    }

    @Test("a word longer than 32 graphemes is not learnable")
    func tooLongWordIsNotLearnable() {
        // Alternating characters, not a single repeated one, so this only
        // exercises the length rule, not the "3+ repeated letters" one.
        #expect(CommitLearnability.isLearnable(String(repeating: "ab", count: 16) + "a") == false) // 33 chars
        #expect(CommitLearnability.isLearnable(String(repeating: "ab", count: 16))) // exactly 32 chars
    }

    @Test("a URL-like or email-like token is not learnable")
    func urlOrEmailLikeIsNotLearnable() {
        #expect(CommitLearnability.isLearnable("user@example.com") == false)
        #expect(CommitLearnability.isLearnable("example.com") == false)
        #expect(CommitLearnability.isLearnable("https://example.com") == false)
        #expect(CommitLearnability.isLearnable("www.example.com") == false)
    }

    @Test("an emoji-only token is not learnable")
    func emojiOnlyIsNotLearnable() {
        #expect(CommitLearnability.isLearnable("😀") == false)
        #expect(CommitLearnability.isLearnable("😀😂") == false)
    }

    @Test("a token mixing Persian and Latin letters is not learnable")
    func mixedScriptIsNotLearnable() {
        #expect(CommitLearnability.isLearnable("سلamس") == false)
    }

    @Test("a token with 3+ identical letters in a row is not learnable")
    func threeOrMoreRepeatedLettersIsNotLearnable() {
        #expect(CommitLearnability.isLearnable("خیلیییی") == false)
        #expect(CommitLearnability.isLearnable("hellllo") == false)
        #expect(CommitLearnability.isLearnable("hello")) // just a doubled letter is fine
    }

    @Test("an empty token is not learnable")
    func emptyTokenIsNotLearnable() {
        #expect(CommitLearnability.isLearnable("") == false)
    }
}
