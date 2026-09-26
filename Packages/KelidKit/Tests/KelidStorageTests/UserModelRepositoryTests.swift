import Foundation
import KelidCore
@testable import KelidStorage
import Testing

/// Not its own `@Suite`: these tests are declared as an extension of
/// `DatabaseManagerTests` (in DatabaseManagerTests.swift) specifically so
/// they share that type's `.serialized` suite rather than getting a second,
/// independently-scheduled one — see that file's own comment. Two separate
/// `.serialized` suites are each internally ordered but can still run
/// *concurrently with each other*, and empirically did: this file's own
/// `UserModelRepository`/`DatabaseManager` calls (`flush`/`prune`/`merge`,
/// all going through the same real suspend/resume machinery
/// `DatabaseManagerTests` exercises directly) intermittently hit "Database
/// is suspended" errors when the two suites' tests happened to interleave.
extension DatabaseManagerTests {
    private func makeUserModelRepository() async throws -> (repository: UserModelRepository, cleanup: () -> Void) {
        let url = tempDatabaseURL()
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()
        return (UserModelRepository(database: manager), { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
    }

    @Test("flush inserts new words, bigrams and trigrams")
    func flushInsertsNewRows() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        let now = Date()
        try await repository.flush(
            language: .fa,
            words: [UserWordDelta(surface: "سلام", matchKey: "سلام", count: 1.0, lastUsedAt: now, source: .typed)],
            bigrams: [UserBigramDelta(w1: "سلام", w2: "دوست", count: 1.0, lastUsedAt: now)],
            trigrams: [UserTrigramDelta(w1: "سلام", w2: "دوست", w3: "من", count: 1.0, lastUsedAt: now)]
        )
        let words = try await repository.loadWords(language: .fa, limit: 10)
        let bigrams = try await repository.loadBigrams(language: .fa, limit: 10)
        let trigrams = try await repository.loadTrigrams(language: .fa, limit: 10)
        #expect(words.map(\.surface) == ["سلام"])
        #expect(bigrams.count == 1)
        #expect(trigrams.count == 1)
    }

    @Test("flush on an existing word updates count/lastUsedAt in place rather than duplicating")
    func flushUpdatesExistingWord() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        try await repository.flush(
            language: .en, words: [UserWordDelta(surface: "hello", matchKey: "hello", count: 1.0, lastUsedAt: t1, source: .typed)],
            bigrams: [], trigrams: []
        )
        try await repository.flush(
            language: .en, words: [UserWordDelta(surface: "hello", matchKey: "hello", count: 2.5, lastUsedAt: t2, source: .typed)],
            bigrams: [], trigrams: []
        )
        let words = try await repository.loadWords(language: .en, limit: 10)
        #expect(words.count == 1)
        #expect(words[0].count == 2.5)
        #expect(words[0].lastUsedAt == t2)
    }

