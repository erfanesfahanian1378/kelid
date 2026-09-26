@testable import EmojiData
import Foundation
import Testing

@Suite("EmojiSuggester (§6.7.10, task 8.7)")
@MainActor
struct EmojiSuggesterTests {
    static func makeSuggester(fixtures: [String: [String: [String]]]) throws -> EmojiSuggester {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-emoji-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (language, table) in fixtures {
            let data = try JSONEncoder().encode(table)
            try data.write(to: dir.appendingPathComponent("emoji_suggest_\(language).json"))
        }
        let bundle = try #require(Bundle(path: dir.path))
        return EmojiSuggester(bundle: bundle)
    }

    @Test("suggest returns the matching emoji list for an exact keyword")
    func suggestsForExactKeyword() throws {
        let suggester = try Self.makeSuggester(fixtures: ["en": ["smile": ["🙂", "😀"]]])
        #expect(suggester.suggest(forWord: "smile", language: "en") == ["🙂", "😀"])
    }

    @Test("suggest normalizes via matchKey before lookup (case-insensitive for English)")
    func suggestNormalizesKeyCase() throws {
        let suggester = try Self.makeSuggester(fixtures: ["en": ["smile": ["🙂"]]])
        #expect(suggester.suggest(forWord: "SMILE", language: "en") == ["🙂"])
        #expect(suggester.suggest(forWord: "Smile", language: "en") == ["🙂"])
    }

    @Test("suggest returns empty for an unmatched word")
    func suggestReturnsEmptyForUnmatchedWord() throws {
        let suggester = try Self.makeSuggester(fixtures: ["en": ["smile": ["🙂"]]])
        #expect(suggester.suggest(forWord: "xyzzy", language: "en") == [])
    }

    @Test("suggest returns empty for an empty word")
    func suggestReturnsEmptyForEmptyWord() throws {
        let suggester = try Self.makeSuggester(fixtures: ["en": ["smile": ["🙂"]]])
        #expect(suggester.suggest(forWord: "", language: "en") == [])
    }

    @Test("suggest returns empty for a language with no bundled table")
    func suggestReturnsEmptyForUnknownLanguage() throws {
        let suggester = try Self.makeSuggester(fixtures: ["en": ["smile": ["🙂"]]])
        #expect(suggester.suggest(forWord: "smile", language: "de") == [])
    }

    @Test("a missing/corrupt resource degrades to no suggestions rather than throwing")
    func missingResourceDegradesGracefully() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-emoji-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try #require(Bundle(path: dir.path))
        let suggester = EmojiSuggester(bundle: bundle)
        #expect(suggester.suggest(forWord: "smile", language: "en") == [])
    }

    @Test("the real bundled fa/en resources resolve common real keywords")
    func realBundledResourcesResolveRealKeywords() {
        let suggester = EmojiSuggester() // default .module bundle -> the real, committed resources
        #expect(!suggester.suggest(forWord: "smile", language: "en").isEmpty)
        #expect(!suggester.suggest(forWord: "خنده", language: "fa").isEmpty)
    }
}
