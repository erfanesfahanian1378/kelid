import Foundation
import KelidCore
@testable import PersianText
@testable import PredictionEngine
import Testing

@Suite("Ranker")
struct RankerTests {
    @Test("dedupe keeps the highest-ranked variant of each canonical form by default")
    func dedupeKeepsHighestRanked() {
        let ranked = [
            RankedSuggestion(wordID: 0, surface: "میخواهم", score: -2.0),
            RankedSuggestion(wordID: 1, surface: "می\u{200C}خواهم", score: -3.0),
        ]
        let result = Ranker.dedupe(ranked, preferZWNJForms: false)
        #expect(result.count == 1)
        #expect(result[0].surface == "میخواهم")
    }

    @Test("dedupe with preferZWNJForms swaps in the ZWNJ variant even when it scored lower")
    func dedupePrefersZWNJWhenConfigured() {
        let ranked = [
            RankedSuggestion(wordID: 0, surface: "میخواهم", score: -2.0),
            RankedSuggestion(wordID: 1, surface: "می\u{200C}خواهم", score: -3.0),
        ]
        let result = Ranker.dedupe(ranked, preferZWNJForms: true)
        #expect(result.count == 1)
        #expect(result[0].surface == "می\u{200C}خواهم")
    }

    @Test("dedupe leaves distinct canonical forms alone")
    func dedupeLeavesDistinctWordsAlone() {
        let ranked = [
            RankedSuggestion(wordID: 0, surface: "کتاب", score: -2.0),
            RankedSuggestion(wordID: 1, surface: "دفتر", score: -3.0),
        ]
        #expect(Ranker.dedupe(ranked, preferZWNJForms: true).count == 2)
    }

    @Test("applyCasing uppercases the candidate when typed text is all caps")
    func casingUppercasesAllCaps() {
        #expect(Ranker.applyCasing("hello", typed: "HEL", isSentenceStart: false) == "HELLO")
    }

    @Test("applyCasing capitalizes the candidate when typed text starts uppercase")
    func casingCapitalizesOnUppercaseStart() {
        #expect(Ranker.applyCasing("hello", typed: "Hel", isSentenceStart: false) == "Hello")
    }

    @Test("applyCasing leaves lowercase typed text alone outside a sentence start")
    func casingLeavesLowercaseAlone() {
        #expect(Ranker.applyCasing("hello", typed: "hel", isSentenceStart: false) == "hello")
    }

    @Test("applyCasing capitalizes at a sentence start even with no typed text yet")
    func casingCapitalizesAtSentenceStart() {
        #expect(Ranker.applyCasing("the", typed: "", isSentenceStart: true) == "The")
    }

    @Test("rank favors an exact match-key match over a longer completion")
    func rankFavorsExactMatch() throws {
        let lexicon = try makeTestLexicon(unigrams: [
            UnigramEntry(surface: "hi", count: 100),
            UnigramEntry(surface: "hint", count: 100),
        ])
        let completions = lexicon.completions(prefixKey: "hi", limit: 10)
        let ranked = Ranker.rank(completions: completions, typedKey: "hi", lexicon: lexicon)
        #expect(ranked.first?.surface == "hi") // same frequency, but "hi" gets the exact-match bonus
    }
}

private func makeTestLexicon(unigrams: [UnigramEntry]) throws -> Lexicon {
    let data = try KLMWriter.build(language: .en, unigrams: unigrams, maxWords: 1000)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-ranker-test-\(UUID().uuidString).klm")
    try data.write(to: url)
    return try Lexicon(file: KLMFile(path: url.path))
}
