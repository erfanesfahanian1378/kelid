import Foundation
import GRDB

public enum ClipKind: String, Codable, Sendable, Equatable {
    case text
    case url
    case image
}

/// §6.5.1: how a clip got into the store.
public enum ClipSource: String, Codable, Sendable, Equatable {
    case capture
    case keyboard
    case app
    case share
    case intent
}

/// §6.11.3's `clip` table row (task 5.1). Timestamps are stored as unix
/// seconds (`REAL`), not GRDB's default ISO8601-string `Date` encoding —
/// this type implements `FetchableRecord`/`MutablePersistableRecord`
/// directly (not via `Codable`) so that mapping is explicit rather than
/// relying on a default that doesn't match the schema.
public struct Clip: Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var uuid: UUID
    public var kind: ClipKind
    public var text: String?
    public var searchKey: String
    public var imageFile: String?
    public var thumbFile: String?
    public var contentHash: String
    public var charCount: Int
    public var isTruncated: Bool
    public var createdAt: Date
    public var lastCopiedAt: Date
    public var lastUsedAt: Date?
    public var copyCount: Int
    public var useCount: Int
    public var isPinned: Bool
    public var pinnedOrder: Double?
    public var isSensitive: Bool
    public var expiresAt: Date?
    public var source: ClipSource

    public init(
        id: Int64? = nil,
        uuid: UUID = UUID(),
        kind: ClipKind,
        text: String? = nil,
        searchKey: String = "",
        imageFile: String? = nil,
        thumbFile: String? = nil,
        contentHash: String,
        charCount: Int = 0,
        isTruncated: Bool = false,
        createdAt: Date,
        lastCopiedAt: Date,
        lastUsedAt: Date? = nil,
        copyCount: Int = 1,
        useCount: Int = 0,
        isPinned: Bool = false,
        pinnedOrder: Double? = nil,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        source: ClipSource
    ) {
        self.id = id
        self.uuid = uuid
        self.kind = kind
        self.text = text
        self.searchKey = searchKey
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.contentHash = contentHash
        self.charCount = charCount
        self.isTruncated = isTruncated
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.lastUsedAt = lastUsedAt
        self.copyCount = copyCount
        self.useCount = useCount
        self.isPinned = isPinned
        self.pinnedOrder = pinnedOrder
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.source = source
    }
}

/// What `ClipRepository.upsert(_:)` inserts before a row (and therefore an
/// `id`) exists — everything a fresh capture/keyboard-copy/app-add knows.
public struct ClipDraft: Sendable, Equatable {
    public var kind: ClipKind
    public var text: String?
    public var searchKey: String
    public var imageFile: String?
    public var thumbFile: String?
    public var contentHash: String
    public var charCount: Int
    public var isTruncated: Bool
    public var isSensitive: Bool
    public var expiresAt: Date?
    public var source: ClipSource

    public init(
        kind: ClipKind,
        text: String? = nil,
        searchKey: String = "",
        imageFile: String? = nil,
        thumbFile: String? = nil,
        contentHash: String,
        charCount: Int = 0,
        isTruncated: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        source: ClipSource
    ) {
        self.kind = kind
        self.text = text
        self.searchKey = searchKey
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.contentHash = contentHash
        self.charCount = charCount
        self.isTruncated = isTruncated
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.source = source
    }
}

extension Clip: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clip"

    public init(row: Row) throws {
        id = row["id"]
        uuid = UUID(uuidString: row["uuid"] as String) ?? UUID()
        kind = ClipKind(rawValue: row["kind"] as String) ?? .text
        text = row["text"]
        searchKey = row["searchKey"]
        imageFile = row["imageFile"]
        thumbFile = row["thumbFile"]
        contentHash = row["contentHash"]
        charCount = row["charCount"]
        isTruncated = row["isTruncated"]
        createdAt = Date(timeIntervalSince1970: row["createdAt"])
        lastCopiedAt = Date(timeIntervalSince1970: row["lastCopiedAt"])
        lastUsedAt = (row["lastUsedAt"] as Double?).map(Date.init(timeIntervalSince1970:))
        copyCount = row["copyCount"]
        useCount = row["useCount"]
        isPinned = row["isPinned"]
        pinnedOrder = row["pinnedOrder"]
        isSensitive = row["isSensitive"]
        expiresAt = (row["expiresAt"] as Double?).map(Date.init(timeIntervalSince1970:))
        source = ClipSource(rawValue: row["source"] as String) ?? .capture
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["uuid"] = uuid.uuidString
        container["kind"] = kind.rawValue
        container["text"] = text
        container["searchKey"] = searchKey
        container["imageFile"] = imageFile
        container["thumbFile"] = thumbFile
        container["contentHash"] = contentHash
        container["charCount"] = charCount
        container["isTruncated"] = isTruncated
        container["createdAt"] = createdAt.timeIntervalSince1970
        container["lastCopiedAt"] = lastCopiedAt.timeIntervalSince1970
        container["lastUsedAt"] = lastUsedAt?.timeIntervalSince1970
        container["copyCount"] = copyCount
        container["useCount"] = useCount
        container["isPinned"] = isPinned
        container["pinnedOrder"] = pinnedOrder
        container["isSensitive"] = isSensitive
        container["expiresAt"] = expiresAt?.timeIntervalSince1970
        container["source"] = source.rawValue
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
