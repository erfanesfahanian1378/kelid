import Foundation
import KelidCore
import KeyboardLayout
import PersianText

/// Cursor word/line movement (§6.4.9) and language advance (§6.4.7) — split
/// out of `InputProcessor.swift` itself purely to keep that type's body
/// under SwiftLint's `type_body_length`; behaviorally this is still part of
/// `InputProcessor`, just declared in a second file.
extension InputProcessor {
    func wordBoundaryOffset(direction: MoveDirection, in doc: TextDocument) -> Int {
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

    func lineBoundaryOffset(direction: MoveDirection, in doc: TextDocument) -> Int {
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

    func advanceLanguage(enabledLanguages: [LanguageID]) -> [InputEffect] {
        guard enabledLanguages.count > 1, let index = enabledLanguages.firstIndex(of: currentLanguage) else {
            return []
        }
        let nextIndex = enabledLanguages.index(after: index) == enabledLanguages.endIndex ? enabledLanguages.startIndex : enabledLanguages
            .index(after: index)
        currentLanguage = enabledLanguages[nextIndex]
        return [.languageChanged(currentLanguage)]
    }
}
