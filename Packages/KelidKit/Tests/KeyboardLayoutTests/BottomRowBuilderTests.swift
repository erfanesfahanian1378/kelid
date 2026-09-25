@testable import KeyboardLayout
import Testing

@Suite("BottomRowBuilder")
struct BottomRowBuilderTests {
    @Test("Persian letters row matches §6.2.6 shape, 2 languages, globe, no emoji key")
    func persianLettersRow() {
        let context = BottomRowContext(page: .letters, language: .fa, languagesCount: 2, needsGlobe: true)
        let row = BottomRowBuilder.build(context)
        let outs = row.map { $0.out ?? $0.action.rawValue }
        #expect(outs == ["۱۲۳", "globe", "EN", "zwnj", "space", ".", "return"])
        #expect(row.first { $0.action == .space }?.flex == true)
        #expect(row.first { $0.action == .space }?.label == "فارسی")
    }

    @Test("English letters row, 1 language: no globe, no language key")
    func englishLettersRowSingleLanguage() {
        let context = BottomRowContext(page: .letters, language: .en, languagesCount: 1, needsGlobe: false)
        let row = BottomRowBuilder.build(context)
        let outs = row.map { $0.out ?? $0.action.rawValue }
        #expect(outs == ["123", "space", ".", "return"])
    }

    @Test("emoji key goes right after the language key, when bottomRowEmojiKey and >1 language")
    func emojiKeyAfterLanguageKey() throws {
        let context = BottomRowContext(page: .letters, language: .fa, languagesCount: 2, needsGlobe: false, showEmojiKey: true)
        let row = BottomRowBuilder.build(context)
        let actions = row.map(\.action)
        let languageIndex = actions.firstIndex(of: .language)
        let emojiIndex = actions.firstIndex(of: .emoji)
        #expect(languageIndex != nil)
        #expect(try emojiIndex == (#require(languageIndex) + 1))
    }

    @Test("no emoji key without a language key (single language)")
    func noEmojiKeyWithoutLanguageKey() {
        let context = BottomRowContext(page: .letters, language: .fa, languagesCount: 1, needsGlobe: false, showEmojiKey: true)
        let row = BottomRowBuilder.build(context)
        #expect(!row.contains { $0.action == .emoji })
    }

    @Test("symbols row: language-return key, no ZWNJ, no language toggle")
    func symbolsRow() {
        let context = BottomRowContext(page: .symbols1, language: .fa, languagesCount: 2, needsGlobe: true)
        let row = BottomRowBuilder.build(context)
        #expect(row.first?.out == "ابپ")
        #expect(row.first?.action == .pageLetters)
        #expect(!row.contains { $0.action == .zwnj })
        #expect(!row.contains { $0.action == .language })
    }

    @Test("emailAddress row: 123, space(flex), @, ., return — always English digits")
    func emailAddressRow() {
        let context = BottomRowContext(page: .letters, language: .fa, languagesCount: 2, needsGlobe: false, keyboardType: .emailAddress)
        let row = BottomRowBuilder.build(context)
        let outs = row.map { $0.out ?? $0.action.rawValue }
        #expect(outs == ["123", "space", "@", ".", "return"])
    }

    @Test("URL row: .com has alternates and return is width 2")
    func urlRow() {
        let context = BottomRowContext(page: .letters, language: .en, languagesCount: 1, needsGlobe: false, keyboardType: .url)
        let row = BottomRowBuilder.build(context)
        let outs = row.map { $0.out ?? $0.action.rawValue }
        #expect(outs == ["123", ".", "/", ".com", "return"])
        #expect(row.first { $0.out == ".com" }?.alternates == [".ir", ".org", ".net", ".edu"])
        #expect(row.last?.width == 2.0)
    }

    @Test("twitter row: @, #, space, return")
    func twitterRow() {
        let context = BottomRowContext(page: .letters, language: .en, languagesCount: 1, needsGlobe: false, keyboardType: .twitter)
        let row = BottomRowBuilder.build(context)
        let outs = row.map { $0.out ?? $0.action.rawValue }
        #expect(outs == ["123", "@", "#", "space", "return"])
    }

    @Test("webSearch is structurally identical to the plain letters row")
    func webSearchMatchesLetters() {
        let plain = BottomRowContext(page: .letters, language: .en, languagesCount: 1, needsGlobe: true)
        let webSearch = BottomRowContext(page: .letters, language: .en, languagesCount: 1, needsGlobe: true, keyboardType: .webSearch)
        #expect(BottomRowBuilder.build(plain) == BottomRowBuilder.build(webSearch))
    }

    @Test("numpad has no bottom row")
    func numpadHasNoBottomRow() {
        let context = BottomRowContext(page: .numpad, language: .en, languagesCount: 1, needsGlobe: false)
        #expect(BottomRowBuilder.build(context).isEmpty)
    }
}
