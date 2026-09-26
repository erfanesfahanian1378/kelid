import Foundation
import KelidCore
import KeyboardLayout
import PersianText

/// Characters that clear a pending auto-space when typed right after it
/// (§6.4.4's smart punctuation spacing).
private let smartPunctuationTriggers: Set<Character> = [".", ",", "!", "?", ";", ":", "،", "؛", "؟", ")", "»", "…"]

/// Sentence-ending punctuation (§6.4.3/§6.6.3). Not `private`: shared with
/// `InputProcessor+Context.swift` (a separate file, split out to keep
/// `InputProcessor`'s body under SwiftLint's `type_body_length`) — `private`
/// at file scope wouldn't be visible there.
let sentenceEndCharacters: Set<Character> = [".", "!", "?", "؟", "…"]

/// Implements §6.4.2's contract: character insertion with shift mapping,
/// page switching, the shift/caps machine and auto-cap (§6.4.3), space and
/// double-space period, smart punctuation spacing (§6.4.4), ZWNJ rules
/// (§6.4.5), backspace (§6.4.6 — the tap only; hold/word/swipe timing is
/// driven externally by repeated `.backspace`/`.deleteWordBackward` calls,
/// §6.4.12), return, `textDidChange` and the shadow buffer (§6.4.8).
///
/// Autocorrect-revert (§6.4.6's "previous action was an autocorrection")
/// and suggestion/clip insertion are no-ops for now — those land with
/// Phase 8 (autocorrect) and Phase 5/7 (clips/suggestions) respectively.
@MainActor
public final class InputProcessor {
    // `internal` (not `private`), not for external use but because
    // `InputProcessor+BackspaceHold.swift` (a separate file, split out to
    // keep this type's body under SwiftLint's `type_body_length`) needs
    // them — `private` in Swift is file-scoped, even across extensions of
    // the same type.
    var settings: InputSettings
    let clock: Clock

    public private(set) var shiftState: ShiftState = .off
    private var lastManualShiftTapAt: Date?
    private var lastSpaceTapAt: Date?
    private var autoSpacePending = false
    /// Not `private`: `InputProcessor+Context.swift` reads this too.
    var currentLanguage: LanguageID
    /// `internal` (not `private`): `InputProcessor+EditActions.swift` (a
    /// separate file, split out to keep this type's body under SwiftLint's
    /// `type_body_length`) needs these — `private` is file-scoped in Swift,
    /// even across extensions of the same type.
    var shadowBuffer = ShadowBuffer()

    public private(set) var context: TypingContext = .empty

    /// Whether `.undo` would currently do anything — the edit panel's own
    /// enabled/disabled state (§6.4.9).
    public var hasUndo: Bool {
        !undoStack.isEmpty
    }

    /// §6.4.9's undo stack (max 20) — scoped to word deletions and clip
    /// inserts (including paste), the two operations explicitly costly
    /// enough to warrant a dedicated Undo button; ordinary character-by-
    /// character typing doesn't push entries (backspace already reverses
    /// that far more directly than an undo stack would).
    enum UndoEntry {
        case inserted(String)
        case deleted(String)
    }

    var undoStack: [UndoEntry] = []
    private var undoTrackedDocumentIdentifier: UUID?
    static let maxUndoEntries = 20

    private static let doubleTapCapsLockWindow: TimeInterval = 0.3
    private static let doubleSpacePeriodWindow: TimeInterval = 0.6

    public init(settings: InputSettings, clock: Clock, initialLanguage: LanguageID = .fa) {
        self.settings = settings
        self.clock = clock
        currentLanguage = initialLanguage
    }

    public func updateSettings(_ settings: InputSettings) {
        self.settings = settings
    }

    // MARK: - Main entry point

