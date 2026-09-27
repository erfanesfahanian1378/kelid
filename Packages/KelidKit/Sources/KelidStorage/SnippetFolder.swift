import Foundation
import GRDB

/// §6.11.3's `snippet_folder` table row (task 10.5).
public struct SnippetFolder: Identifiable, Sendable, Equatable {
    public var id: Int64?
    public var uuid: UUID
    public var name: String
    public var icon: String?
    public var sortOrder: Double

    public init(id: Int64? = nil, uuid: UUID = UUID(), name: String, icon: String? = nil, sortOrder: Double) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
    }
}

extension SnippetFolder: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "snippet_folder"

    public init(row: Row) throws {
        id = row["id"]
        uuid = UUID(uuidString: row["uuid"]) ?? UUID()
        name = row["name"]
        icon = row["icon"]
        sortOrder = row["sortOrder"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["uuid"] = uuid.uuidString
        container["name"] = name
        container["icon"] = icon
        container["sortOrder"] = sortOrder
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
