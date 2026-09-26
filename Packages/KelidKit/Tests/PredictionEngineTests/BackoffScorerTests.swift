import Foundation
import KelidCore
@testable import PersianText
@testable import PredictionEngine
import Testing

/// Task 8.1/8.2's required tests: "Backoff math on fixtures; `<s>`
/// handling; next-word ordering."
@Suite("BackoffScorer (Stupid Backoff, §6.7.3)")
struct BackoffScorerTests {
    /// A small vocabulary + one bigram + one trigram, sized so every
    /// probability is hand-computable: `<s>`, "من" (300/1000 unigram share),
    /// "کتاب", "او", "خانه" real words, plus 20 filler words so the "top-20
    /// unigram fallback" path has real, distinct candidates to reach.
    static func makeFixture() throws -> Lexicon {
        var unigrams = [
            UnigramEntry(surface: "<s>", count: 1000),
            UnigramEntry(surface: "من", count: 300),
            UnigramEntry(surface: "کتاب", count: 200),
            UnigramEntry(surface: "خانه", count: 150),
            UnigramEntry(surface: "او", count: 100),
        ]
        // 20 filler words so "top-20 unigrams" has a real, well-defined set
        // distinct from the 5 words above (all filler counts are lower than
        // "او"'s 100, so they never outrank the real words above by chance).
        for i in 0 ..< 20 {
            unigrams.append(UnigramEntry(surface: "پرکننده\(i)", count: UInt64(50 - i)))
        }

        var options = KLMBuildOptions()
        options.trigramContextMinBigramCount = 1
        let bigrams = [BigramEntry(w1: "من", w2: "کتاب", count: 30)] // P(کتاب|من) = 30/300 = 0.1
        let trigrams = [TrigramEntry(w1: "<s>", w2: "من", w3: "خانه", count: 5)] // P(خانه|<s>,من) = 5/30... needs bigram(<s>,من)

        // Trigram probability denominator is the (w1,w2) *bigram* count, so
        // also register that bigram: c(<s>, من) = 40 -> P(خانه|<s>,من) = 5/40 = 0.125.
        let allBigrams = bigrams + [BigramEntry(w1: "<s>", w2: "من", count: 40)]

        let data = try KLMWriter.build(
            language: .fa,
            unigrams: unigrams,
            maxWords: 200_000,
            bigrams: allBigrams,
            trigrams: trigrams,
            options: options
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-backoff-\(UUID().uuidString).klm")
        try data.write(to: url)
        return try Lexicon(file: KLMFile(path: url.path))
    }

    @Test("a trigram-covered word uses the trigram probability directly, with no backoff penalty")
    func trigramCoveredWordUsesTrigramScoreDirectly() throws {
        let lexicon = try Self.makeFixture()
        let sentenceStartID = try #require(lexicon.wordID(forExactSurface: "<s>"))
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let houseID = try #require(lexicon.wordID(forExactSurface: "خانه"))

        let candidates = BackoffScorer.nextWords(lexicon: lexicon, w1: sentenceStartID, w2: manID)
        let house = try #require(candidates.first { $0.wordID == houseID })

        // P(خانه|<s>,من) = 5/40 = 0.125 -> log10(0.125) ≈ -0.9031, no backoff term.
        #expect(abs(house.log10Score - log10(0.125)) < 0.05) // quantization tolerance
    }

    @Test("a bigram-only word (no trigram entry) is scored with exactly one backoff penalty")
    func bigramOnlyWordGetsOneBackoffPenalty() throws {
        let lexicon = try Self.makeFixture()
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let bookID = try #require(lexicon.wordID(forExactSurface: "کتاب"))

        // No trigram context for (نه‌چیزی, من) — use w1: nil so only the
        // bigram path can supply "کتاب".
        let candidates = BackoffScorer.nextWords(lexicon: lexicon, w1: nil, w2: manID)
        let book = try #require(candidates.first { $0.wordID == bookID })

        // P(کتاب|من) = 30/300 = 0.1 -> log10(0.1) = -1.0, plus one log10(0.4) backoff term.
        let expected = log10(0.1) + log10(0.4)
        #expect(abs(book.log10Score - expected) < 0.05)
    }

    @Test("a word with neither bigram nor trigram data falls back to unigram probability with two backoff penalties")
    func unigramFallbackGetsTwoBackoffPenalties() throws {
        let lexicon = try Self.makeFixture()
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let filler0ID = try #require(lexicon.wordID(forExactSurface: "پرکننده0"))

        let candidates = BackoffScorer.nextWords(lexicon: lexicon, w1: nil, w2: manID, limit: 30)
        let filler = try #require(candidates.first { $0.wordID == filler0ID })

        // "<s>" is hidden — its count doesn't contribute to the total real-
        // word count `KLMWriter` divides by for P(w) (see decision log).
        let namedWordsCount: Double = 300 + 200 + 150 + 100
        var fillerWordsCount = 0.0
        for i in 0 ..< 20 {
            fillerWordsCount += Double(50 - i)
        }
        let totalUnigramCount = namedWordsCount + fillerWordsCount
        let expectedP = 50.0 / totalUnigramCount
        let expected = log10(expectedP) + 2 * log10(0.4)
        #expect(abs(filler.log10Score - expected) < 0.1) // wider tolerance: quantized twice removed from raw count
    }

    @Test("<s> itself is never returned as a next-word candidate")
    func sentenceStartNeverSuggested() throws {
        let lexicon = try Self.makeFixture()
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let candidates = BackoffScorer.nextWords(lexicon: lexicon, w1: nil, w2: manID, limit: 100)
        #expect(candidates.allSatisfy { $0.surface != "<s>" })
    }

    @Test("next-word candidates are ordered by score descending (trigram beats bigram beats unigram fallback)")
    func candidatesAreOrderedByScoreDescending() throws {
        let lexicon = try Self.makeFixture()
        let sentenceStartID = try #require(lexicon.wordID(forExactSurface: "<s>"))
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let candidates = BackoffScorer.nextWords(lexicon: lexicon, w1: sentenceStartID, w2: manID, limit: 30)
        for i in 1 ..< candidates.count {
            #expect(candidates[i - 1].log10Score >= candidates[i].log10Score)
        }
        // "خانه" (trigram, log10P ≈ -0.90) should heavily outrank "پرکننده0"
        // (unigram fallback, two backoff penalties, much lower score).
        let houseIndex = try #require(candidates.firstIndex { $0.surface == "خانه" })
        let fillerIndex = candidates.firstIndex { $0.surface == "پرکننده0" }
        if let fillerIndex {
            #expect(houseIndex < fillerIndex)
        }
    }

    @Test("contextAwareCandidates filters next-word candidates by typed-key prefix")
    func contextAwareCandidatesFiltersByPrefix() throws {
        let lexicon = try Self.makeFixture()
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        // matchKey("کتاب") starts with "ک".
        let candidates = BackoffScorer.contextAwareCandidates(lexicon: lexicon, w1: nil, w2: manID, typedKey: "ک")
        #expect(candidates.contains { $0.surface == "کتاب" })
        #expect(candidates.allSatisfy { PersianNormalization.matchKey($0.surface).hasPrefix("ک") })
    }

    @Test("contextAwareCandidates returns empty for an empty typed key")
    func contextAwareCandidatesEmptyForEmptyKey() throws {
        let lexicon = try Self.makeFixture()
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        #expect(BackoffScorer.contextAwareCandidates(lexicon: lexicon, w1: nil, w2: manID, typedKey: "").isEmpty)
    }
}
