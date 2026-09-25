@testable import PersianText
import Testing

@Suite("WordCharacters")
struct WordCharactersTests {
    @Test("Persian and English letters, digits, marks and ZWNJ/ZWJ are word characters")
    func wordCharacters() {
        for char: Character in ["ا", "a", "Z", "۵", "5", "\u{200C}", "\u{200D}", "\u{064E}"] {
            #expect(WordCharacters.isWordCharacter(char))
        }
    }

    @Test("punctuation and space are not word characters")
    func nonWordCharacters() {
        for char: Character in [" ", ".", "،", "!", "\n"] {
            #expect(!WordCharacters.isWordCharacter(char))
        }
    }

    @Test("apostrophe between letters is a word character; otherwise not")
    func apostropheBetweenLetters() throws {
        let text = "don't"
        let apostropheIndex = try #require(text.firstIndex(of: "'"))
        #expect(WordCharacters.isWordCharacter(at: apostropheIndex, in: text))

        let trailing = "quote'"
        let trailingApostrophe = trailing.index(before: trailing.endIndex)
        #expect(!WordCharacters.isWordCharacter(at: trailingApostrophe, in: trailing))
    }

    @Test("ZWNJ counts as a word character so a ZWNJ compound is one word")
    func zwnjIsWordCharacter() {
        // می‌خوام — every character including the ZWNJ should be a word character.
        for char in "می\u{200C}خوام" {
            #expect(WordCharacters.isWordCharacter(char))
        }
    }
}

@Suite("TextDirectionDetector")
struct TextDirectionDetectorTests {
    @Test("Persian text is RTL")
    func persianIsRTL() {
        #expect(TextDirectionDetector.dominantDirection("سلام") == .rtl)
    }

    @Test("English text is LTR")
    func englishIsLTR() {
        #expect(TextDirectionDetector.dominantDirection("hello") == .ltr)
    }

    @Test("digits-only text is neutral")
    func digitsAreNeutral() {
        #expect(TextDirectionDetector.dominantDirection("12345") == .neutral)
    }

    @Test("dominant direction is the first strong character, even with mixed text")
    func firstStrongCharacterWins() {
        #expect(TextDirectionDetector.dominantDirection("123 سلام hello") == .rtl)
        #expect(TextDirectionDetector.dominantDirection("123 hello سلام") == .ltr)
    }
}
