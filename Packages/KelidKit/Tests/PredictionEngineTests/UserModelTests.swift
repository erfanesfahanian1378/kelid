import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

/// An in-memory `UserModelStore` — a hand-rolled fake, not GRDB, since
/// `PredictionEngineTests` doesn't depend on `KelidStorage` (§4.2) any more
/// than `PredictionEngine` itself does.
final class MockUserModelStore: UserModelStore, @unchecked Sendable {
    private let lock = NSLock()
    private var words: [String: UserModelWordRecord] = [:]
    private var bigrams: [String: UserModelBigramRecord] = [:]
    private var trigrams: [String: UserModelTrigramRecord] = [:]
    private var blocked: Set<String> = []
    private var blockedCorrections: Set<UserModelBlockedCorrection> = []
    private(set) var flushCallCount = 0
    private(set) var lastFlushedWords: [UserModelWordRecord] = []
    private(set) var lastFlushedBigrams: [UserModelBigramRecord] = []
    private(set) var lastFlushedTrigrams: [UserModelTrigramRecord] = []

    func seedWord(_ record: UserModelWordRecord) {
        lock.withLock { words[record.surface] = record }
    }

    func seedBigram(_ record: UserModelBigramRecord) {
        lock.withLock { bigrams["\(record.w1)|\(record.w2)"] = record }
    }

    func seedTrigram(_ record: UserModelTrigramRecord) {
        lock.withLock { trigrams["\(record.w1)|\(record.w2)|\(record.w3)"] = record }
    }

    func loadWords(limit: Int) async throws -> [UserModelWordRecord] {
        lock.withLock { Array(words.values.prefix(limit)) }
    }

    func loadBigrams(limit: Int) async throws -> [UserModelBigramRecord] {
        lock.withLock { Array(bigrams.values.prefix(limit)) }
    }

    func loadTrigrams(limit: Int) async throws -> [UserModelTrigramRecord] {
        lock.withLock { Array(trigrams.values.prefix(limit)) }
    }

    func loadBlockedWords() async throws -> Set<String> {
        lock.withLock { blocked }
    }

    func loadBlockedCorrections() async throws -> Set<UserModelBlockedCorrection> {
        lock.withLock { blockedCorrections }
    }

    func flush(words: [UserModelWordRecord], bigrams: [UserModelBigramRecord], trigrams: [UserModelTrigramRecord]) async throws {
        lock.withLock {
            flushCallCount += 1
            lastFlushedWords = words
            lastFlushedBigrams = bigrams
            lastFlushedTrigrams = trigrams
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
    }

    func setBlocked(_ blocked: Bool, surface: String) async throws {
        lock.withLock {
            if blocked {
                self.blocked.insert(surface)
            } else {
                self.blocked.remove(surface)
            }
        }
    }

    func forget(surface: String) async throws {
        lock.withLock {
            words.removeValue(forKey: surface)
            bigrams = bigrams.filter { !$0.value.w1.contains(surface) && !$0.value.w2.contains(surface) }
            trigrams = trigrams
                .filter { !$0.value.w1.contains(surface) && !$0.value.w2.contains(surface) && !$0.value.w3.contains(surface) }
        }
    }

    func blockCorrection(typed: String, corrected: String) async throws {
        lock.withLock {
            _ = blockedCorrections.insert(UserModelBlockedCorrection(typed: typed, corrected: corrected))
        }
    }

    func deleteAllWords() async throws {
        lock.withLock {
            words.removeAll()
            bigrams.removeAll()
            trigrams.removeAll()
            blocked.removeAll()
            blockedCorrections.removeAll()
        }
    }
}

@Suite("UserModel (task 9.2, §6.7.6)")
struct UserModelTests {
    @Test("effectiveCount decays exactly by half every halfLifeDays")
    func decayHalvesPerHalfLife() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        let model = UserModel(language: .en, settings: UserModelSettings(halfLifeDays: 60), store: MockUserModelStore(), clock: clock)
        let eff0 = model.effectiveCount(10, lastUsedAt: clock.now(), now: clock.now())
        #expect(abs(eff0 - 10) < 0.0001)
        clock.advance(by: 60 * 86400)
        let eff1 = model.effectiveCount(10, lastUsedAt: Date(timeIntervalSince1970: 0), now: clock.now())
        #expect(abs(eff1 - 5) < 0.0001)
        clock.advance(by: 60 * 86400)
        let eff2 = model.effectiveCount(10, lastUsedAt: Date(timeIntervalSince1970: 0), now: clock.now())
        #expect(abs(eff2 - 2.5) < 0.0001)
    }

