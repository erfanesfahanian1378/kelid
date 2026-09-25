import Foundation

/// The keyboard's only channel to the host text field (PLAN.md §6.4.8,
/// rule 5.1.5). `ProxyTextDocument` (keyboard target) wraps
/// `UITextDocumentProxy`; `MockTextDocument` (tests) is a fake host used to
/// exercise edge cases real hosts show (limited/nil/delayed context,
/// per-scalar deletion).
@MainActor
public protocol TextDocument: AnyObject {
    /// `documentContextBeforeInput` — often partial (§2.1 C6): only the
    /// current paragraph or sentence, sometimes `nil`.
    var contextBefore: String? { get }
    /// `documentContextAfterInput`.
    var contextAfter: String? { get }
    var selectedText: String? { get }
    var hasText: Bool { get }
    var traits: FieldTraits { get }
    /// Identifies the currently-focused document; changes when focus moves
    /// to a different field. Used to reset per-field state (shadow buffer,
    /// undo stack — later phases).
    var documentIdentifier: UUID { get }

    func insertText(_ text: String)
    func deleteBackward()
    /// Moves the cursor by `offset` characters (`UITextDocumentProxy`'s
    /// `adjustTextPosition(byCharacterOffset:)`); the keyboard cannot select
    /// text or otherwise reposition it (§2.1 C5).
    func adjustTextPosition(byCharacterOffset offset: Int)
}
