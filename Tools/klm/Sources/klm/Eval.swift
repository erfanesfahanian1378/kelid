import Dispatch
import KelidCore
import PersianText
import PredictionEngine

/// §6.7.12's evaluation harness (task 8.9): KSR, next-word top-1/top-3,
/// correction accuracy (synthetic typos) and completion latency, computed
/// against a real `.klm` file and a held-out corpus (one sentence per
/// line, whitespace-tokenized — already-normalized text, matching
/// `eval/{fa_formal,fa_informal,en}.txt`'s own format, task 6.13).
///
/// Deterministic given `typoSeed`: the typo generator is a local
/// `SplitMix64`, not `SystemRandomNumberGenerator`, so two runs against the
/// same model/corpus produce identical correction-accuracy numbers —
/// necessary for "any later change that lowers KSR by more than 1 point
/// needs a decision-log entry" to mean anything.
enum Eval {
    struct Metrics {
        var wordCount: Int
        var ksr: Double
        var nextWordTop1: Double
        var nextWordTop3: Double
        var nextWordSampleCount: Int
        var correctionTop1: Double
        var correctionTop3: Double
        var correctionSampleCount: Int
        var latencyP50Ms: Double
        var latencyP95Ms: Double
    }

    static func run(lexicon: Lexicon, sentences: [[String]], proximity: FuzzyProximityMap, typoSeed: UInt64 = 42) -> Metrics {
        let wordCount = sentences.reduce(0) { $0 + $1.count }
        let ksr = keystrokeSavingsRate(lexicon: lexicon, sentences: sentences)
        let nextWord = nextWordAccuracy(lexicon: lexicon, sentences: sentences)
        let correction = correctionAccuracy(lexicon: lexicon, sentences: sentences, proximity: proximity, seed: typoSeed)
        let latency = latencyPercentiles(lexicon: lexicon, sentences: sentences)
        return Metrics(
            wordCount: wordCount,
            ksr: ksr,
            nextWordTop1: nextWord.top1,
            nextWordTop3: nextWord.top3,
            nextWordSampleCount: nextWord.sampleCount,
            correctionTop1: correction.top1,
            correctionTop3: correction.top3,
            correctionSampleCount: correction.sampleCount,
            latencyP50Ms: latency.p50,
            latencyP95Ms: latency.p95
        )
    }

    // MARK: - KSR (keystroke savings rate)

    /// Simulates typing each word one character at a time against 3 visible
    /// completion slots; the "user" accepts as soon as the target word
    /// appears. `1 - actual/naive` over the whole corpus.
    static func keystrokeSavingsRate(lexicon: Lexicon, sentences: [[String]]) -> Double {
        var naiveTotal = 0
        var actualTotal = 0
        for words in sentences {
            for word in words {
                let key = PersianNormalization.matchKey(word)
                guard !key.isEmpty else { continue }
                naiveTotal += key.count + 1 // every letter, plus the space that commits it
                var accepted = false
                for prefixLength in 0 ..< key.count {
                    let prefixKey = String(key.prefix(prefixLength))
                    let completions = lexicon.completions(prefixKey: prefixKey, limit: 3)
                    if completions.contains(where: { PersianNormalization.matchKey($0.surface) == key }) {
                        actualTotal += prefixLength + 1 // letters typed so far, plus the accept tap
                        accepted = true
                        break
                    }
                }
                if !accepted {
                    actualTotal += key.count + 1
                }
            }
        }
        guard naiveTotal > 0 else { return 0 }
        return 1 - Double(actualTotal) / Double(naiveTotal)
    }

    // MARK: - Next-word accuracy

    static func nextWordAccuracy(lexicon: Lexicon, sentences: [[String]]) -> (top1: Double, top3: Double, sampleCount: Int) {
        var top1Hits = 0
        var top3Hits = 0
        var total = 0
        for words in sentences {
            var previousWords: [String] = []
            for word in words {
                let contextIDs = resolveContextIDs(previousWords: previousWords, lexicon: lexicon)
                let candidates = BackoffScorer.nextWords(lexicon: lexicon, w1: contextIDs.w1, w2: contextIDs.w2, limit: 20)
                if !candidates.isEmpty {
                    total += 1
                    let targetKey = PersianNormalization.matchKey(word)
                    if let first = candidates.first, PersianNormalization.matchKey(first.surface) == targetKey {
                        top1Hits += 1
                    }
                    if candidates.prefix(3).contains(where: { PersianNormalization.matchKey($0.surface) == targetKey }) {
                        top3Hits += 1
                    }
                }
                previousWords.append(word)
            }
        }
        guard total > 0 else { return (0, 0, 0) }
        return (Double(top1Hits) / Double(total), Double(top3Hits) / Double(total), total)
    }

