import Foundation
import KelidCore
@testable import klm
import PersianText
import PredictionEngine
import Testing

@Suite("Eval (§6.7.12, task 8.9)")
struct EvalTests {
    static func makeLexicon(_ unigrams: [UnigramEntry], bigrams: [BigramEntry] = [], language: LanguageID = .en) throws -> Lexicon {
        let data = try KLMWriter.build(language: language, unigrams: unigrams, maxWords: 200_000, bigrams: bigrams)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-eval-\(UUID().uuidString).klm")
        try data.write(to: url)
        return try Lexicon(file: KLMFile(path: url.path))
    }

    @Test("KSR matches a hand-computed value: accepted after exactly 1 typed letter")
    func ksrMatchesHandComputedValue() throws {
        // "dog"/"bird"/"fish" outrank "cat" in raw frequency, so they (not
        // "cat") fill the top-3 completions for an empty prefix; "cat" only
        // surfaces once "c" narrows the trie to itself. Accepted at
        // prefixLength=1 -> actual = 1 (letter) + 1 (accept tap) = 2,
        // naive = 3 (letters) + 1 (space) = 4 -> KSR = 1 - 2/4 = 0.5.
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "cat", count: 100),
            UnigramEntry(surface: "dog", count: 200),
            UnigramEntry(surface: "bird", count: 150),
            UnigramEntry(surface: "fish", count: 120),
        ])
        let ksr = Eval.keystrokeSavingsRate(lexicon: lexicon, sentences: [["cat"]])
        #expect(abs(ksr - 0.5) < 0.001)
    }

    @Test("KSR is higher when a word completes after just its first letter than when it needs the whole word")
    func ksrHigherWithEarlierCompletion() throws {
        let earlyLexicon = try Self.makeLexicon([UnigramEntry(surface: "cat", count: 100)])
        let lateLexicon = try Self.makeLexicon([
            UnigramEntry(surface: "cat", count: 100),
            UnigramEntry(surface: "car", count: 100),
            UnigramEntry(surface: "can", count: 100),
            UnigramEntry(surface: "cap", count: 100),
        ])
        let earlyKSR = Eval.keystrokeSavingsRate(lexicon: earlyLexicon, sentences: [["cat"]])
        let lateKSR = Eval.keystrokeSavingsRate(lexicon: lateLexicon, sentences: [["cat"]])
        #expect(earlyKSR > lateKSR)
    }

    @Test("next-word accuracy scores top-1 correctly from real bigram data")
    func nextWordAccuracyScoresTop1() throws {
        let lexicon = try Self.makeLexicon(
            [
                UnigramEntry(surface: "hello", count: 300),
                UnigramEntry(surface: "world", count: 100),
                UnigramEntry(surface: "there", count: 50),
            ],
            bigrams: [BigramEntry(w1: "hello", w2: "world", count: 30)]
        )
        let result = Eval.nextWordAccuracy(lexicon: lexicon, sentences: [["hello", "world"]])
        // "hello" (first word) has no preceding context -> unigram fallback
        // only; "world" (second word) has "hello" as context -> the real
        // bigram should put it at top-1.
        #expect(result.sampleCount == 2)
        #expect(result.top1 > 0) // at least one of the two words hit top-1
    }

    @Test("correction accuracy resolves a synthetic typo back to the real word")
    func correctionAccuracyResolvesTypo() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "hello", count: 100_000), UnigramEntry(surface: "world", count: 100)])
        let result = Eval.correctionAccuracy(lexicon: lexicon, sentences: [["hello"]], proximity: .empty, seed: 7)
        #expect(result.sampleCount > 0) // "hello" is long enough for every typo kind except homophone (no Persian letters)
        #expect(result.top1 > 0)
    }

    @Test("correction accuracy is deterministic for a fixed seed")
    func correctionAccuracyIsDeterministic() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "hello", count: 100_000), UnigramEntry(surface: "world", count: 100)])
        let first = Eval.correctionAccuracy(lexicon: lexicon, sentences: [["hello", "world"]], proximity: .empty, seed: 123)
        let second = Eval.correctionAccuracy(lexicon: lexicon, sentences: [["hello", "world"]], proximity: .empty, seed: 123)
        #expect(first.top1 == second.top1)
        #expect(first.sampleCount == second.sampleCount)
    }

    @Test("latencyPercentiles returns non-negative, ordered p50 <= p95")
    func latencyPercentilesAreOrdered() throws {
        let lexicon = try Self.makeLexicon((0 ..< 50).map { UnigramEntry(surface: "word\($0)", count: UInt64(100 - $0)) })
        let result = Eval.latencyPercentiles(lexicon: lexicon, sentences: [(0 ..< 50).map { "word\($0)" }])
        #expect(result.p50 >= 0)
        #expect(result.p95 >= result.p50)
    }

    @Test("run() assembles all metrics into one Metrics value")
    func runAssemblesMetrics() throws {
        let lexicon = try Self.makeLexicon(
            [UnigramEntry(surface: "hello", count: 300), UnigramEntry(surface: "world", count: 100)],
            bigrams: [BigramEntry(w1: "hello", w2: "world", count: 30)]
        )
        let metrics = Eval.run(lexicon: lexicon, sentences: [["hello", "world"]], proximity: .empty)
        #expect(metrics.wordCount == 2)
        #expect(metrics.ksr >= 0 && metrics.ksr <= 1)
    }

    // MARK: - TypoKind

    @Test("TypoKind.deletion removes exactly one character")
    func deletionRemovesOneCharacter() {
        var generator = SplitMix64(seed: 1)
        let typo = TypoKind.deletion.apply(to: "hello", proximity: .empty, using: &generator)
        #expect(typo?.count == 4)
    }

    @Test("TypoKind.insertion adds exactly one character (a duplicate)")
    func insertionAddsOneCharacter() {
        var generator = SplitMix64(seed: 1)
        let typo = TypoKind.insertion.apply(to: "hello", proximity: .empty, using: &generator)
        #expect(typo?.count == 6)
    }

    @Test("TypoKind.transposition keeps the same length and character multiset")
    func transpositionKeepsLengthAndCharacters() throws {
        var generator = SplitMix64(seed: 1)
        let typo = try #require(TypoKind.transposition.apply(to: "hello", proximity: .empty, using: &generator))
        #expect(typo.count == 5)
        #expect(typo.sorted() == "hello".sorted())
    }

    @Test("TypoKind.homophone returns nil for a word with no Persian confusion-group letters")
    func homophoneReturnsNilForPlainEnglish() {
        var generator = SplitMix64(seed: 1)
        let typo = TypoKind.homophone.apply(to: "hello", proximity: .empty, using: &generator)
        #expect(typo == nil)
    }

    @Test("TypoKind.homophone substitutes a confusion-group letter for a Persian word")
    func homophoneSubstitutesForPersianWord() throws {
        var generator = SplitMix64(seed: 1)
        let typo = try #require(TypoKind.homophone.apply(to: "سلام", proximity: .empty, using: &generator))
        #expect(typo.count == 4)
        #expect(typo != "سلام")
    }

    @Test("TypoKind.adjacentKey substitutes a letter for one of its row-neighbors")
    func adjacentKeySubstitutesNeighbor() throws {
        var generator = SplitMix64(seed: 1)
        let typo = try #require(TypoKind.adjacentKey.apply(to: "hello", proximity: .empty, using: &generator))
        #expect(typo.count == 5)
    }

    // MARK: - EvalKeyAdjacency

    @Test("EvalKeyAdjacency.neighbors returns the row-adjacent letters for an English key")
    func englishNeighborsAreRowAdjacent() {
        #expect(Set(EvalKeyAdjacency.neighbors(of: "s")) == Set(["a", "d"]))
    }

    @Test("EvalKeyAdjacency.neighbors returns an empty array for an unknown character")
    func unknownCharacterHasNoNeighbors() {
        #expect(EvalKeyAdjacency.neighbors(of: "1").isEmpty)
    }

    @Test("EvalKeyAdjacency.persianConfusionGroupMembers finds the right group")
    func confusionGroupMembersFindsGroup() throws {
        let members = try #require(EvalKeyAdjacency.persianConfusionGroupMembers("ص"))
        #expect(Set(members) == Set(["س", "ص", "ث"]))
    }

    @Test("EvalKeyAdjacency.persianConfusionGroupMembers returns nil for a letter in no group")
    func confusionGroupMembersNilForUngroupedLetter() {
        #expect(EvalKeyAdjacency.persianConfusionGroupMembers("ب") == nil)
    }

    // MARK: - SplitMix64

    @Test("SplitMix64 is deterministic for a fixed seed")
    func splitMix64IsDeterministic() {
        var a = SplitMix64(seed: 99)
        var b = SplitMix64(seed: 99)
        #expect(a.next() == b.next())
        #expect(a.next() == b.next())
    }
}
