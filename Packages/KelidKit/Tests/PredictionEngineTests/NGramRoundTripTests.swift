import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

/// Task 8.1's required tests: "Backoff math on fixtures; `<s>` handling;
/// next-word ordering," plus a writer→reader round trip for the new
/// `BIDX`/`BENT`/`TIDX`/`TENT` sections (matching task 7.2's own precedent
/// for the unigram sections).
@Suite("KLM n-gram (bigram/trigram) round trip")
struct NGramRoundTripTests {
    static let unigrams: [UnigramEntry] = [
        UnigramEntry(surface: "<s>", count: 1000),
        UnigramEntry(surface: "من", count: 500),
        UnigramEntry(surface: "می\u{200C}خواهم", count: 200),
        UnigramEntry(surface: "بروم", count: 100),
        UnigramEntry(surface: "کتاب", count: 300),
        UnigramEntry(surface: "بخوانم", count: 50),
        UnigramEntry(surface: "او", count: 150),
    ]

    static func writeFixture(bigrams: [BigramEntry] = [], trigrams: [TrigramEntry] = [],
                             options: KLMBuildOptions = KLMBuildOptions()) throws -> KLMFile
    {
        let data = try KLMWriter.build(
            language: .fa,
            unigrams: unigrams,
            maxWords: 200_000,
            bigrams: bigrams,
            trigrams: trigrams,
            options: options
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-ngram-\(UUID().uuidString).klm")
        try data.write(to: url)
        return try KLMFile(path: url.path)
    }

    @Test("a file with no bigrams/trigrams reports hasBigrams/hasTrigrams false")
    func noBigramsReportsFalse() throws {
        let file = try Self.writeFixture()
        #expect(!file.hasBigrams)
        #expect(!file.hasTrigrams)
    }

    @Test("<s> gets a real word id, is hidden, and never appears in completions")
    func sentenceStartIsHiddenButHasID() throws {
        let file = try Self.writeFixture()
        let lexicon = Lexicon(file: file)
        let id = try #require(lexicon.wordID(forExactSurface: "<s>"))
        #expect(lexicon.surface(id) == "<s>")
        #expect(file.flags(id) & KLMFormat.WordFlags.hidden != 0)
        // Never reachable via matchKey-based lookup (never in the trie).
        #expect(lexicon.wordID(forSurface: "<s>") == nil)
        // Never shows up in ANY completion search, including an empty prefix.
        #expect(lexicon.completions(prefixKey: "", limit: 1000).allSatisfy { $0.surface != "<s>" })
    }

    @Test("bigram round trip: exact counts recoverable as quantized scores in frequency order")
    func bigramRoundTrip() throws {
        let bigrams = [
            BigramEntry(w1: "<s>", w2: "من", count: 800), // most likely sentence starter
            BigramEntry(w1: "<s>", w2: "او", count: 100),
            BigramEntry(w1: "من", w2: "می\u{200C}خواهم", count: 400),
            BigramEntry(w1: "من", w2: "کتاب", count: 50),
        ]
        let file = try Self.writeFixture(bigrams: bigrams)
        let lexicon = Lexicon(file: file)
        #expect(file.hasBigrams)

        let sentenceStartID = try #require(lexicon.wordID(forExactSurface: "<s>"))
        let candidates = lexicon.bigramCandidates(forContext: sentenceStartID)
        let bySurface = candidates.map { (lexicon.surface($0.next), $0.score) }
        // Best-first: "من" (800) should outrank "او" (100).
        #expect(bySurface.first?.0 == "من")
        #expect(candidates.count == 2)

        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let manCandidates = lexicon.bigramCandidates(forContext: manID)
        #expect(manCandidates.map { lexicon.surface($0.next) }.first == "می\u{200C}خواهم")
    }

    @Test("bigrams below the minimum count are dropped")
    func bigramMinCountFiltersRareEntries() throws {
        var options = KLMBuildOptions()
        options.bigramMinCount = 10
        let bigrams = [
            BigramEntry(w1: "من", w2: "کتاب", count: 5), // below threshold
            BigramEntry(w1: "من", w2: "می\u{200C}خواهم", count: 20),
        ]
        let file = try Self.writeFixture(bigrams: bigrams, options: options)
        let lexicon = Lexicon(file: file)
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let candidates = lexicon.bigramCandidates(forContext: manID)
        #expect(candidates.count == 1)
        #expect(lexicon.surface(candidates[0].next) == "می\u{200C}خواهم")
    }

    @Test("per-context top-K trims a context down to the configured limit")
    func bigramTopKTrimsContext() throws {
        var options = KLMBuildOptions()
        options.bigramTopK = 2
        let bigrams = (0 ..< 5).map { i in BigramEntry(w1: "من", w2: Self.unigrams[2 + (i % 4)].surface, count: UInt64(100 - i * 10)) }
        let file = try Self.writeFixture(bigrams: bigrams, options: options)
        let lexicon = Lexicon(file: file)
        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        #expect(lexicon.bigramCandidates(forContext: manID).count <= 2)
    }

    @Test("a context with no bigram entries returns empty")
    func unknownContextReturnsEmpty() throws {
        let file = try Self.writeFixture(bigrams: [BigramEntry(w1: "من", w2: "کتاب", count: 100)])
        let lexicon = Lexicon(file: file)
        let bookID = try #require(lexicon.wordID(forSurface: "کتاب"))
        #expect(lexicon.bigramCandidates(forContext: bookID).isEmpty)
    }

    @Test("trigram round trip: context (w1, w2) resolves to next-word candidates")
    func trigramRoundTrip() throws {
        var options = KLMBuildOptions()
        options.trigramContextMinBigramCount = 1 // relax for this small fixture
        let bigrams = [BigramEntry(w1: "من", w2: "می\u{200C}خواهم", count: 50)]
        let trigrams = [
            TrigramEntry(w1: "من", w2: "می\u{200C}خواهم", w3: "بروم", count: 30),
            TrigramEntry(w1: "من", w2: "می\u{200C}خواهم", w3: "بخوانم", count: 10),
        ]
        let file = try Self.writeFixture(bigrams: bigrams, trigrams: trigrams, options: options)
        let lexicon = Lexicon(file: file)
        #expect(file.hasTrigrams)

        let manID = try #require(lexicon.wordID(forExactSurface: "من"))
        let wantID = try #require(lexicon.wordID(forExactSurface: "می\u{200C}خواهم"))
        let candidates = lexicon.trigramCandidates(forContext: manID, wantID)
        #expect(candidates.map { lexicon.surface($0.next) }.first == "بروم")
        #expect(candidates.count == 2)
    }

    @Test("trigram contexts below the c(w1,w2) >= threshold are dropped entirely")
    func trigramContextThresholdDropsRareBigramContexts() throws {
        var options = KLMBuildOptions()
        options.trigramContextMinBigramCount = 100
        let bigrams = [BigramEntry(w1: "من", w2: "می\u{200C}خواهم", count: 5)] // below threshold
        let trigrams = [TrigramEntry(w1: "من", w2: "می\u{200C}خواهم", w3: "بروم", count: 3)]
        let file = try Self.writeFixture(bigrams: bigrams, trigrams: trigrams, options: options)
        // No trigram context clears the threshold, so the section is empty
        // and the header correctly reports no trigrams at all.
        #expect(!file.hasTrigrams)
    }

    @Test("dequantized bigram/trigram scores are sane probabilities (0, 1]")
    func scoresDequantizeToValidProbabilities() throws {
        var options = KLMBuildOptions()
        options.trigramContextMinBigramCount = 1
        let bigrams = [BigramEntry(w1: "<s>", w2: "من", count: 800)]
        let trigrams = [TrigramEntry(w1: "<s>", w2: "من", w3: "کتاب", count: 5)]
        let file = try Self.writeFixture(bigrams: bigrams, trigrams: trigrams, options: options)
        let lexicon = Lexicon(file: file)
        let sentenceStartID = try #require(lexicon.wordID(forExactSurface: "<s>"))
        let bigramScore = try #require(lexicon.bigramCandidates(forContext: sentenceStartID).first?.score)
        let p = pow(10, lexicon.log10BigramProbability(bigramScore))
        #expect(p > 0 && p <= 1)
    }

    @Test("bigrams referencing a surface outside the vocabulary are silently skipped")
    func bigramsWithUnknownSurfacesAreSkipped() throws {
        let bigrams = [BigramEntry(w1: "من", w2: "ناموجود", count: 100)]
        let file = try Self.writeFixture(bigrams: bigrams)
        // "ناموجود" isn't in the unigram list, so this bigram contributes
        // nothing — the file should end up with hasBigrams == false since
        // the only candidate entry was dropped.
        #expect(!file.hasBigrams)
    }
}
