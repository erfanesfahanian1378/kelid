import Foundation
import GRDB
import KelidCore

/// §6.7.6/§6.7.8's `source` tag — where a personal word/increment came from,
/// stored so `UserModelRepository.prune(...)` can exclude `.manual` rows
/// ("never [delete] user-added words") and so a future app dictionary
/// manager (Phase 10) can show provenance.
public enum UserWordSource: String, Codable, Sendable, Equatable {
    case typed
    case accepted
    case manual
    case importSource = "import"
    case contacts
    case replacement
}

/// §6.11.3's `user_word` table row (task 9.1) — one personal word, per
/// language. `count`/`lastUsedAt` are the raw stored values `UserModel`
/// (§6.7.6) computes `eff(count, lastUsed)` from; this type itself has no
/// decay logic, same "storage is dumb, the engine module is smart" split
/// `Clip`/`ClipRepository` already established.
public struct UserWord: Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var language: LanguageID
    public var surface: String
    public var matchKey: String
    public var count: Double
    public var lastUsedAt: Date
    public var firstSeenAt: Date
    public var source: UserWordSource
    public var isBlocked: Bool

    public init(
        id: Int64? = nil,
        language: LanguageID,
        surface: String,
        matchKey: String,
        count: Double,
        lastUsedAt: Date,
        firstSeenAt: Date,
        source: UserWordSource,
        isBlocked: Bool = false
    ) {
        self.id = id
        self.language = language
        self.surface = surface
        self.matchKey = matchKey
        self.count = count
        self.lastUsedAt = lastUsedAt
        self.firstSeenAt = firstSeenAt
        self.source = source
        self.isBlocked = isBlocked
    }
}

extension UserWord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "user_word"

    public init(row: Row) throws {
        id = row["id"]
        language = LanguageID(rawValue: row["lang"] as String) ?? .fa
        surface = row["surface"]
        matchKey = row["matchKey"]
        count = row["count"]
        lastUsedAt = Date(timeIntervalSince1970: row["lastUsedAt"])
        firstSeenAt = Date(timeIntervalSince1970: row["firstSeenAt"])
        source = UserWordSource(rawValue: row["source"] as String) ?? .typed
        isBlocked = row["isBlocked"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["lang"] = language.rawValue
        container["surface"] = surface
        container["matchKey"] = matchKey
        container["count"] = count
        container["lastUsedAt"] = lastUsedAt.timeIntervalSince1970
        container["firstSeenAt"] = firstSeenAt.timeIntervalSince1970
        container["source"] = source.rawValue
        container["isBlocked"] = isBlocked
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
