import KelidCore
import KeyboardLayout

/// §6.4.3's shift/caps state machine.
public enum ShiftState: Sendable, Equatable {
    case off
    /// The next letter is uppercase, then reverts to `.off`. `auto` marks a
    /// shift the auto-capitalization logic set (vs. a manual tap) — both
    /// behave the same for casing, but only a manual tap counts toward the
    /// double-tap-to-capsLock timing (§6.4.3).
    case oneShot(auto: Bool)
    case capsLock
}

/// What changed as a result of handling an `InputAction` (§6.4.2). The
/// controller applies these to `KeyboardState`/`KeyGridView`; `InputProcessor`
/// itself never touches UI.
public enum InputEffect: Equatable, Sendable {
    case shiftChanged(ShiftState)
    case pageChanged(KeyboardPage)
    case languageChanged(LanguageID)
    case requestSuggestions
    case feedback(FeedbackKind)
    case learn(CommitEvent)
    case autocorrected(Autocorrection)
    case openPanel(Panel)
    case nextInputMode
    case dismissKeyboard
    case toast(ToastKind)
    /// §6.4.9's Copy/Cut: the text to write to the system pasteboard.
    /// `InputProcessor` has no pasteboard access of its own (rule 5.1.5) —
    /// the controller fulfills this via `PasteboardClient` and stores a
    /// `.keyboard`-source clip.
    case requestCopyToPasteboard(String)
    /// §6.4.9's Paste: the controller reads the pasteboard string (a
    /// user-initiated read, §2.1 C3) and feeds it back via
    /// `.insertClip(text)` — `InputProcessor` can't read the pasteboard
    /// itself.
    case requestPasteFromPasteboard
}

public enum FeedbackKind: Sendable, Equatable {
    case keyPress
    case specialKeyPress
    case error
}

/// §6.7.8's commit source tags — `PredictionEngine`'s own
/// `UserModelCommitSource` has more cases (`.importText`/`.contacts`/
/// `.manual`, none of which a live typing session ever produces); this is
/// `InputEngine`'s narrower "what real-time typing can commit" subset
/// (§4.2: `InputEngine` doesn't depend on `PredictionEngine`). `KeyboardUI`
/// converts between the two when forwarding a `.learn` effect.
public enum CommitSource: String, Sendable, Equatable {
    /// A space/punctuation/return committed the typed word as-is, or
    /// autocorrect silently committed its corrected word (§6.7.8: commit
    /// triggers include "autocorrect (the final word)" — not called out
    /// with its own increment weight in §6.7.6's list, so it's treated the
    /// same as an ordinary typed-and-committed word).
    case typed
    /// A non-verbatim suggestion bar slot was tapped.
    case accepted
    /// The verbatim slot specifically was tapped (§6.7.6: 2.0, not 1.0).
    case verbatim
    /// A backspace right after an autocorrect reverted it — the *original*
    /// typed word is learned (§6.7.6: 2.0).
    case revert
}

/// §6.7.8's commit event — task 9.3. `previousWords` is the same
/// sentence-scoped, up-to-2-words `TypingContext.previousWords` shape,
/// captured *before* the committing action ran (so it reflects the
/// sentence context the committed word actually appeared in).
public struct CommitEvent: Sendable, Equatable {
    public let word: String
    public let language: LanguageID
    public let source: CommitSource
    public let previousWords: [String]
    /// Set only when `source == .revert`: the autocorrected word the user
    /// just rejected by backspacing it away — §6.7.8: "Reverting an
    /// autocorrect adds the pair `(typed → corrected)` to
    /// `blockedCorrections`," which needs both halves of the pair, not just
    /// the original `word` this event already carries.
    public let revertedCorrection: String?

    public init(word: String, language: LanguageID, source: CommitSource, previousWords: [String], revertedCorrection: String? = nil) {
        self.word = word
        self.language = language
        self.source = source
        self.previousWords = previousWords
        self.revertedCorrection = revertedCorrection
    }
}

/// §6.7.9's autocorrect event (task 8.6) — `separator` is what was typed to
/// trigger it (space, return, or a punctuation character), needed so a
/// revert (§6.4.6/§6.7.9 rule 6) knows exactly how much to delete.
public struct Autocorrection: Sendable, Equatable {
    public let original: String
    public let corrected: String
    public let separator: String

    public init(original: String, corrected: String, separator: String) {
        self.original = original
        self.corrected = corrected
        self.separator = separator
    }
}

public enum ToastKind: Sendable, Equatable {
    case info(String)
}
