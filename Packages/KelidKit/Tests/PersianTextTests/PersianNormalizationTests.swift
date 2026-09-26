@testable import PersianText
import Testing

@Suite("PersianNormalization")
struct PersianNormalizationTests {
    // MARK: - canonical

    @Test("canonical maps Arabic yeh/kaf variants to Persian forms")
    func canonicalMapsYehAndKaf() {
        #expect(PersianNormalization.canonical("علي") == "علی") // ي -> ی
        #expect(PersianNormalization.canonical("كتاب") == "کتاب") // ك -> ک
    }

    @Test("canonical converts Arabic-Indic digits to Persian digits")
    func canonicalConvertsDigits() {
        #expect(PersianNormalization.canonical("٠١٢٣") == "۰۱۲۳")
    }

    @Test("canonical removes tatweel")
    func canonicalRemovesTatweel() {
        #expect(PersianNormalization.canonical("سـلام") == "سلام")
    }

    @Test("canonical removes ZWNJ at word start, end, and next to a space")
    func canonicalRemovesEdgeZWNJ() {
        #expect(PersianNormalization.canonical("\u{200C}می\u{200C}خوام") == "می\u{200C}خوام") // leading ZWNJ dropped, internal kept
        #expect(PersianNormalization.canonical("می\u{200C}خوام\u{200C}") == "می\u{200C}خوام") // trailing dropped
        #expect(PersianNormalization.canonical("سلام \u{200C}دنیا") == "سلام دنیا") // space-adjacent dropped
    }

    @Test("canonical collapses repeated ZWNJ to one")
    func canonicalCollapsesRepeatedZWNJ() {
        let result = PersianNormalization.canonical("می\u{200C}\u{200C}خوام")
        #expect(result.unicodeScalars.filter { $0 == "\u{200C}" }.count == 1)
    }

    @Test("canonical removes ZWJ between two Persian letters but keeps it elsewhere")
    func canonicalRemovesZWJBetweenPersianLetters() {
        #expect(PersianNormalization.canonical("ک\u{200D}گ") == "کگ")
        #expect(PersianNormalization.canonical("a\u{200D}b") == "a\u{200D}b")
    }

    @Test("canonical normalizes NBSP to a regular space")
    func canonicalNormalizesNBSP() {
        #expect(PersianNormalization.canonical("سلام\u{00A0}دنیا") == "سلام دنیا")
    }

    // MARK: - matchKey

    @Test("matchKey removes diacritics")
    func matchKeyRemovesDiacritics() {
        #expect(PersianNormalization.matchKey("سَلام") == "سلام")
    }

    @Test("matchKey maps hamza-carrying letters to their base form")
    func matchKeyMapsHamzaLetters() {
        #expect(PersianNormalization.matchKey("آب") == "اب")
        #expect(PersianNormalization.matchKey("مؤمن") == "مومن")
        #expect(PersianNormalization.matchKey("رئیس") == "رییس")
        #expect(PersianNormalization.matchKey("خانۀ") == "خانه")
        #expect(PersianNormalization.matchKey("مدرسة") == "مدرسه")
    }

    @Test("matchKey lowercases Latin text and normalizes curly apostrophe")
    func matchKeyLowercasesLatin() {
        #expect(PersianNormalization.matchKey("Don\u{2019}t") == "don't")
    }

    @Test("matchKey converts all digits to ASCII")
    func matchKeyConvertsDigitsToASCII() {
        #expect(PersianNormalization.matchKey("۱۲۳") == "123")
        #expect(PersianNormalization.matchKey("١٢٣") == "123")
    }

    // MARK: - searchKey (§6.6.4's own worked examples)

    @Test("searchKey finds ی when querying ي")
    func searchKeyMatchesYehVariant() {
        #expect(PersianNormalization.searchKey("علی") == PersianNormalization.searchKey("علي"))
    }

    @Test("searchKey finds کتابها when querying کتاب\u{200C}ها (ZWNJ-insensitive)")
    func searchKeyIsZWNJInsensitive() {
        // Internal ZWNJ isn't stripped by canonical (only edge/space-adjacent
        // ZWNJ is) but matchKey/searchKey strip *all* ZWNJ, since they're
        // for lossy matching, not display.
        #expect(PersianNormalization.searchKey("کتاب\u{200C}ها") == PersianNormalization.searchKey("کتابها"))
    }

    @Test("searchKey collapses whitespace")
    func searchKeyCollapsesWhitespace() {
        #expect(PersianNormalization.searchKey("سلام   دنیا") == PersianNormalization.searchKey("سلام دنیا"))
    }

    @Test("searchKey removes Latin accents")
    func searchKeyRemovesLatinAccents() {
        #expect(PersianNormalization.searchKey("café") == "cafe")
    }
}
