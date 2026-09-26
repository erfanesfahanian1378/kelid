import Foundation
import PersianText

/// Clip insert/Paste (task 5.8, §6.5.5), the edit panel's Copy/Cut/Undo
/// (§6.4.9) — split out of `InputProcessor.swift` itself purely to keep
/// that type's body under SwiftLint's `type_body_length`; behaviorally this
/// is still part of `InputProcessor`, just declared in a second file.
extension InputProcessor {
    /// Also used for `.pasteClipboard` once the controller has read the
    /// pasteboard string — both are "insert already-resolved text that
    /// isn't what the user typed," so they share smart-spacing and undo
    /// behavior. Pasted/inserted text is never learned (§6.5.5) — there's
    /// no learning implemented yet (Phase 9), so that's naturally already
    /// true rather than something to specifically suppress here.
    func insertClip(_ text: String, in doc: TextDocument) -> [InputEffect] {
        guard !text.isEmpty else { return [] }
        var inserted = text
        if settings.clipSmartSpacing,
           let beforeChar = (doc.contextBefore ?? shadowBuffer.contents).last, WordCharacters.isWordCharacter(beforeChar),
           let firstChar = text.first, WordCharacters.isWordCharacter(firstChar)
        {
            inserted = " " + text
        }
        doc.insertText(inserted)
        shadowBuffer.recordInsertion(inserted)
        pushUndo(.inserted(inserted))
        return resolveShiftAfterInsertion()
    }

    // MARK: - Edit panel: Copy/Cut/Paste (§6.4.9)

    /// `InputProcessor` has no pasteboard access (rule 5.1.5) — this only
    /// resolves `selectedText` and hands the actual write back as an
    /// effect for the controller to fulfill via `PasteboardClient`.
    /// Disabled state (no selection, or no Full Access) is the caller's
    /// concern for graying out the button; calling this with no selection
    /// is simply a no-op.
    func copySelection(in doc: TextDocument) -> [InputEffect] {
        guard let selected = doc.selectedText, !selected.isEmpty else { return [] }
        return [.requestCopyToPasteboard(selected)]
    }

    /// "Copy, then `deleteBackward()` once" (§6.4.9) — relies on the host's
    /// documented behavior that `deleteBackward()` removes the current
    /// selection as a whole when one exists, rather than one character
    /// before the cursor.
    func cutSelection(in doc: TextDocument) -> [InputEffect] {
        guard let selected = doc.selectedText, !selected.isEmpty else { return [] }
        doc.deleteBackward()
        shadowBuffer.recordDeletion(count: selected.count)
        pushUndo(.deleted(selected))
        return [.requestCopyToPasteboard(selected)]
    }

    // MARK: - Undo (§6.4.9, max 20 entries)

    func pushUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > Self.maxUndoEntries {
            undoStack.removeFirst()
        }
    }

    /// Reverses the most recent tracked entry. Best-effort like the rest of
    /// §6.4.8's host-resilience patterns: an inserted entry is undone by
    /// calling `deleteBackward()` once per `Character` in what was
    /// inserted, which is correct as long as the host's grapheme-cluster
    /// boundaries at undo time match what they were at insertion time
    /// (true for plain text; ZWNJ-heavy edge cases are the same known
    /// device-dependent territory §6.4.8 already flags elsewhere).
    func performUndo(in doc: TextDocument) {
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case let .inserted(text):
            for _ in text {
                doc.deleteBackward()
            }
            shadowBuffer.recordDeletion(count: text.count)
        case let .deleted(text):
            doc.insertText(text)
            shadowBuffer.recordInsertion(text)
        }
    }
}
