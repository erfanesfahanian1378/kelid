import Foundation
import GRDB
import KelidCore
import PersianText

/// A `(typed, corrected)` pair a user has explicitly rejected — §6.7.8:
/// "Reverting an autocorrect adds the pair `(typed → corrected)` to
/// `blockedCorrections`."
public struct BlockedCorrectionPair: Sendable, Hashable {
    public let typed: String
    public let corrected: String

    public init(typed: String, corrected: String) {
        self.typed = typed
        self.corrected = corrected
    }
}

/// One dirty word entry as `UserModel`'s (§6.7.6) write-behind flush hands
/// it to the repository — the *final* count/lastUsedAt after decay +
/// increment, not a delta to add, so a plain upsert (not a SQL `+=`) is
/// always correct.
public struct UserWordDelta: Sendable, Equatable {
    public let surface: String
    public let matchKey: String
    public let count: Double
    public let lastUsedAt: Date
    public let source: UserWordSource

    public init(surface: String, matchKey: String, count: Double, lastUsedAt: Date, source: UserWordSource) {
        self.surface = surface
        self.matchKey = matchKey
        self.count = count
        self.lastUsedAt = lastUsedAt
        self.source = source
    }
}

public struct UserBigramDelta: Sendable, Equatable {
    public let w1: String
    public let w2: String
    public let count: Double
    public let lastUsedAt: Date

