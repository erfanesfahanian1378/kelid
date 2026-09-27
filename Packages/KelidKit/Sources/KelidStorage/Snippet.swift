import Foundation
import GRDB

/// §6.11.3's `snippet` table row (task 10.5). `shortcut` is the text-
/// expansion trigger (e.g. "@@addr") — `nil`/unset means the snippet is only
/// ever inserted manually from the clipboard panel's Snippets tab, never by
/// typing a shortcut.
public struct Snippet: Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var uuid: UUID
    public var folderID: Int64?
    public var title: String?
    public var text: String
    public var searchKey: String
    public var shortcut: String?
    public var sortOrder: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var useCount: Int

    public init(
        id: Int64? = nil,
        uuid: UUID = UUID(),
        folderID: Int64? = nil,
        title: String? = nil,
        text: String,
        searchKey: String,
        shortcut: String? = nil,
        sortOrder: Double,
        createdAt: Date,
        updatedAt: Date,
        useCount: Int = 0
    ) {
        self.id = id
        self.uuid = uuid
        self.folderID = folderID
        self.title = title
        self.text = text
        self.searchKey = searchKey
        self.shortcut = shortcut
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
    }
}

extension Snippet: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "snippet"

    public init(row: Row) throws {
        id = row["id"]
        uuid = UUID(uuidString: row["uuid"]) ?? UUID()
        folderID = row["folderId"]
        title = row["title"]
        text = row["text"]
        searchKey = row["searchKey"]
        shortcut = row["shortcut"]
        sortOrder = row["sortOrder"]
        createdAt = Date(timeIntervalSince1970: row["createdAt"])
        updatedAt = Date(timeIntervalSince1970: row["updatedAt"])
        useCount = row["useCount"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["uuid"] = uuid.uuidString
        container["folderId"] = folderID
        container["title"] = title
        container["text"] = text
        container["searchKey"] = searchKey
        container["shortcut"] = shortcut
        container["sortOrder"] = sortOrder
        container["createdAt"] = createdAt.timeIntervalSince1970
        container["updatedAt"] = updatedAt.timeIntervalSince1970
        container["useCount"] = useCount
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
