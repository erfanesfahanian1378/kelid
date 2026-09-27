import Foundation
import GRDB
import KelidCore
import PersianText

public enum SnippetRepositoryError: Error, Sendable, Equatable {
    /// Task 10.5's "shortcut field with uniqueness validation" — the
    /// `snippet.shortcut` column already has a `UNIQUE` constraint (§6.11.3),
    /// this just surfaces it as a typed error instead of a raw SQLite one.
    case shortcutAlreadyInUse
    /// A row fetched from the database had no `id` — should be unreachable
    /// (every persisted row has one), surfaced as a typed error instead of
    /// a force unwrap per this project's "no force unwraps outside tests" rule.
    case missingRowID
}

/// One backup-imported snippet's fields (task 10.9), bundled into a struct
/// so `importSnippet` stays under SwiftLint's 5-parameter limit.
public struct SnippetImportRecord: Sendable {
    public let uuid: UUID
    public let folderID: Int64?
    public let title: String?
    public let text: String
    public let shortcut: String?
    public let sortOrder: Double
    public let createdAt: Date
    public let updatedAt: Date
    public let useCount: Int

    public init(
        uuid: UUID, folderID: Int64?, title: String?, text: String, shortcut: String?, sortOrder: Double,
        createdAt: Date, updatedAt: Date, useCount: Int
    ) {
        self.uuid = uuid
        self.folderID = folderID
        self.title = title
        self.text = text
        self.shortcut = shortcut
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
    }
}

/// A folder plus its snippets, for the app's Snippets sub-tab and the
/// keyboard's Snippets panel tab — both want "show me everything, grouped,"
/// not paged access.
public struct SnippetFolderContents: Sendable, Equatable {
    public let folder: SnippetFolder?
    public let snippets: [Snippet]
}

