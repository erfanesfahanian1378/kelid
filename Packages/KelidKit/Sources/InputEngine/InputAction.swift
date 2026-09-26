import KeyboardLayout

/// Runtime key actions the controller sends to `InputProcessor` (§6.4.1).
///
/// Named `InputAction`, not `KeyAction` as §6.4.1 literally writes it:
/// `KeyboardLayout.KeyAction` (Phase 2) already owns that name for the
/// JSON layout schema's static `action` field, and `InputEngine` imports
/// `KeyboardLayout` — reusing the name here would collide.
public enum InputAction: Equatable, Sendable {
    /// Insert text, already case-mapped by the caller (shift is a *state*,
    /// not something `InputProcessor` reapplies to `text`).
    case character(String)
    case zwnj
    case space
    /// One step: touch-down triggers this once; hold-repeat and
    /// word-deletion are additional `.backspace`/`.deleteWordBackward`
    /// calls the touch layer sends on its own timer (§6.4.6, §6.4.12).
    case backspace
    case deleteWordBackward
    case returnKey
    /// A shift-key tap. `InputProcessor` (not the caller) tracks the
    /// double-tap-within-300ms-to-capsLock timing (§6.4.3), using its own
    /// `Clock`.
    case shift
    /// Directly force caps lock on/off (e.g. a long-press-shift gesture).
    case capsLock
    case page(KeyboardPage)
    case nextLanguage
    /// Globe tap — the controller calls `advanceToNextInputMode` itself;
    /// this only produces the matching `InputEffect` for anything else that
    /// needs to react (e.g. saving the last language).
    case nextInputMode
    case openPanel(Panel)
    /// Logical characters; positive = forward.
    case moveCursor(Int)
    case moveCursorWord(MoveDirection)
    case moveCursorLine(MoveDirection)
    case insertSuggestion(Suggestion)
    /// Already-resolved clip text (task 5.8) — like `.character`, this
    /// arrives pre-fetched: `InputProcessor` has no clipboard/database
    /// access of its own (rule 5.1.5-adjacent module boundary). Also used
    /// for `.pasteClipboard`'s actual insertion once the controller has
    /// read the pasteboard string.
    case insertClip(String)
    case copySelection
    case cutSelection
    case pasteClipboard
    case undo
    case dismissKeyboard
}

/// §6.4.9's cursor-move direction — named to avoid colliding with
/// `KeyboardLayout.Direction` (text/layout direction, a different concept).
public enum MoveDirection: Sendable, Equatable {
    case forward
    case backward
}

/// Which panel a `.openPanel` action opens (§4.5's `KeyboardState.mode`).
/// Real panel implementations arrive with their phases (clipboard: Phase 5,
/// emoji: Phase 12, resize: Phase 4); this enum exists now so
/// `InputProcessor` has something to name in its effects.
public enum Panel: Sendable, Equatable {
    case clipboard
    case emoji
    case edit
    case quickSettings
    case resize
}

/// Placeholder — Phase 7/8 give this real fields (text, source, score...).
public struct Suggestion: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