    private static func resolveContextIDs(previousWords: [String], lexicon: Lexicon) -> (w1: UInt32?, w2: UInt32?) {
        guard let last = previousWords.last else { return (nil, nil) }
        let w2 = lexicon.wordID(forExactSurface: last)
        guard previousWords.count >= 2 else { return (nil, w2) }
        let w1 = lexicon.wordID(forExactSurface: previousWords[previousWords.count - 2])
        return (w1, w2)
    }

    // MARK: - Correction accuracy (synthetic typos)

    static func correctionAccuracy(
        lexicon: Lexicon,
        sentences: [[String]],
        proximity: FuzzyProximityMap,
        seed: UInt64
    ) -> (top1: Double, top3: Double, sampleCount: Int) {
        var generator = SplitMix64(seed: seed)
        var top1Hits = 0
        var top3Hits = 0
        var sampleCount = 0
        for words in sentences {
            for word in words {
                let key = PersianNormalization.matchKey(word)
                guard key.count >= 3, lexicon.wordID(forSurface: word) != nil else { continue }
                for kind in TypoKind.allCases {
                    guard let typo = kind.apply(to: key, proximity: proximity, using: &generator), typo != key else { continue }
                    sampleCount += 1
                    let maxCost = Lexicon.fuzzyMaxCost(forTypedLength: typo.count)
                    let matches = lexicon.fuzzyMatches(typedKey: typo, proximity: proximity, prefixMode: false, limit: 5)
                        .filter { $0.editCost <= maxCost }
                    let ranked = Ranker.rank(fuzzy: matches, typedKey: typo, lexicon: lexicon)
                    if let first = ranked.first, PersianNormalization.matchKey(first.surface) == key {
                        top1Hits += 1
                    }
                    if ranked.prefix(3).contains(where: { PersianNormalization.matchKey($0.surface) == key }) {
                        top3Hits += 1
                    }
                }
            }
        }
        guard sampleCount > 0 else { return (0, 0, 0) }
        return (Double(top1Hits) / Double(sampleCount), Double(top3Hits) / Double(sampleCount), sampleCount)
    }

    // MARK: - Latency

    static func latencyPercentiles(lexicon: Lexicon, sentences: [[String]]) -> (p50: Double, p95: Double) {
        let words = sentences.flatMap(\.self).prefix(500)
        guard !words.isEmpty else { return (0, 0) }
        var samplesMs: [Double] = []
        samplesMs.reserveCapacity(words.count)
        for word in words {
            let key = PersianNormalization.matchKey(word)
            let prefixKey = String(key.prefix(max(1, key.count / 2)))
            let start = DispatchTime.now()
            _ = lexicon.completions(prefixKey: prefixKey, limit: 20)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            samplesMs.append(elapsedMs)
        }
        samplesMs.sort()
        return (percentile(samplesMs, 0.50), percentile(samplesMs, 0.95))
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[index]
    }

    // MARK: - Personalization (task 9.11)

    struct PersonalizationMetrics {
        var trainSentenceCount: Int
        var evalSentenceCount: Int
        var languageOnlyKSR: Double
        var hybridKSR: Double
    }

    /// "Simulate learning from half of `fa_informal` and measure KSR on the
    /// other half, hybrid vs language-only." The first half's words feed a
    /// real `UserModel` via `recordCommit(source: .typed)`, exactly as if
    /// the user had actually typed and committed every one of them; the
    /// second half is then scored twice — once with plain `Lexicon.completions`
    /// (`languageOnlyKSR`, identical math to `keystrokeSavingsRate` above)
    /// and once with `S = λ·S_user + (1−λ)·S_lang`-blended completions
    /// (`hybridKSR`) — so the delta between the two isolates exactly what
    /// personalization bought on genuinely unseen-by-this-measurement text.
    static func runWithPersonalization(
        lexicon: Lexicon, sentences: [[String]], personalWeight: Double = 0.6
    ) async -> PersonalizationMetrics {
        let splitIndex = sentences.count / 2
        let trainSentences = Array(sentences.prefix(splitIndex))
        let evalSentences = Array(sentences.suffix(sentences.count - splitIndex))

        let store = InMemoryUserModelStore()
        let userModel = UserModel(language: .fa, store: store)
        for words in trainSentences {
            var previousWords: [String] = []
            for word in words {
                let matchKey = PersianNormalization.matchKey(word)
                guard !matchKey.isEmpty else { continue }
                await userModel.recordCommit(
                    surface: word, matchKey: matchKey, source: .typed, previousWords: previousWords, learnPhrases: true
                )
                previousWords.append(word)
                if previousWords.count > 2 {
                    previousWords.removeFirst()
                }
            }
        }
        let languageOnlyKSR = keystrokeSavingsRate(lexicon: lexicon, sentences: evalSentences)
        let hybridKSR = await keystrokeSavingsRateHybrid(
            lexicon: lexicon, userModel: userModel, sentences: evalSentences, personalWeight: personalWeight
        )
        return PersonalizationMetrics(
            trainSentenceCount: trainSentences.count, evalSentenceCount: evalSentences.count,
            languageOnlyKSR: languageOnlyKSR, hybridKSR: hybridKSR
        )
    }

