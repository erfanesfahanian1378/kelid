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

    // MARK: - Suggestion accept (task 7.8, §6.4.8's word-replacement algorithm)

    /// Replaces the currently-typed word (`context.prefix`) with
    /// `suggestion.text`, then a space — §6.4.8's own 4-step algorithm,
    /// including its "verify what actually got deleted, restore any
    /// leftover combining mark/ZWNJ, bounded to 4 extra calls" resilience
    /// (the same pattern `insertSpace`'s ZWNJ handling already uses).
    func insertSuggestion(_ suggestion: Suggestion, in doc: TextDocument) -> [InputEffect] {
        let before = doc.contextBefore ?? shadowBuffer.contents
        let prefix = context.prefix
        for _ in prefix {
            doc.deleteBackward()
        }
        shadowBuffer.recordDeletion(count: prefix.count)

        let expectedRemainder = String(before.dropLast(prefix.count))
        var actualRemainder = doc.contextBefore ?? ""
        var extraAttempts = 0
        while actualRemainder != expectedRemainder, expectedRemainder.hasPrefix(actualRemainder), extraAttempts < 4 {
            // The host deleted more than `prefix` alone (a fused grapheme
            // cluster) — restore the extra trailing part.
            let overDeleted = String(expectedRemainder.dropFirst(actualRemainder.count))
            doc.insertText(overDeleted)
            shadowBuffer.recordInsertion(overDeleted)
            actualRemainder = doc.contextBefore ?? ""
            extraAttempts += 1
        }

        // What actually left the document, for a single-tap undo — computed
        // from the real before/after diff (like `deleteWordBackward`'s own
        // undo capture) rather than assumed to be exactly `prefix`, since
        // the leftover-cleanup loop above may have changed that.
        var actuallyDeleted = prefix
        if before.hasPrefix(actualRemainder), before.count > actualRemainder.count {
            actuallyDeleted = String(before.dropFirst(actualRemainder.count))
        }

        let replacement = suggestion.text + " "
        doc.insertText(replacement)
        shadowBuffer.recordInsertion(replacement)
        autoSpacePending = true
        pushUndo(.replaced(deleted: actuallyDeleted, inserted: replacement))

        var effects = resolveShiftAfterInsertion()
        effects.append(.requestSuggestions)
        return effects
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
        case let .replaced(deleted, inserted):
            for _ in inserted {
                doc.deleteBackward()
            }
            shadowBuffer.recordDeletion(count: inserted.count)
            doc.insertText(deleted)
            shadowBuffer.recordInsertion(deleted)
        }
    }
}
