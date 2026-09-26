import Foundation
import KelidCore
@testable import PersianText
@testable import PredictionEngine
import Testing

/// Task 7.3/7.12's required property test: "Best-first completions equal
/// brute-force top-K on random prefixes."
@Suite("Lexicon completions vs. brute force")
struct LexiconPropertyTests {
    /// A deterministic (seeded) random vocabulary so a failure is
    /// reproducible — mixes Persian and English "words" (random letter
    /// strings, not real words, since only trie/ranking behavior is under
    /// test here, not real-language plausibility).
    static func randomVocabulary(seed: UInt64, count: Int) -> [UnigramEntry] {
        var generator = SplitMix64(seed: seed)
        let persianLetters = Array("ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی")
        let englishLetters = Array("abcdefghijklmnopqrstuvwxyz")
        var entries: [UnigramEntry] = []
        var seenSurfaces = Set<String>()
        while entries.count < count {
            let usePersian = Bool.random(using: &generator)
            let alphabet = usePersian ? persianLetters : englishLetters
            let length = Int.random(in: 1 ... 6, using: &generator)
            let surface = String((0 ..< length).map { _ in alphabet.randomElement(using: &generator)! })
            guard !seenSurfaces.contains(surface) else { continue }
            seenSurfaces.insert(surface)
            entries.append(UnigramEntry(surface: surface, count: UInt64.random(in: 1 ... 100_000, using: &generator)))
        }
        return entries
    }

    /// Brute-force reference implementation: every word whose match key
    /// starts with `prefixKey`, sorted the same way `Lexicon.completions`
    /// promises to sort (score descending, id ascending), truncated to
    /// `limit`.
    static func bruteForceCompletions(
        vocabulary _: [UnigramEntry],
        prefixKey: String,
        limit: Int,
        wordIDByMatchKey: [(matchKey: String, id: UInt32, score: UInt8)]
    ) -> [UInt32] {
        wordIDByMatchKey
            .filter { $0.matchKey.hasPrefix(prefixKey) }
            .sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
            .prefix(limit)
            .map(\.id)
    }

    @Test("random prefixes: best-first search returns exactly the brute-force top-K", arguments: [1, 2, 3, 4, 5])
    func bestFirstMatchesBruteForce(seed: Int) throws {
        let vocabulary = Self.randomVocabulary(seed: UInt64(seed), count: 300)
        let data = try KLMWriter.build(language: .fa, unigrams: vocabulary, maxWords: 200_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-klm-property-\(UUID().uuidString).klm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try KLMFile(path: url.path)
        let lexicon = Lexicon(file: file)

        // Sorted-by-frequency order determines word ids the same way
        // `KLMWriter` does, so the brute-force reference and the file agree
        // on which id belongs to which surface.
        let sortedByFrequency = vocabulary.sorted { $0.count == $1.count ? $0.surface < $1.surface : $0.count > $1.count }
        let wordIDByMatchKey = sortedByFrequency.enumerated().map { index, entry in
            (matchKey: PersianNormalization.matchKey(entry.surface), id: UInt32(index), score: file.score(UInt32(index)))
        }

        var generator = SplitMix64(seed: UInt64(seed) &+ 1000)
        for _ in 0 ..< 20 {
            // Random prefix: take a random word's match key and truncate it,
            // so at least some prefixes are guaranteed to have matches.
            let sample = try #require(wordIDByMatchKey.randomElement(using: &generator)?.matchKey)
            let prefixLength = Int.random(in: 0 ... sample.count, using: &generator)
            let prefixKey = String(sample.prefix(prefixLength))

            let limit = Int.random(in: 1 ... 20, using: &generator)
            let expected = Self.bruteForceCompletions(
                vocabulary: vocabulary,
                prefixKey: prefixKey,
                limit: limit,
                wordIDByMatchKey: wordIDByMatchKey
            )
            let actual = lexicon.completions(prefixKey: prefixKey, limit: limit).map(\.wordID)
            #expect(actual == expected, "prefix=\(prefixKey) limit=\(limit)")
        }
    }
}

/// A tiny deterministic PRNG (SplitMix64) so these tests are reproducible
/// without pulling in a third-party dependency just for test fixtures.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