    @Test("setBlocked marks a word blocked, and loadBlockedWords reflects it")
    func setBlockedMarksWord() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        try await repository.flush(
            language: .fa, words: [UserWordDelta(surface: "خفن", matchKey: "خفن", count: 1.0, lastUsedAt: Date(), source: .typed)],
            bigrams: [], trigrams: []
        )
        try await repository.setBlocked(true, surface: "خفن", language: .fa)
        let blocked = try await repository.loadBlockedWords(language: .fa)
        #expect(blocked == ["خفن"])
        try await repository.setBlocked(false, surface: "خفن", language: .fa)
        let unblocked = try await repository.loadBlockedWords(language: .fa)
        #expect(unblocked.isEmpty)
    }

    @Test("forget deletes the word and every n-gram that mentions it")
    func forgetDeletesWordAndNGrams() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        let now = Date()
        try await repository.flush(
            language: .fa,
            words: [
                UserWordDelta(surface: "سلام", matchKey: "سلام", count: 1.0, lastUsedAt: now, source: .typed),
                UserWordDelta(surface: "دوست", matchKey: "دوست", count: 1.0, lastUsedAt: now, source: .typed),
            ],
            bigrams: [
                UserBigramDelta(w1: "سلام", w2: "دوست", count: 1.0, lastUsedAt: now),
                UserBigramDelta(w1: "دوست", w2: "من", count: 1.0, lastUsedAt: now),
            ],
            trigrams: [UserTrigramDelta(w1: "سلام", w2: "دوست", w3: "من", count: 1.0, lastUsedAt: now)]
        )
        try await repository.forget(surface: "سلام", language: .fa)
        let words = try await repository.loadWords(language: .fa, limit: 10)
        let bigrams = try await repository.loadBigrams(language: .fa, limit: 10)
        let trigrams = try await repository.loadTrigrams(language: .fa, limit: 10)
        #expect(words.map(\.surface) == ["دوست"]) // "سلام" gone, "دوست" untouched
        #expect(bigrams.map(\.w1) == ["دوست"]) // the (سلام, دوست) bigram is gone
        #expect(trigrams.isEmpty) // the trigram mentions سلام
    }

    @Test("blockCorrection records the pair, and a duplicate is silently ignored")
    func blockCorrectionRecordsPair() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        try await repository.blockCorrection(typed: "teh", corrected: "the", language: .en)
        try await repository.blockCorrection(typed: "teh", corrected: "the", language: .en) // duplicate, must not throw
        let blocked = try await repository.loadBlockedCorrections(language: .en)
        #expect(blocked == [BlockedCorrectionPair(typed: "teh", corrected: "the")])
    }

    @Test("prune deletes the lowest-eff words (and their n-grams) once over the cap, but never .manual words")
    func pruneDeletesLowestEffExceptManual() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        let now = Date()
        let longAgo = now.addingTimeInterval(-1000 * 86400) // 1000 days ago -> decays to ~0 with a 60-day half-life
        try await repository.flush(
            language: .en,
            words: [
                UserWordDelta(surface: "fresh", matchKey: "fresh", count: 10, lastUsedAt: now, source: .typed),
                UserWordDelta(surface: "stale", matchKey: "stale", count: 10, lastUsedAt: longAgo, source: .typed),
                UserWordDelta(surface: "kept", matchKey: "kept", count: 1, lastUsedAt: longAgo, source: .manual),
            ],
            bigrams: [UserBigramDelta(w1: "stale", w2: "word", count: 1, lastUsedAt: longAgo)],
            trigrams: []
        )
        try await repository.prune(language: .en, keepingTop: 2, halfLifeDays: 60, now: now)
        let words = try await repository.loadWords(language: .en, limit: 10)
        #expect(Set(words.map(\.surface)) == ["fresh", "kept"]) // "stale" (lowest eff, not manual) pruned
        let bigrams = try await repository.loadBigrams(language: .en, limit: 10)
        #expect(bigrams.isEmpty) // the bigram mentioning the pruned word is gone too
    }

    @Test("prune is a no-op when at or under the cap")
    func pruneNoOpUnderCap() async throws {
        let (repository, cleanup) = try await makeUserModelRepository()
        defer { cleanup() }
        try await repository.flush(
            language: .en, words: [UserWordDelta(surface: "hello", matchKey: "hello", count: 1, lastUsedAt: Date(), source: .typed)],
            bigrams: [], trigrams: []
        )
        try await repository.prune(language: .en, keepingTop: 10, halfLifeDays: 60, now: Date())
        let words = try await repository.loadWords(language: .en, limit: 10)
        #expect(words.count == 1)
    }

    @Test("merge sums counts, keeps the max lastUsedAt, unions blocked flags and blocked corrections")
    func mergeCombinesLocalIntoShared() async throws {
        let (shared, sharedCleanup) = try await makeUserModelRepository()
        defer { sharedCleanup() }
        let (local, localCleanup) = try await makeUserModelRepository()
        defer { localCleanup() }

        let sharedTime = Date(timeIntervalSince1970: 1000)
        let localTime = Date(timeIntervalSince1970: 2000) // more recent than sharedTime
        try await shared.flush(
            language: .fa, words: [UserWordDelta(surface: "سلام", matchKey: "سلام", count: 3, lastUsedAt: sharedTime, source: .typed)],
            bigrams: [], trigrams: []
        )
        try await local.flush(
            language: .fa,
            words: [
                UserWordDelta(surface: "سلام", matchKey: "سلام", count: 2, lastUsedAt: localTime, source: .typed),
                UserWordDelta(surface: "خداحافظ", matchKey: "خداحافظ", count: 1, lastUsedAt: localTime, source: .typed),
            ],
            bigrams: [UserBigramDelta(w1: "سلام", w2: "عزیز", count: 1, lastUsedAt: localTime)],
            trigrams: []
        )
        try await local.setBlocked(true, surface: "خداحافظ", language: .fa)
        try await local.blockCorrection(typed: "slam", corrected: "سلام", language: .fa)

        try await shared.merge(from: local, language: .fa)

        let mergedWords = try await shared.loadWords(language: .fa, limit: 10)
        let salaam = try #require(mergedWords.first { $0.surface == "سلام" })
        #expect(salaam.count == 5) // 3 (shared) + 2 (local)
        #expect(salaam.lastUsedAt == localTime) // max(sharedTime, localTime)
        let khodahafez = try #require(mergedWords.first { $0.surface == "خداحافظ" })
        #expect(khodahafez.isBlocked) // a brand-new merged word keeps its local isBlocked flag

        let mergedBigrams = try await shared.loadBigrams(language: .fa, limit: 10)
        #expect(mergedBigrams.map(\.w2) == ["عزیز"])

        let mergedCorrections = try await shared.loadBlockedCorrections(language: .fa)
        #expect(mergedCorrections == [BlockedCorrectionPair(typed: "slam", corrected: "سلام")])
    }
}