    /// Same simulation as `keystrokeSavingsRate`, but the 3 visible slots
    /// are chosen by `S(w|ctx) = λ·S_user + (1−λ)·S_lang` (§6.7.5/§6.7.7),
    /// not raw language-model frequency alone — `Ranker.rank(completions:...)`
    /// is the exact same blending code `SuggestionService` itself uses.
    private static func keystrokeSavingsRateHybrid(
        lexicon: Lexicon, userModel: UserModel, sentences: [[String]], personalWeight: Double
    ) async -> Double {
        var naiveTotal = 0
        var actualTotal = 0
        let rankerConfig = RankerConfig(personalWeight: personalWeight)
        for words in sentences {
            var previousWords: [String] = []
            for word in words {
                let key = PersianNormalization.matchKey(word)
                guard !key.isEmpty else { continue }
                naiveTotal += key.count + 1
                let w1: String? = previousWords.count >= 2 ? previousWords[previousWords.count - 2] : nil
                let w2 = previousWords.last
                var accepted = false
                for prefixLength in 0 ..< key.count {
                    let prefixKey = String(key.prefix(prefixLength))
                    let completions = lexicon.completions(prefixKey: prefixKey, limit: 32)
                    var personalScores: [String: Double] = [:]
                    for completion in completions {
                        personalScores[PersianNormalization.matchKey(completion.surface)] = await userModel.stupidBackoffScore(
                            word: completion.surface, w1: w1, w2: w2
                        )
                    }
                    let ranked = Ranker.rank(
                        completions: completions, typedKey: prefixKey, lexicon: lexicon, personalScores: personalScores,
                        config: rankerConfig
                    )
                    let top3 = ranked.sorted { $0.score > $1.score }.prefix(3)
                    if top3.contains(where: { PersianNormalization.matchKey($0.surface) == key }) {
                        actualTotal += prefixLength + 1
                        accepted = true
                        break
                    }
                }
                if !accepted {
                    actualTotal += key.count + 1
                }
                previousWords.append(word)
                if previousWords.count > 2 {
                    previousWords.removeFirst()
                }
            }
        }
        guard naiveTotal > 0 else { return 0 }
        return 1 - Double(actualTotal) / Double(naiveTotal)
    }
}

/// A minimal, process-local `UserModelStore` for `runWithPersonalization`'s
/// simulation — `klm` has no database at all (§4.2: it doesn't depend on
/// `KelidStorage`), and this eval run never needs to persist anything
/// beyond its own process lifetime anyway, so an in-memory `actor` is the
/// simplest thing that satisfies the protocol.
actor InMemoryUserModelStore: UserModelStore {
    private var words: [String: UserModelWordRecord] = [:]
    private var bigrams: [String: UserModelBigramRecord] = [:]
    private var trigrams: [String: UserModelTrigramRecord] = [:]
    private var blocked: Set<String> = []
    private var blockedCorrections: Set<UserModelBlockedCorrection> = []

    func loadWords(limit: Int) async throws -> [UserModelWordRecord] {
        Array(words.values.prefix(limit))
    }

    func loadBigrams(limit: Int) async throws -> [UserModelBigramRecord] {
        Array(bigrams.values.prefix(limit))
    }

    func loadTrigrams(limit: Int) async throws -> [UserModelTrigramRecord] {
        Array(trigrams.values.prefix(limit))
    }

    func loadBlockedWords() async throws -> Set<String> {
        blocked
    }

    func loadBlockedCorrections() async throws -> Set<UserModelBlockedCorrection> {
        blockedCorrections
    }

    func flush(words: [UserModelWordRecord], bigrams: [UserModelBigramRecord], trigrams: [UserModelTrigramRecord]) async throws {
        for word in words {
            self.words[word.surface] = word
        }
        for bigram in bigrams {
            self.bigrams["\(bigram.w1)|\(bigram.w2)"] = bigram
        }
        for trigram in trigrams {
            self.trigrams["\(trigram.w1)|\(trigram.w2)|\(trigram.w3)"] = trigram
        }
    }

    func setBlocked(_ blocked: Bool, surface: String) async throws {
        if blocked {
            self.blocked.insert(surface)
        } else {
            self.blocked.remove(surface)
        }
    }

    func forget(surface: String) async throws {
        words.removeValue(forKey: surface)
    }

    func blockCorrection(typed: String, corrected: String) async throws {
        blockedCorrections.insert(UserModelBlockedCorrection(typed: typed, corrected: corrected))
    }

    func deleteAllWords() async throws {
        words.removeAll()
        bigrams.removeAll()
        trigrams.removeAll()
        blocked.removeAll()
        blockedCorrections.removeAll()
    }
}

