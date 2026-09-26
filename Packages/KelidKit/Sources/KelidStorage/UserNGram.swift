import Foundation
import GRDB
import KelidCore

/// §6.11.3's `user_bigram` table row (task 9.1) — `WITHOUT ROWID`, keyed by
/// `(lang, w1, w2)`, so this conforms to plain `PersistableRecord` (there's
/// no auto-increment id to capture back, unlike `UserWord`).
public struct UserBigram: Sendable, Equatable {
    public var language: LanguageID
    public var w1: String
    public var w2: String
    public var count: Double
    public var lastUsedAt: Date

    public init(language: LanguageID, w1: String, w2: String, count: Double, lastUsedAt: Date) {
        self.language = language
        self.w1 = w1
        self.w2 = w2
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

extension UserBigram: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "user_bigram"

    public init(row: Row) throws {
        language = LanguageID(rawValue: row["lang"] as String) ?? .fa
        w1 = row["w1"]
        w2 = row["w2"]
        count = row["count"]
        lastUsedAt = Date(timeIntervalSince1970: row["lastUsedAt"])
    }

    public func encode(to container: inout PersistenceContainer) {
        container["lang"] = language.rawValue
        container["w1"] = w1
        container["w2"] = w2
        container["count"] = count
        container["lastUsedAt"] = lastUsedAt.timeIntervalSince1970
    }
}

/// §6.11.3's `user_trigram` table row — same reasoning as `UserBigram`,
/// keyed by `(lang, w1, w2, w3)`.
public struct UserTrigram: Sendable, Equatable {
    public var language: LanguageID
    public var w1: String
    public var w2: String
    public var w3: String
    public var count: Double
    public var lastUsedAt: Date

    public init(language: LanguageID, w1: String, w2: String, w3: String, count: Double, lastUsedAt: Date) {
        self.language = language
        self.w1 = w1
        self.w2 = w2
        self.w3 = w3
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

extension UserTrigram: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "user_trigram"

    public init(row: Row) throws {
        language = LanguageID(rawValue: row["lang"] as String) ?? .fa
        w1 = row["w1"]
        w2 = row["w2"]
        w3 = row["w3"]
        count = row["count"]
        lastUsedAt = Date(timeIntervalSince1970: row["lastUsedAt"])
    }

    public func encode(to container: inout PersistenceContainer) {
        container["lang"] = language.rawValue
        container["w1"] = w1
        container["w2"] = w2
        container["w3"] = w3
        container["count"] = count
        container["lastUsedAt"] = lastUsedAt.timeIntervalSince1970
    }
}

/// §6.11.3's `user_correction_block` table row (§6.7.8: "Reverting an
/// autocorrect adds the pair `(typed → corrected)` to `blockedCorrections`").
public struct UserCorrectionBlock: Sendable, Equatable {
    public var language: LanguageID
    public var typed: String
    public var corrected: String
    public var createdAt: Date

    public init(language: LanguageID, typed: String, corrected: String, createdAt: Date) {
        self.language = language
        self.typed = typed
        self.corrected = corrected
        self.createdAt = createdAt
    }
}

extension UserCorrectionBlock: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "user_correction_block"

    public init(row: Row) throws {
        language = LanguageID(rawValue: row["lang"] as String) ?? .fa
        typed = row["typed"]
        corrected = row["corrected"]
        createdAt = Date(timeIntervalSince1970: row["createdAt"])
    }

    public func encode(to container: inout PersistenceContainer) {
        container["lang"] = language.rawValue
        container["typed"] = typed
        container["corrected"] = corrected
        container["createdAt"] = createdAt.timeIntervalSince1970
    }
}