    @discardableResult
    public func handle(_ action: InputAction, in doc: TextDocument) -> [InputEffect] {
        shadowBuffer.noteDocument(doc.documentIdentifier)
        if undoTrackedDocumentIdentifier != doc.documentIdentifier {
            undoTrackedDocumentIdentifier = doc.documentIdentifier
            undoStack.removeAll()
        }

        var effects: [InputEffect] = []
        var clearsAutoSpace = true

        switch action {
        case let .character(text):
            effects += insertCharacter(text, in: doc)

        case .zwnj:
            effects += insertZWNJ(in: doc)

        case .space:
            effects += insertSpace(in: doc)
            clearsAutoSpace = false // insertSpace manages the flag itself

        case .backspace:
            effects += performBackspace(in: doc)

        case .deleteWordBackward:
            effects += deleteWordBackward(in: doc)

        case .returnKey:
            doc.insertText("\n")
            shadowBuffer.recordInsertion("\n")
            effects += resolveShiftAfterInsertion()

        case .shift:
            effects += handleShiftTap()

        case .capsLock:
            shiftState = shiftState == .capsLock ? .off : .capsLock
            effects.append(.shiftChanged(shiftState))

        case let .page(page):
            effects.append(.pageChanged(page))

        case .nextLanguage:
            effects += advanceLanguage(enabledLanguages: settings.enabledLanguages)

        case .nextInputMode:
            effects.append(.nextInputMode)

        case let .openPanel(panel):
            effects.append(.openPanel(panel))

        case let .moveCursor(offset):
            doc.adjustTextPosition(byCharacterOffset: offset)

        case let .moveCursorWord(direction):
            doc.adjustTextPosition(byCharacterOffset: wordBoundaryOffset(direction: direction, in: doc))

        case let .moveCursorLine(direction):
            doc.adjustTextPosition(byCharacterOffset: lineBoundaryOffset(direction: direction, in: doc))

        case .insertSuggestion:
            // Phase 7-8: not yet implemented.
            break

        case let .insertClip(text):
            effects += insertClip(text, in: doc)

        case .copySelection:
            effects += copySelection(in: doc)

        case .cutSelection:
            effects += cutSelection(in: doc)

        case .pasteClipboard:
            effects.append(.requestPasteFromPasteboard)

        case .undo:
            performUndo(in: doc)

        case .dismissKeyboard:
            effects.append(.dismissKeyboard)
        }

        if clearsAutoSpace, action != .backspace {
            autoSpacePending = false
        }

        context = computeContext(doc: doc)
        effects += recomputeAutoCapitalization()
        return effects
    }

    @discardableResult
    public func textDidChange(in doc: TextDocument) -> [InputEffect] {
        shadowBuffer.noteDocument(doc.documentIdentifier)
        shadowBuffer.verify(against: doc.contextBefore)
        context = computeContext(doc: doc)
        return recomputeAutoCapitalization()
    }

    // MARK: - Character insertion (§6.4.4 smart punctuation)

    private func insertCharacter(_ text: String, in doc: TextDocument) -> [InputEffect] {
        if autoSpacePending, settings.smartPunctuationSpacing, text.count == 1, let char = text.first,
           smartPunctuationTriggers.contains(char)
        {
            doc.deleteBackward()
            shadowBuffer.recordDeletion()
        }
        doc.insertText(text)
        shadowBuffer.recordInsertion(text)
        var effects = resolveShiftAfterInsertion()
        effects.append(.requestSuggestions)
        return effects
    }

    /// `internal`, not `private` — `InputProcessor+EditActions.swift` (a
    /// separate file) calls this too.
    func resolveShiftAfterInsertion() -> [InputEffect] {
        guard case .oneShot = shiftState else { return [] }
        shiftState = .off
        return [.shiftChanged(.off)]
    }

    // Clip insert/Paste (task 5.8, §6.5.5), the edit panel's Copy/Cut
    // (§6.4.9), and Undo are implemented in `InputProcessor+EditActions.swift`.

    // MARK: - ZWNJ (§6.4.5)

    private func insertZWNJ(in doc: TextDocument) -> [InputEffect] {
        let before = doc.contextBefore ?? shadowBuffer.contents
        let lastScalar = before.unicodeScalars.last

        let atWordStart = before.isEmpty || !(before.last.map(WordCharacters.isWordCharacter) ?? false)
        let afterSpace = lastScalar == " "
        let afterZWNJ = lastScalar == "\u{200C}"

        guard !atWordStart, !afterSpace, !afterZWNJ else {
            return []
        }
        doc.insertText("\u{200C}")
        shadowBuffer.recordInsertion("\u{200C}")
        return []
    }

    // MARK: - Space, double-space period (§6.4.4)

