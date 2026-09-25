import Foundation
@testable import InputEngine
import KelidCore
import KelidSettings
import Testing

@Suite("InputProcessor")
@MainActor
struct InputProcessorTests {
    // MARK: - Shift / caps machine (§6.4.3)

    @Test("a single shift tap enters one-shot")
    func singleShiftTapEntersOneShot() {
        let processor = InputProcessor(settings: InputSettings(autoCapitalize: false), clock: TestClock())
        let doc = MockTextDocument()
        let effects = processor.handle(.shift, in: doc)
        #expect(processor.shiftState == .oneShot(auto: false))
        #expect(effects.contains(.shiftChanged(.oneShot(auto: false))))
    }

    @Test("typing a character after one-shot reverts shift to off")
    func characterAfterOneShotRevertsToOff() {
        let processor = InputProcessor(settings: InputSettings(autoCapitalize: false), clock: TestClock())
        let doc = MockTextDocument()
        processor.handle(.shift, in: doc)
        let effects = processor.handle(.character("A"), in: doc)
        #expect(processor.shiftState == .off)
        #expect(effects.contains(.shiftChanged(.off)))
    }

    @Test("two shift taps within 300ms enters caps lock; a third tap exits it")
    func doubleTapEntersCapsLock() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(autoCapitalize: false), clock: clock)
        let doc = MockTextDocument()
        processor.handle(.shift, in: doc)
        clock.advance(by: 0.1)
        processor.handle(.shift, in: doc)
        #expect(processor.shiftState == .capsLock)

        processor.handle(.shift, in: doc)
        #expect(processor.shiftState == .off)
    }

    @Test("two shift taps more than 300ms apart do not enter caps lock")
    func slowDoubleTapDoesNotEnterCapsLock() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(autoCapitalize: false), clock: clock)
        let doc = MockTextDocument()
        processor.handle(.shift, in: doc) // -> oneShot
        clock.advance(by: 0.5)
        processor.handle(.shift, in: doc) // oneShot -> off (too slow for capsLock)
        #expect(processor.shiftState == .off)
    }

    @Test("caps lock survives typing a character")
    func capsLockSurvivesTyping() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(autoCapitalize: false), clock: clock)
        let doc = MockTextDocument()
        processor.handle(.shift, in: doc)
        clock.advance(by: 0.1)
        processor.handle(.shift, in: doc)
        #expect(processor.shiftState == .capsLock)
        processor.handle(.character("A"), in: doc)
        #expect(processor.shiftState == .capsLock)
    }

    // MARK: - Auto-capitalization (§6.4.3)

    @Test("auto-cap .sentences fires at the start of text")
    func autoCapSentencesAtStart() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "", traits: FieldTraits(autocapitalization: .sentences))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .oneShot(auto: true))
    }

    @Test("auto-cap .sentences fires after '. '")
    func autoCapSentencesAfterPeriodSpace() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "Hello. ", traits: FieldTraits(autocapitalization: .sentences))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .oneShot(auto: true))
    }

    @Test("auto-cap .sentences does not fire mid-sentence")
    func autoCapSentencesNotMidSentence() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "Hello wor", traits: FieldTraits(autocapitalization: .sentences))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .off)
    }

    @Test("auto-cap .words fires after any space")
    func autoCapWordsAfterSpace() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ", traits: FieldTraits(autocapitalization: .words))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .oneShot(auto: true))
    }

    @Test("auto-cap .allCharacters forces caps lock")
    func autoCapAllCharactersForcesCapsLock() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "anything", traits: FieldTraits(autocapitalization: .allCharacters))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .capsLock)
    }

    @Test("auto-cap .none never fires")
    func autoCapNoneNeverFires() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "", traits: FieldTraits(autocapitalization: .none))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .off)
    }

    @Test("autoCapitalize setting off disables all auto-cap")
    func autoCapitalizeSettingOff() {
        let processor = InputProcessor(settings: InputSettings(autoCapitalize: false), clock: TestClock())
        let doc = MockTextDocument(text: "", traits: FieldTraits(autocapitalization: .sentences))
        processor.textDidChange(in: doc)
        #expect(processor.shiftState == .off)
    }

    // MARK: - Double-space period (§6.4.4)

    @Test("double-space after a letter inserts a period")
    func doubleSpaceAfterLetterInsertsPeriod() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "hello")
        processor.handle(.space, in: doc)
        clock.advance(by: 0.1)
        processor.handle(.space, in: doc)
        #expect(doc.contextBefore == "hello. ")
    }

    @Test("double-space after a digit inserts a period")
    func doubleSpaceAfterDigitInsertsPeriod() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "room42")
        processor.handle(.space, in: doc)
        clock.advance(by: 0.1)
        processor.handle(.space, in: doc)
        #expect(doc.contextBefore == "room42. ")
    }

    @Test("double-space after punctuation does not insert a period")
    func doubleSpaceAfterPunctuationDoesNotInsertPeriod() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "hello!")
        processor.handle(.space, in: doc)
        clock.advance(by: 0.1)
        processor.handle(.space, in: doc)
        #expect(doc.contextBefore == "hello!  ") // two plain spaces, no period inserted
    }

    @Test("double-space more than 0.6s apart does not insert a period")
    func doubleSpaceTooSlowDoesNotInsertPeriod() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "hello")
        processor.handle(.space, in: doc)
        clock.advance(by: 1.0)
        processor.handle(.space, in: doc)
        #expect(doc.contextBefore == "hello  ")
    }

    @Test("double-space period is a no-op when the setting is off")
    func doubleSpacePeriodSettingOff() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(doubleSpacePeriod: false), clock: clock)
        let doc = MockTextDocument(text: "hello")
        processor.handle(.space, in: doc)
        clock.advance(by: 0.1)
        processor.handle(.space, in: doc)
        #expect(doc.contextBefore == "hello  ")
    }

    // MARK: - Smart punctuation spacing (§6.4.4)

    @Test("a pending auto-space is removed when punctuation is typed next")
    func autoSpaceRemovedBeforePunctuation() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ")
        processor.markAutoSpacePending()
        processor.handle(.character(","), in: doc)
        #expect(doc.contextBefore == "hello,")
    }

    @Test("smart punctuation spacing does nothing when there's no pending auto-space")
    func noAutoSpaceNoRemoval() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ")
        processor.handle(.character(","), in: doc)
        #expect(doc.contextBefore == "hello ,")
    }

    @Test("the auto-space flag is cleared by any other action")
    func autoSpaceFlagClearedByOtherActions() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello ")
        processor.markAutoSpacePending()
        processor.handle(.character("x"), in: doc) // not punctuation — clears the flag, no removal
        #expect(doc.contextBefore == "hello x")
        processor.handle(.character(","), in: doc) // flag already cleared, no removal
        #expect(doc.contextBefore == "hello x,")
    }

    // MARK: - ZWNJ rules (§6.4.5)

    @Test("ZWNJ is ignored at the start of a word")
    func zwnjIgnoredAtWordStart() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "")
        processor.handle(.zwnj, in: doc)
        #expect(doc.contextBefore == "")
    }

    @Test("ZWNJ is ignored right after a space")
    func zwnjIgnoredAfterSpace() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "می ")
        processor.handle(.zwnj, in: doc)
        #expect(doc.contextBefore == "می ")
    }

    @Test("a second ZWNJ right after another is ignored")
    func doubleZWNJIgnored() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "می")
        processor.handle(.zwnj, in: doc) // first one is legal (after a word char)
        processor.handle(.zwnj, in: doc) // second one, right after the first, is ignored
        #expect(doc.contextBefore == "می\u{200C}")
    }

    @Test("ZWNJ after a normal word character is inserted")
    func zwnjAfterWordCharacterInserted() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "می")
        processor.handle(.zwnj, in: doc)
        #expect(doc.contextBefore == "می\u{200C}")
    }

    @Test("space right after a ZWNJ replaces it with a space")
    func spaceAfterZWNJReplacesIt() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "می\u{200C}")
        processor.handle(.space, in: doc)
        #expect(doc.contextBefore == "می ")
    }

    // MARK: - Backspace hold timing (§6.4.6, with TestClock)

    @Test("backspace hold does not repeat before 500ms")
    func backspaceHoldDoesNotRepeatBeforeFirstDelay() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "hello world")
        processor.beginBackspaceHold()
        clock.advance(by: 0.4)
        #expect(processor.tickBackspaceHold(in: doc) == false)
        #expect(doc.contextBefore == "hello world")
    }

    @Test("backspace hold repeats at 500ms, then every 80ms at normal speed")
    func backspaceHoldRepeatsAtNormalSpeed() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(backspaceRepeat: .normal), clock: clock)
        let doc = MockTextDocument(text: "hello world")
        processor.beginBackspaceHold()
        clock.advance(by: 0.5)
        #expect(processor.tickBackspaceHold(in: doc) == true)
        #expect(doc.contextBefore == "hello worl")

        clock.advance(by: 0.08)
        #expect(processor.tickBackspaceHold(in: doc) == true)
        #expect(doc.contextBefore == "hello wor")
    }

    @Test("backspace hold switches to whole-word deletion every 200ms after 2s")
    func backspaceHoldSwitchesToWordModeAfter2s() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "hello world")
        processor.beginBackspaceHold()
        clock.advance(by: 2.0)
        #expect(processor.tickBackspaceHold(in: doc) == true)
        // Whole trailing word "world" deleted in one tick, not just one character.
        #expect(doc.contextBefore == "hello ")
    }

    @Test("ending the hold stops further repeats")
    func endingHoldStopsRepeats() {
        let clock = TestClock()
        let processor = InputProcessor(settings: InputSettings(), clock: clock)
        let doc = MockTextDocument(text: "hello world")
        processor.beginBackspaceHold()
        processor.endBackspaceHold()
        clock.advance(by: 1.0)
        #expect(processor.tickBackspaceHold(in: doc) == false)
        #expect(doc.contextBefore == "hello world")
    }

    // MARK: - Word deletion boundaries (§6.4.6/§6.6.3)

    @Test("deleteWordBackward removes a Persian ZWNJ compound as one word")
    func deleteWordBackwardRemovesZWNJCompound() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "سلام می\u{200C}خواهم")
        processor.handle(.deleteWordBackward, in: doc)
        #expect(doc.contextBefore == "سلام ")
    }

    @Test("deleteWordBackward keeps an English contraction's apostrophe as one word")
    func deleteWordBackwardKeepsContractionTogether() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "I don't")
        processor.handle(.deleteWordBackward, in: doc)
        #expect(doc.contextBefore == "I ")
    }

    @Test("deleteWordBackward skips trailing spaces before deleting the word")
    func deleteWordBackwardSkipsTrailingSpaces() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello world   ")
        processor.handle(.deleteWordBackward, in: doc)
        #expect(doc.contextBefore == "hello ")
    }

    // MARK: - Return (§6.4.1)

    @Test("return inserts a newline")
    func returnInsertsNewline() {
        let processor = InputProcessor(settings: InputSettings(), clock: TestClock())
        let doc = MockTextDocument(text: "hello")
        processor.handle(.returnKey, in: doc)
        #expect(doc.contextBefore == "hello\n")
    }

    // MARK: - Language switching (§6.4.7)

    @Test("nextLanguage cycles through the enabled languages and wraps around")
    func nextLanguageCycles() {
        let processor = InputProcessor(settings: InputSettings(enabledLanguages: [.fa, .en]), clock: TestClock(), initialLanguage: .fa)
        let doc = MockTextDocument()
        let effects1 = processor.handle(.nextLanguage, in: doc)
        #expect(effects1.contains(.languageChanged(.en)))
        let effects2 = processor.handle(.nextLanguage, in: doc)
        #expect(effects2.contains(.languageChanged(.fa)))
    }

    @Test("nextLanguage does nothing with only one enabled language")
    func nextLanguageNoOpWithOneLanguage() {
        let processor = InputProcessor(settings: InputSettings(enabledLanguages: [.fa]), clock: TestClock(), initialLanguage: .fa)
        let doc = MockTextDocument()
        let effects = processor.handle(.nextLanguage, in: doc)
        #expect(!effects.contains {
            if case .languageChanged = $0 {
                true
            } else {
                false
            }
        })
    }
}

@Suite("FieldRequirements")
struct FieldRequirementsTests {
    @Test("email and URL fields force English")
    func emailAndURLForceEnglish() {
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .emailAddress)).forcedLanguage == .en)
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .url)).forcedLanguage == .en)
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .asciiCapable)).forcedLanguage == .en)
    }

    @Test("plain default fields do not force a language")
    func defaultFieldDoesNotForceLanguage() {
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .default)).forcedLanguage == nil)
    }

    @Test("number pads force the numpad page")
    func numberPadsForceNumpadPage() {
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .numberPad)).forcedPage == .numpad)
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .decimalPad)).forcedPage == .numpad)
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .asciiCapableNumberPad)).forcedPage == .numpad)
    }

    @Test("numbersAndPunctuation forces symbols1")
    func numbersAndPunctuationForcesSymbols1() {
        #expect(FieldRequirements.resolve(for: FieldTraits(keyboardType: .numbersAndPunctuation)).forcedPage == .symbols1)
    }
}