    public init(w1: String, w2: String, count: Double, lastUsedAt: Date) {
        self.w1 = w1
        self.w2 = w2
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

public struct UserTrigramDelta: Sendable, Equatable {
    public let w1: String
    public let w2: String
    public let w3: String
    public let count: Double
    public let lastUsedAt: Date

    public init(w1: String, w2: String, w3: String, count: Double, lastUsedAt: Date) {
        self.w1 = w1
        self.w2 = w2
        self.w3 = w3
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

/// Task 9.1: persistence for `UserModel` (§6.7.6) — batch UPSERT of the
/// write-behind dirty set, capped loads for the in-memory model, block/
/// unblock/forget, pruning, and local→shared merge (§6.11.2's no-Full-
/// Access fallback).
public actor UserModelRepository {
    private let database: DatabaseManager
    private let darwinNotifier: DarwinNotifier
    private let appGroupIdentifier: String?

    public init(database: DatabaseManager, darwinNotifier: DarwinNotifier = .shared, appGroupIdentifier: String? = AppGroup.identifier) {
        self.database = database
        self.darwinNotifier = darwinNotifier
        self.appGroupIdentifier = appGroupIdentifier
    }

    /// Task 10.6: the app's Dictionary manager edits this same database a
    /// running keyboard's `UserModel` already loaded into memory — without
    /// this, a block/forget/add/reset made from the app would silently not
    /// reach a keyboard already on screen until its process restarted.
    /// `PredictionEngine.SuggestionService` observes this (task 9.2's own
    /// "reload on `.userdict.changed`," never actually wired until now) and
    /// reloads the affected `UserModel`.
    private func notifyChanged() {
        darwinNotifier.post(.userDictChanged, appGroupIdentifier: appGroupIdentifier)
    }

    // MARK: - Write-behind flush (§6.7.6: "one transaction of UPSERTs")

    public func flush(
        language: LanguageID,
        words: [UserWordDelta],
        bigrams: [UserBigramDelta],
        trigrams: [UserTrigramDelta]
    ) async throws {
        guard !words.isEmpty || !bigrams.isEmpty || !trigrams.isEmpty else { return }
        try await database.write { db in
            for delta in words {
                if var existing = try UserWord
                    .filter(Column("lang") == language.rawValue && Column("surface") == delta.surface)
                    .fetchOne(db)
                {
                    existing.count = delta.count
                    existing.lastUsedAt = delta.lastUsedAt
                    try existing.update(db)
                } else {
                    var word = UserWord(
                        language: language,
                        surface: delta.surface,
                        matchKey: delta.matchKey,
                        count: delta.count,
                        lastUsedAt: delta.lastUsedAt,
                        firstSeenAt: delta.lastUsedAt,
                        source: delta.source
                    )
                    try word.insert(db)
                }
            }
            for delta in bigrams {
                if var existing = try UserBigram
                    .filter(Column("lang") == language.rawValue && Column("w1") == delta.w1 && Column("w2") == delta.w2)
                    .fetchOne(db)
                {
                    existing.count = delta.count
                    existing.lastUsedAt = delta.lastUsedAt
                    try existing.update(db)
                } else {
                    try UserBigram(language: language, w1: delta.w1, w2: delta.w2, count: delta.count, lastUsedAt: delta.lastUsedAt)
                        .insert(db)
                }
            }
            for delta in trigrams {
                if var existing = try UserTrigram
                    .filter(
                        Column("lang") == language.rawValue && Column("w1") == delta.w1 && Column("w2") == delta.w2 && Column("w3") == delta
                            .w3
                    )
                    .fetchOne(db)
                {
                    existing.count = delta.count
                    existing.lastUsedAt = delta.lastUsedAt
                    try existing.update(db)
                } else {
                    try UserTrigram(
                        language: language, w1: delta.w1, w2: delta.w2, w3: delta.w3, count: delta.count, lastUsedAt: delta.lastUsedAt
                    )
                    .insert(db)
                }
            }
        }
    }

    // MARK: - Capped loads (for `UserModel`'s initial/reload load)

    /// Most recent+frequent first (§6.7.6's "most recent and frequent" cap
    /// rule) — `ORDER BY count DESC, lastUsedAt DESC` is a reasonable proxy
    /// for "the words worth keeping in memory" without needing to already
    /// know `halfLifeDays` here (real `eff` decay is `UserModel`'s job).
    public func loadWords(language: LanguageID, limit: Int) async throws -> [UserWord] {
        try await database.read { db in
            try UserWord
                .filter(Column("lang") == language.rawValue)
                .order(Column("count").desc, Column("lastUsedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func loadBigrams(language: LanguageID, limit: Int) async throws -> [UserBigram] {
        try await database.read { db in
            try UserBigram
                .filter(Column("lang") == language.rawValue)
                .order(Column("count").desc, Column("lastUsedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func loadTrigrams(language: LanguageID, limit: Int) async throws -> [UserTrigram] {
        try await database.read { db in
            try UserTrigram
                .filter(Column("lang") == language.rawValue)
                .order(Column("count").desc, Column("lastUsedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func loadBlockedWords(language: LanguageID) async throws -> Set<String> {
        try await database.read { db in
            let surfaces = try String.fetchAll(
                db, sql: "SELECT surface FROM user_word WHERE lang = ? AND isBlocked = 1", arguments: [language.rawValue]
            )
            return Set(surfaces)
        }
    }

    public func loadBlockedCorrections(language: LanguageID) async throws -> Set<BlockedCorrectionPair> {
        try await database.read { db in
            let rows = try UserCorrectionBlock.filter(Column("lang") == language.rawValue).fetchAll(db)
            return Set(rows.map { BlockedCorrectionPair(typed: $0.typed, corrected: $0.corrected) })
        }
    }

    // MARK: - Block / unblock / forget (§6.7.8's long-press menu)

    public func setBlocked(_ blocked: Bool, surface: String, language: LanguageID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE user_word SET isBlocked = ? WHERE lang = ? AND surface = ?",
                arguments: [blocked, language.rawValue, surface]
            )
        }
        notifyChanged()
    }

    /// "Forget" — delete the word row and every n-gram row that mentions it
    /// (§6.7.8: "delete the word and its n-grams").
    public func forget(surface: String, language: LanguageID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM user_word WHERE lang = ? AND surface = ?", arguments: [language.rawValue, surface])
            try db.execute(
                sql: "DELETE FROM user_bigram WHERE lang = ? AND (w1 = ? OR w2 = ?)", arguments: [language.rawValue, surface, surface]
            )
            try db.execute(
                sql: "DELETE FROM user_trigram WHERE lang = ? AND (w1 = ? OR w2 = ? OR w3 = ?)",
                arguments: [language.rawValue, surface, surface, surface]
            )
        }
        notifyChanged()
    }

    /// Task 10.6's "add a word manually" — seeded at a baseline comfortably
    /// above any reasonable `newWordThreshold`, same reasoning as
    /// `UserModel.addContactNames`: a word you deliberately typed into the
    /// dictionary manager should be immediately suggestable, not have to
    /// "earn" visibility the way an organically-typed new word does.
    /// `.manual` source, so `prune`/`enforceWordCap` never evict it.
    public func addManualWord(surface: String, language: LanguageID) async throws {
        let now = Date()
        try await database.write { db in
            guard try UserWord.filter(Column("lang") == language.rawValue && Column("surface") == surface).fetchCount(db) == 0 else {
                return // already exists — leave real usage counts alone
            }
            var word = UserWord(
                language: language, surface: surface, matchKey: PersianNormalization.matchKey(surface), count: 10, lastUsedAt: now,
                firstSeenAt: now, source: .manual
            )
            try word.insert(db)
        }
        notifyChanged()
    }

    public func blockCorrection(typed: String, corrected: String, language: LanguageID) async throws {
        try await database.write { db in
            try UserCorrectionBlock(language: language, typed: typed, corrected: corrected, createdAt: Date()).insert(
                db,
                onConflict: .ignore
            )
        }
    }

    /// Task 9.8's "Clear my learned words for this language" — every row in
    /// every personal-model table, for `language` only (the other language's
    /// data is untouched).
    public func deleteAll(language: LanguageID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM user_word WHERE lang = ?", arguments: [language.rawValue])
            try db.execute(sql: "DELETE FROM user_bigram WHERE lang = ?", arguments: [language.rawValue])
            try db.execute(sql: "DELETE FROM user_trigram WHERE lang = ?", arguments: [language.rawValue])
            try db.execute(sql: "DELETE FROM user_correction_block WHERE lang = ?", arguments: [language.rawValue])
        }
        notifyChanged()
    }

    // MARK: - Prune (§6.7.6: "delete the lowest eff rows, never user-added words")

    /// Deletes the lowest-`eff` `user_word` rows (and their n-grams) once
    /// the row count for `language` exceeds `maxWords`, skipping `.manual`
    /// rows (the plan's own "never user-added words"). `eff` is computed
    /// here with the caller's `halfLifeDays`/`now`, matching `UserModel`'s
    /// own decay formula (§6.7.6), so pruning agrees with what the
    /// in-memory model would actually rank as least valuable.
    public func prune(language: LanguageID, keepingTop maxWords: Int, halfLifeDays: Int, now: Date) async throws {
        try await database.write { db in
            let totalCount = try UserWord.filter(Column("lang") == language.rawValue).fetchCount(db)
            guard totalCount > maxWords else { return }
            let overflow = totalCount - maxWords

            let candidates = try UserWord
                .filter(Column("lang") == language.rawValue && Column("source") != UserWordSource.manual.rawValue)
                .fetchAll(db)
            let halfLife = max(Double(halfLifeDays), 1)
            let ranked = candidates.sorted { lhs, rhs in
                Self.effectiveCount(lhs, halfLifeDays: halfLife, now: now) < Self.effectiveCount(rhs, halfLifeDays: halfLife, now: now)
            }
            for word in ranked.prefix(overflow) {
                try db.execute(sql: "DELETE FROM user_word WHERE lang = ? AND surface = ?", arguments: [language.rawValue, word.surface])
                try db.execute(
                    sql: "DELETE FROM user_bigram WHERE lang = ? AND (w1 = ? OR w2 = ?)",
                    arguments: [language.rawValue, word.surface, word.surface]
                )
                try db.execute(
                    sql: "DELETE FROM user_trigram WHERE lang = ? AND (w1 = ? OR w2 = ? OR w3 = ?)",
                    arguments: [language.rawValue, word.surface, word.surface, word.surface]
                )
            }
        }
    }

    private static func effectiveCount(_ word: UserWord, halfLifeDays: Double, now: Date) -> Double {
        let daysSinceUse = now.timeIntervalSince(word.lastUsedAt) / 86400
        return word.count * pow(0.5, daysSinceUse / halfLifeDays)
    }

    // MARK: - Backup import (§6.11.7, task 10.9)

    /// "Import merges... by `surface` for user words (sum counts)" — the
    /// same sum/max-lastUsed shape `merge(from:language:)` already uses for
    /// the no-Full-Access local→shared case, just from an in-memory array
    /// (a decoded `.kelidbackup` file) instead of another `DatabaseManager`.
    public func importWords(_ words: [UserWordDelta], language: LanguageID) async throws {
        guard !words.isEmpty else { return }
        try await database.write { db in
            for imported in words {
                if var existing = try UserWord
                    .filter(Column("lang") == language.rawValue && Column("surface") == imported.surface)
                    .fetchOne(db)
                {
                    existing.count += imported.count
                    existing.lastUsedAt = max(existing.lastUsedAt, imported.lastUsedAt)
                    try existing.update(db)
                } else {
                    var word = UserWord(
                        language: language, surface: imported.surface, matchKey: imported.matchKey, count: imported.count,
                        lastUsedAt: imported.lastUsedAt, firstSeenAt: imported.lastUsedAt, source: imported.source
                    )
                    try word.insert(db)
                }
            }
        }
        notifyChanged()
    }

    // MARK: - Local → shared merge (§6.11.2's no-Full-Access fallback)

    /// Merges `local`'s rows for `language` into `self` — "sum counts, max
    /// `lastUsed`, union blocklists" — then the caller (which owns the
    /// local database's file) is responsible for deleting it. Does **not**
    /// delete `local`'s own rows itself, since `local` is a whole separate
    /// `DatabaseManager`/file this type has no direct file-system authority
    /// over.
    public func merge(from local: UserModelRepository, language: LanguageID) async throws {
        let localWords = try await local.database.read { db in
            try UserWord.filter(Column("lang") == language.rawValue).fetchAll(db)
        }
        let localBigrams = try await local.database.read { db in
            try UserBigram.filter(Column("lang") == language.rawValue).fetchAll(db)
        }
        let localTrigrams = try await local.database.read { db in
            try UserTrigram.filter(Column("lang") == language.rawValue).fetchAll(db)
        }
        let localBlockedCorrections = try await local.loadBlockedCorrections(language: language)

        try await database.write { db in
            for localWord in localWords {
                if var existing = try UserWord
                    .filter(Column("lang") == language.rawValue && Column("surface") == localWord.surface)
                    .fetchOne(db)
                {
                    existing.count += localWord.count
                    existing.lastUsedAt = max(existing.lastUsedAt, localWord.lastUsedAt)
                    existing.isBlocked = existing.isBlocked || localWord.isBlocked
                    try existing.update(db)
                } else {
                    var copy = localWord
                    copy.id = nil
                    try copy.insert(db)
                }
            }
            for localBigram in localBigrams {
                if var existing = try UserBigram
                    .filter(Column("lang") == language.rawValue && Column("w1") == localBigram.w1 && Column("w2") == localBigram.w2)
                    .fetchOne(db)
                {
                    existing.count += localBigram.count
                    existing.lastUsedAt = max(existing.lastUsedAt, localBigram.lastUsedAt)
                    try existing.update(db)
                } else {
                    try localBigram.insert(db)
                }
            }
            for localTrigram in localTrigrams {
                if var existing = try UserTrigram
                    .filter(
                        Column("lang") == language.rawValue && Column("w1") == localTrigram.w1 && Column("w2") == localTrigram.w2 &&
                            Column("w3") == localTrigram.w3
                    )
                    .fetchOne(db)
                {
                    existing.count += localTrigram.count
                    existing.lastUsedAt = max(existing.lastUsedAt, localTrigram.lastUsedAt)
                    try existing.update(db)
                } else {
                    try localTrigram.insert(db)
                }
            }
            for pair in localBlockedCorrections {
                try UserCorrectionBlock(language: language, typed: pair.typed, corrected: pair.corrected, createdAt: Date())
                    .insert(db, onConflict: .ignore)
            }
        }
        notifyChanged()
    }
}