    private func insertSpace(in doc: TextDocument) -> [InputEffect] {
        let now = clock.now()
        let before = doc.contextBefore ?? shadowBuffer.contents

        // "Space right after a ZWNJ replaces the ZWNJ with a space." ZWNJ
        // typically *fuses* with the preceding letter into one grapheme
        // cluster (confirmed empirically — see WordCharacters), and hosts
        // vary on whether a single deleteBackward() removes just the ZWNJ
        // scalar or the whole fused cluster (§6.4.8's own documented
        // uncertainty, task 3.16's device check). Rather than assume either
        // way, verify what actually got removed and restore any letter that
        // came along with it — the same resilience §6.4.8 prescribes for
        // word replacement.
        if before.unicodeScalars.last == "\u{200C}" {
            let expectedRemainder = String(String.UnicodeScalarView(before.unicodeScalars.dropLast()))
            doc.deleteBackward()
            let actualRemainder = doc.contextBefore ?? ""
            if actualRemainder != expectedRemainder, expectedRemainder.hasPrefix(actualRemainder) {
                // The host's deleteBackward() removed more than the ZWNJ
                // alone (the fused cluster) — restore the trailing part of
                // `expectedRemainder` that came along with it.
                let overDeleted = String(expectedRemainder.dropFirst(actualRemainder.count))
                doc.insertText(overDeleted)
                shadowBuffer.recordInsertion(overDeleted)
            }
            shadowBuffer.recordDeletion()
            doc.insertText(" ")
            shadowBuffer.recordInsertion(" ")
            autoSpacePending = false
            lastSpaceTapAt = now
            return [.requestSuggestions]
        }

        // Double-space period: previous action was a space tap within 0.6s,
        // and the text before the cursor (before *this* space) ends with a
        // letter/digit then a space.
        if settings.doubleSpacePeriod,
           let lastSpaceTapAt, now.timeIntervalSince(lastSpaceTapAt) <= Self.doubleSpacePeriodWindow,
           endsWithLetterOrDigitThenSpace(before)
        {
            doc.deleteBackward()
            shadowBuffer.recordDeletion()
            doc.insertText(". ")
            shadowBuffer.recordInsertion(". ")
            autoSpacePending = false
            self.lastSpaceTapAt = nil
            return [.requestSuggestions]
        }

        doc.insertText(" ")
        shadowBuffer.recordInsertion(" ")
        autoSpacePending = false
        lastSpaceTapAt = now
        return [.requestSuggestions]
    }

    private func endsWithLetterOrDigitThenSpace(_ text: String) -> Bool {
        guard text.hasSuffix(" ") else { return false }
        let withoutSpace = text.dropLast()
        guard let last = withoutSpace.last else { return false }
        return WordCharacters.isWordCharacter(last) && last != "\u{200C}" && last != "\u{200D}"
    }

    /// Marks that the keyboard itself just inserted a trailing space the
    /// user didn't type (suggestion accept, clip insert, autocorrect) — a
    /// later phase calls this; smart punctuation spacing then knows to
    /// remove it if the next character typed is punctuation.
    public func markAutoSpacePending() {
        autoSpacePending = true
    }

    // MARK: - Backspace (§6.4.6 — tap only; hold/word/swipe timing is in

    // `InputProcessor+BackspaceHold.swift`, split out to keep this type's
    // body under SwiftLint's `type_body_length` — hence `performBackspace`/
    // `deleteWordBackward` below being `internal`, not `private`: `private`
    // is file-scoped in Swift, and that extension lives in a different file.)

    func performBackspace(in doc: TextDocument) -> [InputEffect] {
        doc.deleteBackward()
        shadowBuffer.recordDeletion()
        return []
    }

    // Also `internal`, not `private`, for the same cross-file reason as
    // `settings`/`clock` above — these back `tickBackspaceHold` in
    // `InputProcessor+BackspaceHold.swift`.
    var backspaceHoldStartedAt: Date?
    var lastBackspaceHoldFireAt: Date?
    static let backspaceFirstRepeatDelay: TimeInterval = 0.5
    static let backspaceWordModeThreshold: TimeInterval = 2.0
    static let backspaceWordModeInterval: TimeInterval = 0.2

    func deleteWordBackward(in doc: TextDocument) -> [InputEffect] {
        let before = doc.contextBefore ?? shadowBuffer.contents
        let count = wordDeletionCount(before)
        for _ in 0 ..< count {
            doc.deleteBackward()
        }
        shadowBuffer.recordDeletion(count: count)

        // Capture exactly what left the document for Undo (§6.4.9), via the
        // same before/after diff `KeyboardController`'s backspace-swipe
        // restore (Phase 4) uses — robust to the host's `deleteBackward()`
        // granularity rather than assuming `count` characters were removed.
        let after = doc.contextBefore ?? ""
        if before.hasPrefix(after), before.count > after.count {
            pushUndo(.deleted(String(before.dropFirst(after.count))))
        }
        return []
    }