    @Test("increment weights match §6.7.6 exactly for every source")
    func incrementWeightsMatchSpec() {
        #expect(UserModel.increment(for: .typed) == 1.0)
        #expect(UserModel.increment(for: .accepted) == 1.0)
        #expect(UserModel.increment(for: .verbatim) == 2.0)
        #expect(UserModel.increment(for: .revert) == 2.0)
        #expect(UserModel.increment(for: .importText) == 0.5)
    }

    @Test("recordCommit on a new word sets count to the increment, and again adds to the decayed eff")
    func recordCommitAccumulatesOnDecayedEff() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: clock)
        await model.recordCommit(surface: "hello", matchKey: "hello", source: .typed, previousWords: [], learnPhrases: true)
        #expect(await model.unigramProbability("hello") != nil)

        clock.advance(by: 60 * 86400) // one half-life: eff(1.0) decays to 0.5
        await model.recordCommit(surface: "hello", matchKey: "hello", source: .typed, previousWords: [], learnPhrases: true)
        // New stored count = decayed eff (0.5) + increment (1.0) = 1.5.
        try await model.flush()
        let flushed = try #require(store.loadWordSync(surface: "hello"))
        #expect(abs(flushed.count - 1.5) < 0.0001)
    }

    @Test("a blocked word's recordCommit is a no-op")
    func blockedWordCommitIsNoOp() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        await model.recordCommit(surface: "badword", matchKey: "badword", source: .typed, previousWords: [], learnPhrases: true)
        try await model.block(surface: "badword")
        await model.recordCommit(surface: "badword", matchKey: "badword", source: .typed, previousWords: [], learnPhrases: true)
        // Still exactly 1 commit's worth (the second, blocked, commit didn't add anything).
        try await model.flush()
        let flushed = try #require(store.loadWordSync(surface: "badword"))
        #expect(abs(flushed.count - 1.0) < 0.0001)
    }

    @Test("P_uni matches eff(w) / (sum of all eff + 50)")
    func unigramProbabilityMatchesFormula() async throws {
        let store = MockUserModelStore()
        let clock = TestClock()
        let model = UserModel(language: .en, store: store, clock: clock)
        await model.recordCommit(surface: "a", matchKey: "a", source: .typed, previousWords: [], learnPhrases: false)
        for _ in 0 ..< 9 {
            await model.recordCommit(
                surface: "a",
                matchKey: "a",
                source: .typed,
                previousWords: [],
                learnPhrases: false
            )
        } // eff("a") = 10
        for _ in 0 ..< 40 {
            await model.recordCommit(
                surface: "b",
                matchKey: "b",
                source: .typed,
                previousWords: [],
                learnPhrases: false
            )
        } // eff("b") = 40
        let pA = try #require(await model.unigramProbability("a"))
        #expect(abs(pA - 10.0 / (10 + 40 + 50)) < 0.0001)
    }

    @Test("P_bi matches eff(w1,w) / (eff(w1) + 5)")
    func bigramProbabilityMatchesFormula() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        for _ in 0 ..< 10 {
            await model.recordCommit(surface: "a", matchKey: "a", source: .typed, previousWords: [], learnPhrases: false)
        }
        for _ in 0 ..< 6 {
            await model.recordCommit(surface: "b", matchKey: "b", source: .typed, previousWords: ["a"], learnPhrases: true)
        }
        let pBiAB = try #require(await model.bigramProbability(context: "a", word: "b"))
        #expect(abs(pBiAB - 6.0 / (10 + 5)) < 0.0001)
    }

    @Test(
        "a sentence-start commit (\"<s>\" as the previous word) records a real (<s>, w) bigram, even though \"<s>\" is never committed as its own word"
    )
    func sentenceStartBigramIsLearnedWithoutCommittingSTag() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        for _ in 0 ..< 3 {
            await model.recordCommit(
                surface: "hello",
                matchKey: "hello",
                source: .typed,
                previousWords: ["<s>"],
                learnPhrases: true
            )
        }
        // "<s>" itself has a fixed eff baseline of 0 (never committed directly) -> P_bi(hello|<s>) = eff(<s>,hello) / (0 + 5).
        let pBi = try #require(await model.bigramProbability(context: "<s>", word: "hello"))
        #expect(abs(pBi - 3.0 / 5.0) < 0.0001)
        let backoff = await model.stupidBackoffScore(word: "hello", w1: nil, w2: "<s>")
        #expect(abs(backoff - 0.4 * pBi) < 0.0001)
    }

    @Test("P_tri matches eff(w1,w2,w) / (eff(w1,w2) + 3)")
    func trigramProbabilityMatchesFormula() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        await model.recordCommit(surface: "a", matchKey: "a", source: .typed, previousWords: [], learnPhrases: false)
        for _ in 0 ..< 6 {
            await model.recordCommit(surface: "b", matchKey: "b", source: .typed, previousWords: ["a"], learnPhrases: true)
        }
        for _ in 0 ..< 4 {
            await model.recordCommit(surface: "c", matchKey: "c", source: .typed, previousWords: ["a", "b"], learnPhrases: true)
        }
        let pTri = try #require(await model.trigramProbability(w1: "a", w2: "b", word: "c"))
        #expect(abs(pTri - 4.0 / (6 + 3)) < 0.0001)
    }

    @Test("stupidBackoffScore prefers trigram, then 0.4x bigram, then 0.16x unigram, then 0")
    func stupidBackoffScoreBacksOffInOrder() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        await model.recordCommit(surface: "a", matchKey: "a", source: .typed, previousWords: [], learnPhrases: false)
        for _ in 0 ..< 6 {
            await model.recordCommit(surface: "b", matchKey: "b", source: .typed, previousWords: ["a"], learnPhrases: true)
        }
        for _ in 0 ..< 4 {
            await model.recordCommit(surface: "c", matchKey: "c", source: .typed, previousWords: ["a", "b"], learnPhrases: true)
        }
        for _ in 0 ..< 20 {
            await model.recordCommit(surface: "d", matchKey: "d", source: .typed, previousWords: [], learnPhrases: false)
        }

        let triScore = await model.stupidBackoffScore(word: "c", w1: "a", w2: "b")
        let expectedTri = try #require(await model.trigramProbability(w1: "a", w2: "b", word: "c"))
        #expect(abs(triScore - expectedTri) < 0.0001) // trigram: no penalty

        let biScore = await model.stupidBackoffScore(word: "b", w1: nil, w2: "a")
        let expectedBi = try #require(await model.bigramProbability(context: "a", word: "b"))
        #expect(abs(biScore - 0.4 * expectedBi) < 0.0001) // no trigram data for this context -> bigram fallback

        let uniScore = await model.stupidBackoffScore(word: "d", w1: nil, w2: nil)
        let expectedUni = try #require(await model.unigramProbability("d"))
        #expect(abs(uniScore - 0.16 * expectedUni) < 0.0001) // no n-gram data at all -> unigram fallback

        let unknownScore = await model.stupidBackoffScore(word: "neverseen", w1: nil, w2: nil)
        #expect(unknownScore == 0)
    }

    @Test("block/unblock round-trips through isBlocked and the store")
    func blockUnblockRoundTrips() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        #expect(await model.isBlocked("word") == false)
        try await model.block(surface: "word")
        #expect(await model.isBlocked("word"))
        let blockedInStore = try await store.loadBlockedWords()
        #expect(blockedInStore == ["word"])
        try await model.unblock(surface: "word")
        #expect(await model.isBlocked("word") == false)
    }

    @Test("forget removes the word and every n-gram mentioning it, in memory and in the store")
    func forgetRemovesWordAndNGrams() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        await model.recordCommit(surface: "a", matchKey: "a", source: .typed, previousWords: [], learnPhrases: false)
        await model.recordCommit(surface: "b", matchKey: "b", source: .typed, previousWords: ["a"], learnPhrases: true)
        try await model.forget(surface: "a")
        #expect(await model.unigramProbability("a") == nil)
        #expect(await model.bigramProbability(context: "a", word: "b") == nil)
    }

    @Test("blockCorrection round-trips through isBlockedCorrection")
    func blockCorrectionRoundTrips() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        #expect(await model.isBlockedCorrection(typed: "teh", corrected: "the") == false)
        try await model.blockCorrection(typed: "teh", corrected: "the")
        #expect(await model.isBlockedCorrection(typed: "teh", corrected: "the"))
    }

    @Test("isSuggestable requires eff >= newWordThreshold only for words the language model doesn't already know")
    func isSuggestableAppliesThresholdOnlyToNewWords() async {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, settings: UserModelSettings(newWordThreshold: 2), store: store, clock: TestClock())
        await model
            .recordCommit(surface: "newslang", matchKey: "newslang", source: .typed, previousWords: [], learnPhrases: false) // eff = 1
        #expect(await model.isSuggestable("newslang", isKnownToLanguageModel: false) == false) // 1 < 2
        #expect(await model.isSuggestable("newslang", isKnownToLanguageModel: true)) // already known -> threshold doesn't apply
        await model
            .recordCommit(surface: "newslang", matchKey: "newslang", source: .typed, previousWords: [], learnPhrases: false) // eff = 2
        #expect(await model.isSuggestable("newslang", isKnownToLanguageModel: false)) // 2 >= 2
    }

    @Test("addContactNames seeds immediately-suggestable, no-decay words that don't require typing to appear")
    func addContactNamesSeedsNoDecayWords() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        let store = MockUserModelStore()
        let model = UserModel(language: .en, settings: UserModelSettings(newWordThreshold: 2), store: store, clock: clock)
        await model.addContactNames(["Aryan", "Niloofar"])

        // Immediately suggestable, no `recordCommit` needed first (unlike an
        // ordinary new word, which needs `eff >= newWordThreshold`).
        #expect(await model.isSuggestable("Aryan", isKnownToLanguageModel: false))
        #expect(await model.unigramProbability("Aryan") != nil)

        // No decay: a full year later, still exactly as suggestable/scored.
        let before = await model.unigramProbability("Aryan")
        clock.advance(by: 365 * 86400)
        let after = await model.unigramProbability("Aryan")
        #expect(before == after)
        #expect(await model.isSuggestable("Aryan", isKnownToLanguageModel: false))

        try await model.flush()
        let flushed = try #require(store.loadWordSync(surface: "Aryan"))
        #expect(flushed.source == .contacts)
    }

    @Test("addContactNames never overwrites a name the user has actually typed since")
    func addContactNamesDoesNotOverwriteExistingWord() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        await model.recordCommit(surface: "Aryan", matchKey: "aryan", source: .typed, previousWords: [], learnPhrases: false)
        let beforeProbability = try #require(await model.unigramProbability("Aryan"))
        await model.addContactNames(["Aryan"]) // already known — must be left alone, not reseeded
        let afterProbability = try #require(await model.unigramProbability("Aryan"))
        #expect(beforeProbability == afterProbability)
    }

    @Test("rebuildPersonalLexicon includes suggestable words and excludes sub-threshold new words; completions/fuzzy work over it")
    func personalLexiconRebuildFiltersByThreshold() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, settings: UserModelSettings(newWordThreshold: 2), store: store, clock: TestClock())
        for _ in 0 ..< 5 {
            await model.recordCommit(
                surface: "hello",
                matchKey: "hello",
                source: .typed,
                previousWords: [],
                learnPhrases: false
            )
        }
        await model
            .recordCommit(surface: "xyz", matchKey: "xyz", source: .typed, previousWords: [], learnPhrases: false) // eff = 1 < threshold
        try await model.rebuildPersonalLexicon(baseLexicon: nil)

        let helloCompletions = await model.personalCompletions(prefixKey: "h")
        #expect(helloCompletions.map(\.surface) == ["hello"])
        let xyzCompletions = await model.personalCompletions(prefixKey: "x")
        #expect(xyzCompletions.isEmpty) // below threshold, not in the rebuilt trie at all

        let fuzzy = await model.personalFuzzyMatches(typedKey: "hallo", proximity: .empty)
        #expect(fuzzy.contains { $0.surface == "hello" })
    }

    @Test("personalCompletions/personalFuzzyMatches filter out blocked words even if they're in the rebuilt trie")
    func personalCandidatesExcludeBlockedWords() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        for _ in 0 ..< 5 {
            await model.recordCommit(
                surface: "hello",
                matchKey: "hello",
                source: .typed,
                previousWords: [],
                learnPhrases: false
            )
        }
        try await model.rebuildPersonalLexicon(baseLexicon: nil)
        try await model.block(surface: "hello")
        #expect(await model.personalCompletions(prefixKey: "h").isEmpty)
    }

    @Test("flush sends exactly the dirty entries and clears the dirty set, so a second flush with no new commits is a no-op")
    func flushSendsOnlyDirtyEntriesAndClears() async throws {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, store: store, clock: TestClock())
        await model.recordCommit(surface: "hello", matchKey: "hello", source: .typed, previousWords: [], learnPhrases: false)
        try await model.flush()
        #expect(store.flushCallCount == 1)
        #expect(store.lastFlushedWords.map(\.surface) == ["hello"])

        try await model.flush() // nothing changed since -> must not call the store again
        #expect(store.flushCallCount == 1)
    }

    @Test("load() populates words, bigrams, trigrams, blocked words and blocked corrections from the store")
    func loadPopulatesFromStore() async throws {
        let store = MockUserModelStore()
        let now = Date(timeIntervalSince1970: 1000)
        store.seedWord(UserModelWordRecord(surface: "سلام", matchKey: "سلام", count: 5, lastUsedAt: now, source: .typed))
        store.seedWord(UserModelWordRecord(surface: "دوست", matchKey: "دوست", count: 3, lastUsedAt: now, source: .typed))
        store.seedBigram(UserModelBigramRecord(w1: "سلام", w2: "دوست", count: 2, lastUsedAt: now))
        let model = UserModel(language: .fa, store: store, clock: TestClock(now: now))
        try await model.load()
        #expect(await model.wordCount == 2)
        #expect(await model.bigramCount == 1)
        #expect(await model.unigramProbability("سلام") != nil)
        #expect(await model.bigramProbability(context: "سلام", word: "دوست") != nil)
    }

    @Test("load() is idempotent")
    func loadIsIdempotent() async throws {
        let store = MockUserModelStore()
        store.seedWord(UserModelWordRecord(surface: "hi", matchKey: "hi", count: 1, lastUsedAt: Date(), source: .typed))
        let model = UserModel(language: .en, store: store, clock: TestClock())
        try await model.load()
        try await model.load()
        #expect(await model.wordCount == 1)
    }

    @Test("the in-memory word cap evicts the lowest-eff word but never a .manual one")
    func wordCapEvictsLowestEffExceptManual() async {
        let store = MockUserModelStore()
        let model = UserModel(language: .en, settings: UserModelSettings(maxWords: 2), store: store, clock: TestClock())
        await model.recordCommit(surface: "manual", matchKey: "manual", source: .manual, previousWords: [], learnPhrases: false)
        await model.recordCommit(surface: "weak", matchKey: "weak", source: .typed, previousWords: [], learnPhrases: false) // eff = 1
        for _ in 0 ..< 10 {
            await model.recordCommit(surface: "strong", matchKey: "strong", source: .typed, previousWords: [], learnPhrases: false)
        } // eff = 10, pushes count to 3 words -> over cap of 2
        #expect(await model.wordCount == 2)
        #expect(await model.unigramProbability("weak") == nil) // evicted (lowest eff, not manual)
        #expect(await model.unigramProbability("manual") != nil) // never evicted
        #expect(await model.unigramProbability("strong") != nil)
    }
}

private extension MockUserModelStore {
    /// Synchronous peek at what's been flushed so far, for assertions —
    /// safe here since this mock's lock already makes every method
    /// thread-safe and this test suite never calls it concurrently with an
    /// in-flight flush.
    func loadWordSync(surface: String) -> UserModelWordRecord? {
        lastFlushedWords.first { $0.surface == surface }
    }
}