/// §6.7.12's 4 typo categories, plus adjacent-key substitution — each a
/// pure, seeded transformation of a match key so results are reproducible.
enum TypoKind: CaseIterable {
    case deletion
    case insertion
    case transposition
    case homophone
    case adjacentKey

    func apply(to key: String, proximity _: FuzzyProximityMap, using generator: inout SplitMix64) -> String? {
        var chars = Array(key)
        guard chars.count >= 2 else { return nil }
        switch self {
        case .deletion:
            let index = Int.random(in: 0 ..< chars.count, using: &generator)
            chars.remove(at: index)
            return String(chars)

        case .insertion:
            let index = Int.random(in: 0 ..< chars.count, using: &generator)
            chars.insert(chars[index], at: index) // a doubled-letter fat-finger, §6.7.3's own insertion model
            return String(chars)

        case .transposition:
            let index = Int.random(in: 0 ..< chars.count - 1, using: &generator)
            chars.swapAt(index, index + 1)
            return String(chars)

        case .homophone:
            let candidates = chars.indices.filter { EvalKeyAdjacency.persianConfusionGroupMembers(chars[$0]) != nil }
            guard !candidates.isEmpty else { return nil } // no Persian confusion-group letters in this word (e.g. plain English)
            let index = candidates.randomElement(using: &generator)!
            guard let members = EvalKeyAdjacency.persianConfusionGroupMembers(chars[index]),
                  let replacement = members.filter({ $0 != chars[index] }).randomElement(using: &generator)
            else {
                return nil
            }
            chars[index] = replacement
            return String(chars)

        case .adjacentKey:
            let candidates = chars.indices.filter { !EvalKeyAdjacency.neighbors(of: chars[$0]).isEmpty }
            guard !candidates.isEmpty else { return nil }
            let index = candidates.randomElement(using: &generator)!
            guard let replacement = EvalKeyAdjacency.neighbors(of: chars[index]).randomElement(using: &generator) else { return nil }
            chars[index] = replacement
            return String(chars)
        }
    }
}

/// A small, self-contained key-adjacency table for the eval harness's
/// synthetic "adjacent-key substitution" typos — `klm` doesn't depend on
/// `KeyboardLayout` (§4.2's module table), so this is a reasonable
/// standalone approximation of the real `fa.standard`/`en.standard`
/// layouts' geometry, not the real `ProximityMap` `KeyboardUI` builds.
enum EvalKeyAdjacency {
    private static let englishRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let persianRows = ["ضصثقفغعهخحج", "شسیبلاتنمک", "ظطزرذدپو"]

    static func neighbors(of char: Character) -> [Character] {
        for row in englishRows + persianRows {
            if let index = row.firstIndex(of: char) {
                var result: [Character] = []
                if index > row.startIndex {
                    result.append(row[row.index(before: index)])
                }
                if row.index(after: index) < row.endIndex {
                    result.append(row[row.index(after: index)])
                }
                return result
            }
        }
        return []
    }

    /// Reuses `PersianText.PersianConfusionGroups`' own pairwise cost table
    /// indirectly — walks a small fixed group list matching §6.6.6's
    /// exactly, since that type only exposes pairwise cost lookups, not
    /// "all members of a" group.
    private static let groups: [[Character]] = [
        ["ا", "آ"], ["ی", "ئ"], ["و", "ؤ"], ["ت", "ط"],
        ["س", "ص", "ث"], ["ز", "ذ", "ض", "ظ"], ["ه", "ح"], ["ق", "غ"], ["ا", "ع"],
    ]

    static func persianConfusionGroupMembers(_ char: Character) -> [Character]? {
        groups.first { $0.contains(char) }
    }
}

/// Seeded, deterministic PRNG (SplitMix64) — the same algorithm already
/// used by `PredictionEngineTests`' own property-based tests, reimplemented
/// here since `klm` can't `@testable import` another package's test target.
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