    /// §6.4.6: "skip trailing spaces, then delete back to the previous
    /// non-word character" (§6.6.3 word characters).
    ///
    /// Walks a shrinking *index* into the original, unmodified `text`
    /// rather than popping characters off a copy: the apostrophe-between-
    /// letters check (`isWordCharacter(at:in:)`) needs to see the letter
    /// that comes *after* the apostrophe, which a shrinking copy would
    /// already have removed by the time the walk reaches it.
    private func wordDeletionCount(_ text: String) -> Int {
        var end = text.endIndex
        var count = 0
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous] == " " else { break }
            end = previous
            count += 1
        }
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard WordCharacters.isWordCharacter(at: previous, in: text) else { break }
            end = previous
            count += 1
        }
        return count
    }

    // MARK: - Cursor word/line movement (§6.4.9)

    private func wordBoundaryOffset(direction: MoveDirection, in doc: TextDocument) -> Int {
        switch direction {
        case .backward:
            let before = doc.contextBefore ?? shadowBuffer.contents
            return -wordDeletionCount(before)
        case .forward:
            guard let after = doc.contextAfter else { return 0 }
            var start = after.startIndex
            var count = 0
            while start < after.endIndex, after[start] == " " {
                start = after.index(after: start)
                count += 1
            }
            while start < after.endIndex, WordCharacters.isWordCharacter(at: start, in: after) {
                start = after.index(after: start)
                count += 1
            }
            return count
        }
    }

    private func lineBoundaryOffset(direction: MoveDirection, in doc: TextDocument) -> Int {
        switch direction {
        case .backward:
            let before = doc.contextBefore ?? shadowBuffer.contents
            if let lastNewline = before.lastIndex(of: "\n") {
                return -before.distance(from: before.index(after: lastNewline), to: before.endIndex)
            }
            return -before.count
        case .forward:
            guard let after = doc.contextAfter else { return 0 }
            if let nextNewline = after.firstIndex(of: "\n") {
                return after.distance(from: after.startIndex, to: nextNewline)
            }
            return after.count
        }
    }

    // MARK: - Shift/caps (§6.4.3)

    private func handleShiftTap() -> [InputEffect] {
        let now = clock.now()
        switch shiftState {
        case .off:
            shiftState = .oneShot(auto: false)
        case .oneShot:
            if let lastManualShiftTapAt, now.timeIntervalSince(lastManualShiftTapAt) <= Self.doubleTapCapsLockWindow {
                shiftState = .capsLock
            } else {
                shiftState = .off
            }
        case .capsLock:
            shiftState = .off
        }
        lastManualShiftTapAt = now
        return [.shiftChanged(shiftState)]
    }

    /// §6.4.3: recomputed after every action and on `textDidChange`. Only
    /// ever *sets* a one-shot when currently `.off` — never overrides an
    /// active manual shift/caps lock the user just set.
    private func recomputeAutoCapitalization() -> [InputEffect] {
        guard settings.autoCapitalize else { return [] }

        switch context.traits.autocapitalization {
        case .allCharacters:
            guard shiftState != .capsLock else { return [] }
            shiftState = .capsLock
            return [.shiftChanged(.capsLock)]

        case .none:
            return []

        case .sentences:
            guard shiftState == .off, context.isSentenceStart else { return [] }
            shiftState = .oneShot(auto: true)
            return [.shiftChanged(shiftState)]

        case .words:
            guard shiftState == .off else { return [] }
            let atWordStart = context.prefix.isEmpty
            guard atWordStart else { return [] }
            shiftState = .oneShot(auto: true)
            return [.shiftChanged(shiftState)]
        }
    }

    // MARK: - Language (§6.4.7)

    private func advanceLanguage(enabledLanguages: [LanguageID]) -> [InputEffect] {
        guard enabledLanguages.count > 1, let index = enabledLanguages.firstIndex(of: currentLanguage) else {
            return []
        }
        let nextIndex = enabledLanguages.index(after: index) == enabledLanguages.endIndex ? enabledLanguages.startIndex : enabledLanguages
            .index(after: index)
        currentLanguage = enabledLanguages[nextIndex]
        return [.languageChanged(currentLanguage)]
    }

    // Context computation (task 3.5, §6.4.2) is implemented in
    // `InputProcessor+Context.swift`.
}