/// Task 10.5: folder/snippet CRUD, reorder, and the shortcut lookup the
/// keyboard's text-expansion feature needs — over the `v1_snippets` tables
/// migration `DatabaseManager` already creates.
public actor SnippetRepository {
    private let database: DatabaseManager
    private let darwinNotifier: DarwinNotifier
    private let appGroupIdentifier: String?
    private let clock: Clock

    public init(
        database: DatabaseManager,
        darwinNotifier: DarwinNotifier = .shared,
        appGroupIdentifier: String? = AppGroup.identifier,
        clock: Clock = SystemClock()
    ) {
        self.database = database
        self.darwinNotifier = darwinNotifier
        self.appGroupIdentifier = appGroupIdentifier
        self.clock = clock
    }

    // MARK: - Folders

    public func listFolders() async throws -> [SnippetFolder] {
        try await database.read { db in
            try SnippetFolder.order(Column("sortOrder").asc).fetchAll(db)
        }
    }

    @discardableResult
    public func createFolder(name: String, icon: String? = nil) async throws -> SnippetFolder {
        let result = try await database.write { db -> SnippetFolder in
            let maxOrder = try Double.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM snippet_folder") ?? 0
            var folder = SnippetFolder(name: name, icon: icon, sortOrder: maxOrder + 1)
            try folder.insert(db)
            return folder
        }
        notifyChanged()
        return result
    }

    public func renameFolder(id: Int64, name: String) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE snippet_folder SET name = ? WHERE id = ?", arguments: [name, id])
        }
        notifyChanged()
    }

    /// Deleting a folder sets its snippets' `folderId` to `NULL` (§6.11.3's
    /// `ON DELETE SET NULL`) rather than deleting them — they become
    /// unfiled, not gone.
    public func deleteFolder(id: Int64) async throws {
        try await database.write { db in
            _ = try SnippetFolder.deleteOne(db, key: id)
        }
        notifyChanged()
    }

    public func reorderFolders(ids: [Int64]) async throws {
        try await database.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE snippet_folder SET sortOrder = ? WHERE id = ?", arguments: [Double(index), id])
            }
        }
        notifyChanged()
    }

    // MARK: - Snippets

    public func listSnippets(folderID: Int64?) async throws -> [Snippet] {
        try await database.read { db in
            try Snippet
                .filter(Column("folderId") == folderID)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    public func listAllGroupedByFolder() async throws -> [SnippetFolderContents] {
        try await database.read { db in
            let folders = try SnippetFolder.order(Column("sortOrder").asc).fetchAll(db)
            let allSnippets = try Snippet.order(Column("sortOrder").asc).fetchAll(db)
            var groups = folders.map { folder in
                SnippetFolderContents(folder: folder, snippets: allSnippets.filter { $0.folderID == folder.id })
            }
            let unfiled = allSnippets.filter { $0.folderID == nil }
            if !unfiled.isEmpty {
                groups.append(SnippetFolderContents(folder: nil, snippets: unfiled))
            }
            return groups
        }
    }

    public func search(query: String) async throws -> [Snippet] {
        let likePattern = "%\(PersianNormalization.searchKey(query))%"
        return try await database.read { db in
            try Snippet
                .filter(Column("searchKey").like(likePattern))
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    /// Task 9.6/10.5: the keyboard's text-expansion lookup — an exact,
    /// case-sensitive match on the raw shortcut (a shortcut is a
    /// deliberately-typed trigger like "@@addr", not prose text that should
    /// be normalized/fuzzy-matched the way `searchKey` is for search).
    public func snippet(forShortcut shortcut: String) async throws -> Snippet? {
        try await database.read { db in
            try Snippet.filter(Column("shortcut") == shortcut).fetchOne(db)
        }
    }

    @discardableResult
    public func createSnippet(
        folderID: Int64?, title: String?, text: String, shortcut: String?
    ) async throws -> Snippet {
        let now = clock.now()
        do {
            let result = try await database.write { db -> Snippet in
                let maxOrder = try Double.fetchOne(
                    db, sql: "SELECT MAX(sortOrder) FROM snippet WHERE folderId IS ?", arguments: [folderID]
                ) ?? 0
                var snippet = Snippet(
                    folderID: folderID,
                    title: title,
                    text: text,
                    searchKey: PersianNormalization.searchKey(title ?? text),
                    shortcut: Self.normalizedShortcut(shortcut),
                    sortOrder: maxOrder + 1,
                    createdAt: now,
                    updatedAt: now
                )
                try snippet.insert(db)
                return snippet
            }
            notifyChanged()
            return result
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw SnippetRepositoryError.shortcutAlreadyInUse
        }
    }

    public func updateSnippet(id: Int64, title: String?, text: String, shortcut: String?) async throws {
        let now = clock.now()
        do {
            try await database.write { db in
                try db.execute(
                    sql: "UPDATE snippet SET title = ?, text = ?, searchKey = ?, shortcut = ?, updatedAt = ? WHERE id = ?",
                    arguments: [title, text, PersianNormalization.searchKey(title ?? text), Self.normalizedShortcut(shortcut), now
                        .timeIntervalSince1970, id]
                )
            }
            notifyChanged()
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw SnippetRepositoryError.shortcutAlreadyInUse
        }
    }

    public func moveSnippet(id: Int64, toFolder folderID: Int64?) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE snippet SET folderId = ? WHERE id = ?", arguments: [folderID, id])
        }
        notifyChanged()
    }

    public func deleteSnippets(ids: [Int64]) async throws {
        try await database.write { db in
            _ = try Snippet.deleteAll(db, keys: ids)
        }
        notifyChanged()
    }

    public func reorderSnippets(ids: [Int64], folderID: Int64?) async throws {
        try await database.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE snippet SET sortOrder = ?, folderId = ? WHERE id = ?", arguments: [Double(index), folderID, id]
                )
            }
        }
        notifyChanged()
    }

    /// Task 10.5's text expansion: bumps `useCount` every time a shortcut
    /// actually expands.
    public func markUsed(id: Int64) async throws {
        try await database.write { db in
            try db.execute(sql: "UPDATE snippet SET useCount = useCount + 1 WHERE id = ?", arguments: [id])
        }
    }

    /// Empty string means "no shortcut," stored as `NULL` — an empty string
    /// would otherwise trivially violate the `UNIQUE` constraint after the
    /// second snippet with a blank shortcut field.
    private static func normalizedShortcut(_ shortcut: String?) -> String? {
        guard let shortcut, !shortcut.isEmpty else { return nil }
        return shortcut
    }

    private func notifyChanged() {
        darwinNotifier.post(.snippetsChanged, appGroupIdentifier: appGroupIdentifier)
    }

    /// §6.12's "Delete all Kelid data" (task 10.10/App → Settings →
    /// Advanced).
    public func deleteAllSnippetsAndFolders() async throws {
        try await database.write { db in
            _ = try Snippet.deleteAll(db)
            _ = try SnippetFolder.deleteAll(db)
        }
        notifyChanged()
    }

    // MARK: - Backup import (§6.11.7, task 10.9)

    /// "Import merges... by `uuid` for snippets [and folders]" — upserts a
    /// folder by its backup `uuid`, returning its local row id so the
    /// caller (`BackupService`) can resolve an imported snippet's folder
    /// reference (backup JSON carries folder *uuids*, not local ids, since
    /// those are only ever stable within one database).
    @discardableResult
    public func importFolder(uuid: UUID, name: String, icon: String?, sortOrder: Double) async throws -> Int64 {
        let id = try await database.write { db -> Int64 in
            if var existing = try SnippetFolder.filter(Column("uuid") == uuid.uuidString).fetchOne(db) {
                existing.name = name
                existing.icon = icon
                try existing.update(db)
                guard let existingID = existing.id else { throw SnippetRepositoryError.missingRowID }
                return existingID
            }
            var folder = SnippetFolder(uuid: uuid, name: name, icon: icon, sortOrder: sortOrder)
            try folder.insert(db)
            return db.lastInsertedRowID
        }
        notifyChanged()
        return id
    }

    /// Same upsert-by-uuid shape as `importFolder`. A shortcut collision
    /// with a *different* existing snippet drops the imported shortcut
    /// (`nil`) rather than failing the whole restore over one field —
    /// restoring a backup shouldn't be all-or-nothing over a single
    /// duplicate shortcut.
    public func importSnippet(_ record: SnippetImportRecord) async throws {
        try await database.write { db in
            let searchKey = PersianNormalization.searchKey(record.title ?? record.text)
            var resolvedShortcut = Self.normalizedShortcut(record.shortcut)
            if let candidate = resolvedShortcut,
               let owner = try Snippet.filter(Column("shortcut") == candidate).fetchOne(db), owner.uuid != record.uuid
            {
                resolvedShortcut = nil
            }
            if var existing = try Snippet.filter(Column("uuid") == record.uuid.uuidString).fetchOne(db) {
                existing.folderID = record.folderID
                existing.title = record.title
                existing.text = record.text
                existing.searchKey = searchKey
                existing.shortcut = resolvedShortcut
                existing.updatedAt = record.updatedAt
                existing.useCount = max(existing.useCount, record.useCount)
                try existing.update(db)
            } else {
                var snippet = Snippet(
                    uuid: record.uuid, folderID: record.folderID, title: record.title, text: record.text, searchKey: searchKey,
                    shortcut: resolvedShortcut, sortOrder: record.sortOrder, createdAt: record.createdAt,
                    updatedAt: record.updatedAt, useCount: record.useCount
                )
                try snippet.insert(db)
            }
        }
        notifyChanged()
    }
}
