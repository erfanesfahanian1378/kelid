import Foundation
@testable import InputEngine

/// Fake host for `TextDocument`, with the host-imitation switches from
/// PLAN.md §6.4.8. Lives directly in this test target (the plan allows
/// either that or a separate `InputEngineTestSupport` library target) —
/// promote it to its own target if a later phase's test target also needs
/// it.
@MainActor
final class MockTextDocument: TextDocument {
    enum DeletionGranularity {
        /// Deletes one `Character` (extended grapheme cluster) per call —
        /// what most real hosts do.
        case grapheme
        /// Deletes one Unicode scalar per call — some hosts do this for
        /// combining marks (e.g. a standalone diacritic gets left behind
        /// only partially removed). See PLAN.md §6.4.8's device check.
        case scalar
    }

    enum ContextLimit {
        case unlimited
        case characters(Int)
        case currentParagraphOnly
    }

    private(set) var buffer: String
    private(set) var cursorIndex: String.Index
    private(set) var selectionRange: Range<String.Index>?
    let documentIdentifier = UUID()

    var traits: FieldTraits
    var contextLimit: ContextLimit = .unlimited
    var contextIsNil = false
    var deletionGranularity: DeletionGranularity = .grapheme
    /// When true, `contextBefore` keeps returning its pre-mutation value
    /// until `settleContext()` is called — simulating a host where the
    /// context lags right after a cursor move (§6.4.8).
    var contextDelay = false
    private var frozenContextBefore: String?

    init(text: String = "", cursorAt index: String.Index? = nil, traits: FieldTraits = .default) {
        buffer = text
        cursorIndex = index ?? text.endIndex
        self.traits = traits
    }

    var hasText: Bool {
        !buffer.isEmpty
    }

    var selectedText: String? {
        selectionRange.map { String(buffer[$0]) }
    }

    var contextBefore: String? {
        if contextIsNil {
            return nil
        }
        if contextDelay {
            return frozenContextBefore ?? rawContextBefore()
        }
        return rawContextBefore()
    }

    var contextAfter: String? {
        contextIsNil ? nil : rawContextAfter()
    }

    // Every mutation below recomputes `cursorIndex` from a *character (or
    // scalar) offset* taken before mutating `buffer`, rather than reusing an
    // index computed pre-mutation directly — Swift's `String.Index` is not
    // guaranteed valid across a mutation of the string it was derived from
    // even when the position it names is outside the edited range (e.g.
    // `buffer.removeSubrange(previous..<cursorIndex); cursorIndex = previous`
    // traps with "String index range is out of bounds" once a fused
    // grapheme cluster like a ZWNJ-joined letter is involved). Recomputing
    // via `index(_:offsetBy:)` from a freshly-taken `startIndex` sidesteps
    // this entirely.

    func insertText(_ text: String) {
        freezeContextIfNeeded()
        // Scalar offsets, not Character offsets: inserted text can *fuse*
        // with the existing character right before the insertion point
        // (e.g. inserting ZWNJ right after a letter joins them into one
        // grapheme cluster), so "old character count + inserted character
        // count" does not reliably predict the new cursor's character
        // offset — the total can grow by *fewer* graphemes than characters
        // inserted. Scalar counts aren't affected by grapheme fusion.
        var scalarOffset: Int
        if let selection = selectionRange {
            scalarOffset = buffer.unicodeScalars.distance(from: buffer.unicodeScalars.startIndex, to: selection.lowerBound)
            buffer.removeSubrange(selection)
            selectionRange = nil
        } else {
            scalarOffset = buffer.unicodeScalars.distance(from: buffer.unicodeScalars.startIndex, to: cursorIndex)
        }
        let insertionIndex = buffer.unicodeScalars.index(buffer.unicodeScalars.startIndex, offsetBy: scalarOffset)
        buffer.insert(contentsOf: text, at: insertionIndex)
        let newScalarOffset = scalarOffset + text.unicodeScalars.count
        cursorIndex = buffer.unicodeScalars.index(buffer.unicodeScalars.startIndex, offsetBy: newScalarOffset)
    }

    func deleteBackward() {
        freezeContextIfNeeded()
        if let selection = selectionRange {
            let offset = buffer.unicodeScalars.distance(from: buffer.unicodeScalars.startIndex, to: selection.lowerBound)
            buffer.removeSubrange(selection)
            cursorIndex = buffer.unicodeScalars.index(buffer.unicodeScalars.startIndex, offsetBy: offset)
            selectionRange = nil
            return
        }
        guard cursorIndex > buffer.startIndex else { return }
        switch deletionGranularity {
        case .grapheme:
            let previous = buffer.index(before: cursorIndex)
            let offset = buffer.unicodeScalars.distance(from: buffer.unicodeScalars.startIndex, to: previous)
            buffer.removeSubrange(previous ..< cursorIndex)
            cursorIndex = buffer.unicodeScalars.index(buffer.unicodeScalars.startIndex, offsetBy: offset)
        case .scalar:
            // A grapheme boundary is always also a scalar boundary, so
            // `cursorIndex` is valid to index directly into `.unicodeScalars`.
            let previous = buffer.unicodeScalars.index(before: cursorIndex)
            let offset = buffer.unicodeScalars.distance(from: buffer.unicodeScalars.startIndex, to: previous)
            buffer.unicodeScalars.removeSubrange(previous ..< cursorIndex)
            cursorIndex = buffer.unicodeScalars.index(buffer.unicodeScalars.startIndex, offsetBy: offset)
        }
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        freezeContextIfNeeded()
        if offset >= 0 {
            cursorIndex = buffer.index(cursorIndex, offsetBy: offset, limitedBy: buffer.endIndex) ?? buffer.endIndex
        } else {
            cursorIndex = buffer.index(cursorIndex, offsetBy: offset, limitedBy: buffer.startIndex) ?? buffer.startIndex
        }
        selectionRange = nil
    }

    /// Simulates the host catching up: after this, `contextBefore` reflects
    /// the current buffer/cursor again.
    func settleContext() {
        frozenContextBefore = nil
    }

    func select(_ range: Range<String.Index>) {
        selectionRange = range
    }

    func selectAll() {
        selectionRange = buffer.startIndex ..< buffer.endIndex
    }

    private func freezeContextIfNeeded() {
        guard contextDelay, frozenContextBefore == nil else { return }
        frozenContextBefore = rawContextBefore()
    }

    private func rawContextBefore() -> String {
        let full = String(buffer[buffer.startIndex ..< cursorIndex])
        switch contextLimit {
        case .unlimited:
            return full
        case let .characters(n):
            return String(full.suffix(n))
        case .currentParagraphOnly:
            if let lastNewline = full.lastIndex(of: "\n") {
                return String(full[full.index(after: lastNewline)...])
            }
            return full
        }
    }

    private func rawContextAfter() -> String {
        let full = String(buffer[cursorIndex...])
        switch contextLimit {
        case .unlimited:
            return full
        case let .characters(n):
            return String(full.prefix(n))
        case .currentParagraphOnly:
            if let nextNewline = full.firstIndex(of: "\n") {
                return String(full[..<nextNewline])
            }
            return full
        }
    }
}
