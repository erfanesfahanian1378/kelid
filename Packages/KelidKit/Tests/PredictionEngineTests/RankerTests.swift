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

    @Test("rank(fuzzy:) penalizes a candidate by its edit cost via the gamma term, unlike rank(completions:)'s always-0 cost")
    func rankFuzzyPenalizesEditCost() throws {
        let lexicon = try makeTestLexicon(unigrams: [UnigramEntry(surface: "hello", count: 100)])
        let match = FuzzyMatch(wordID: 0, surface: "hello", score: lexicon.score(0), editCost: 1.0)
        let ranked = Ranker.rank(fuzzy: [match], typedKey: "helo", lexicon: lexicon)
        let completionRanked = Ranker.rank(
            completions: [LexiconCompletion(wordID: 0, surface: "hello", score: lexicon.score(0))],
            typedKey: "helo", lexicon: lexicon
        )
        // Same word, same typed key, but the fuzzy candidate carries a real
        // (nonzero) edit cost -> its score must be strictly lower.
        #expect(ranked[0].score < completionRanked[0].score)
        // Exactly gamma (1.2 by default) * editCost (1.0) lower, in log10 space.
        #expect(abs((completionRanked[0].score - ranked[0].score) - RankerConfig().gamma) < 0.0001)
    }

    @Test("RankerConfig's blending weight defaults to 0 (task 8.5's hook, wired in Phase 9)")
    func rankerConfigPersonalWeightDefaultsToZero() {
        #expect(RankerConfig().personalWeight == 0)
    }

    // MARK: - Task 9.4: personal blending

    @Test("rank(completions:) blends S_lang and S_user exactly per §6.7.5's formula when personalWeight > 0")
    func rankCompletionsBlendsWithPersonalScore() throws {
        // A single word at 100% of the vocabulary -> log10Probability == 0
        // (S_lang == 1.0 exactly), so the blend's arithmetic is easy to
        // hand-verify: blended = 0.5*0.2 + 0.5*1.0 = 0.6.
        let lexicon = try makeTestLexicon(unigrams: [UnigramEntry(surface: "hello", count: 100)])
        let completions = lexicon.completions(prefixKey: "hello", limit: 10)
        let config = RankerConfig(personalWeight: 0.5)
        let ranked = Ranker.rank(
            completions: completions,
            typedKey: "hello",
            lexicon: lexicon,
            personalScores: ["hello": 0.2],
            config: config
        )
        let expected = log10(0.6) + 0.15 // + §6.7.5's exact-match bonus (candidateKey == typedKey)
        #expect(abs(ranked[0].score - expected) < 0.0001)
    }

    @Test("personalWeight = 0 (the default) never even looks at personalScores, matching the pre-Phase-9 score exactly")
    func zeroPersonalWeightIgnoresPersonalScores() throws {
        let lexicon = try makeTestLexicon(unigrams: [UnigramEntry(surface: "hello", count: 100)])
        let completions = lexicon.completions(prefixKey: "hello", limit: 10)
        let withoutPersonalScores = Ranker.rank(completions: completions, typedKey: "hello", lexicon: lexicon)
        // A poisoned value that would visibly change the score if it were
        // ever read — proves λ=0 short-circuits before touching it.
        let withPoisonedPersonalScores = Ranker.rank(
            completions: completions, typedKey: "hello", lexicon: lexicon, personalScores: ["hello": 999],
            config: RankerConfig(personalWeight: 0)
        )
        #expect(withoutPersonalScores[0].score == withPoisonedPersonalScores[0].score)
    }

    @Test("rank(personalOnly:) scores a language-model-unknown word purely from S_user (S_lang = 0)")
    func rankPersonalOnlyUsesOnlyPersonalScore() throws {
        let lexicon = try makeTestLexicon(unigrams: [UnigramEntry(surface: "hello", count: 100)]) // unrelated to "newword"
        let config = RankerConfig(personalWeight: 0.5)
        let ranked = Ranker.rank(
            personalOnly: [(surface: "newword", editCost: 0)], typedKey: "newword", lexicon: lexicon,
            personalScores: ["newword": 0.3], config: config
        )
        let expected = log10(0.5 * 0.3) + 0.15 // S_lang term drops out entirely (0.5 * 0 == 0) + exact-match bonus
        #expect(abs(ranked[0].score - expected) < 0.0001)
    }

    @Test("blendedNextWordScore matches §6.7.5's formula exactly")
    func blendedNextWordScoreMatchesFormula() {
        let config = RankerConfig(personalWeight: 0.6)
        let score = Ranker.blendedNextWordScore(surface: "foo", log10LanguageScore: -1.0, personalScores: ["foo": 0.4], config: config)
        let expected = log10(0.6 * 0.4 + 0.4 * 0.1) // S_lang = 10^-1.0 = 0.1
        #expect(abs(score - expected) < 0.0001)
    }

    @Test("blendedNextWordScore returns the language score unchanged when personalWeight is 0")
    func blendedNextWordScoreNoOpAtZeroWeight() {
        let score = Ranker.blendedNextWordScore(
            surface: "foo",
            log10LanguageScore: -1.0,
            personalScores: ["foo": 999],
            config: RankerConfig()
        )
        #expect(score == -1.0)
    }
}

private func makeTestLexicon(unigrams: [UnigramEntry]) throws -> Lexicon {
    let data = try KLMWriter.build(language: .en, unigrams: unigrams, maxWords: 1000)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-ranker-test-\(UUID().uuidString).klm")
    try data.write(to: url)
    return try Lexicon(file: KLMFile(path: url.path))
}
