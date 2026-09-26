import Foundation
import PersianText

/// Commit detection and §6.7.8's word-shape learnability filters (task
/// 9.3) — split out of `InputProcessor.swift` itself purely to keep that
/// type's body under SwiftLint's `type_body_length`; behaviorally this is
/// still part of `InputProcessor`, just declared in a second file.
extension InputProcessor {
    /// Builds a `.learn(CommitEvent)` effect for a just-committed word, or
    /// `[]` if it fails §6.7.8's filters. Only the checks `InputProcessor`
    /// can actually make (field sensitivity, word shape) happen here —
    /// `learning.enabled`/incognito are settings/UI state `KeyboardUI` owns,
    /// so it does that half of the gating itself before ever touching
    /// `UserModel`.
    func commitEffect(
        word: String, source: CommitSource, previousWords: [String], traits: FieldTraits, revertedCorrection: String? = nil
    ) -> [InputEffect] {
        guard !traits.isSensitive, CommitLearnability.isLearnable(word) else { return [] }
        return [.learn(CommitEvent(
            word: word, language: currentLanguage, source: source, previousWords: previousWords,
            revertedCorrection: revertedCorrection
        ))]
    }
}

/// §6.7.8: "Never learn when... the token is > 32 graphemes, contains
/// digits, looks like a URL or email, is emoji-only, mixes Persian and
/// Latin letters, or has 3+ identical letters in a row."
enum CommitLearnability {
    static func isLearnable(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let characters = Array(word)
        guard characters.count <= 32 else { return false }
        guard !word.contains(where: \.isNumber) else { return false }
        guard !looksLikeURLOrEmail(word) else { return false }
        guard !isEmojiOnly(characters) else { return false }
        guard !mixesPersianAndLatin(word) else { return false }
        guard !hasThreeOrMoreRepeatedCharacters(characters) else { return false }
        return true
    }

    /// Same best-effort, single-word heuristic as
    /// `PredictionEngine.AutocorrectEngine`'s own — `InputEngine` can't
    /// depend on `PredictionEngine` to share it (§4.2's sibling modules),
    /// so this is a small, independent duplicate.
    private static func looksLikeURLOrEmail(_ text: String) -> Bool {
        if text.contains("@"), text.contains(".") {
            return true
        }
        if text.contains("://") {
            return true
        }
        if text.lowercased().hasPrefix("www.") {
            return true
        }
        if let dotIndex = text.firstIndex(of: "."), dotIndex != text.startIndex, text.index(after: dotIndex) < text.endIndex {
            return true
        }
        return false
    }

    private static func isEmojiOnly(_ characters: [Character]) -> Bool {
        !characters.isEmpty && characters.allSatisfy(isEmojiCharacter)
    }

    private static func isEmojiCharacter(_ character: Character) -> Bool {
        guard let firstScalar = character.unicodeScalars.first else { return false }
        if firstScalar.properties.isEmojiPresentation || firstScalar.value >= 0x1F300 {
            return true
        }
        // A multi-scalar grapheme (e.g. a ZWJ sequence or a keycap) that
        // combines an emoji-property scalar with something else.
        return character.unicodeScalars.count > 1 && character.unicodeScalars.contains { $0.properties.isEmoji }
    }

    /// Persian/Arabic block ranges (matching the same ranges PLAN.md's own
    /// RTL-cursor-direction check uses: U+0600–U+06FF, U+FB50–U+FDFF,
    /// U+FE70–U+FEFF) mixed with plain ASCII Latin letters.
    private static func mixesPersianAndLatin(_ text: String) -> Bool {
        var hasPersian = false
        var hasLatin = false
        for scalar in text.unicodeScalars {
            if Self.isPersianScalar(scalar) {
                hasPersian = true
            } else if scalar.isASCII, Character(scalar).isLetter {
                hasLatin = true
            }
            if hasPersian, hasLatin {
                return true
            }
        }
        return false
    }

    private static func isPersianScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x0600 ... 0x06FF).contains(scalar.value) || (0xFB50 ... 0xFDFF).contains(scalar.value) || (0xFE70 ... 0xFEFF)
            .contains(scalar.value)
    }

    private static func hasThreeOrMoreRepeatedCharacters(_ characters: [Character]) -> Bool {
        guard characters.count >= 3 else { return false }
        for index in 0 ... (characters.count - 3) {
            if characters[index] == characters[index + 1], characters[index + 1] == characters[index + 2] {
                return true
            }
        }
        return false
    }
}
