import Foundation
import KeyboardLayout
import PersianText

/// `TypingContext` computation (task 3.5, §6.4.2) — split out of
/// `InputProcessor.swift` itself purely to keep that type's body under
/// SwiftLint's `type_body_length`; behaviorally this is still part of
/// `InputProcessor`, just declared in a second file. `computeContext` is
/// `internal` (not `private`) since `handle(_:in:)`/`textDidChange(in:)` in
/// the main file call it — `private` is file-scoped in Swift, even across
/// extensions of the same type.
extension InputProcessor {
    func computeContext(doc: TextDocument) -> TypingContext {
        let before = doc.contextBefore ?? shadowBuffer.contents
        let after = doc.contextAfter ?? ""

        let prefix = trailingWordCharacters(before)
        let suffix = leadingWordCharacters(after)
        let isSentenceStart = computeIsSentenceStart(before)
        let previousWords = computePreviousWords(before, currentPrefix: prefix)

        return TypingContext(
            prefix: prefix,
            suffix: suffix,
            previousWords: previousWords,
            isSentenceStart: isSentenceStart,
            language: currentLanguage,
            traits: doc.traits
        )
    }

    private func trailingWordCharacters(_ text: String) -> String {
        String(Array(text).reversed().prefix { WordCharacters.isWordCharacter($0) }.reversed())
    }

    private func leadingWordCharacters(_ text: String) -> String {
        String(text.prefix { WordCharacters.isWordCharacter($0) })
    }

    private func computeIsSentenceStart(_ before: String) -> Bool {
        var chars = Array(before)
        guard !chars.isEmpty else { return true }
        if chars.last == "\n" {
            return true
        }
        // Skip trailing spaces.
        while let last = chars.last, last == " " {
            chars.removeLast()
        }
        if chars.isEmpty {
            return true
        } // only spaces/nothing before the cursor
        guard let last = chars.last else { return true }
        return sentenceEndCharacters.contains(last)
    }

    /// Up to 2 words back in the same sentence, stopping at a sentence
    /// boundary; `["<s>"]` if there are none (§6.4.2).
    private func computePreviousWords(_ before: String, currentPrefix: String) -> [String] {
        var remaining = String(before.dropLast(currentPrefix.count))
        var words: [String] = []
        while words.count < 2 {
            // Trim trailing separators, stopping at a sentence boundary.
            guard let last = remaining.last else { break }
            if sentenceEndCharacters.contains(last) || last == "\n" {
                break
            }
            if last == " " {
                remaining.removeLast()
                continue
            }
            let word = trailingWordCharacters(remaining)
            guard !word.isEmpty else { break }
            words.insert(word, at: 0)
            remaining.removeLast(word.count)
        }
        return words.isEmpty ? ["<s>"] : words
    }
}
