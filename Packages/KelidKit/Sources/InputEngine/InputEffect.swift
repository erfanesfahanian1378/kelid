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
}

public enum FeedbackKind: Sendable, Equatable {
    case keyPress
    case specialKeyPress
    case error
}

/// Placeholder — Phase 9 gives this the real personal-learning fields.
public struct CommitEvent: Sendable, Equatable {
    public let word: String
    public let language: LanguageID
}

/// Placeholder — Phase 8 gives this the real before/after/reason fields.
public struct Autocorrection: Sendable, Equatable {
    public let original: String
    public let corrected: String
}

public enum ToastKind: Sendable, Equatable {
    case info(String)
}
