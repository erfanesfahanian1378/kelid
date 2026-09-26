import Foundation
import GRDB
import KelidCore
import SQLite3

public enum DatabaseManagerError: Error, Sendable, Equatable {
    /// `open()` hasn't succeeded yet.
    case notOpen
    /// The on-disk schema is newer than this build's migrator knows about
    /// (§6.11.4) — the database was opened read-only, so writes are refused
    /// instead of risking corruption.
    case readOnly
    case failedToOpen
}

/// Implements PLAN.md §6.11.2 exactly: a coordinated-open `DatabasePool` in
/// WAL mode, with persistent WAL and GRDB's suspension-notification
/// handling, so the shared App Group SQLite file survives being accessed
/// by multiple processes (app, keyboard, later Share Extension) without
/// `0xDEAD10CC` (§2.1 C14).
///
/// An `actor` rather than a `@MainActor` class: every method is naturally
/// `async` (task 1.5), calls are serialized so `open()` can't race with
/// itself, and GRDB's `DatabasePool` is itself `Sendable`.
public actor DatabaseManager {
    /// Coarse state for diagnostics (task 1.8's debug line). Not used for
    /// any decision-making inside this type itself — `pool`/`isReadOnly`
    /// are the source of truth there.
    public enum State: Sendable, Equatable {
        case unavailable
        case open
        case suspended
    }

    private let log = Log.logger(.storage)
    public let fileURL: URL
    private var pool: DatabasePool?
    public private(set) var isReadOnly = false
    public private(set) var state: State = .unavailable

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Opens the database if it isn't already open. Safe to call more than
    /// once (a no-op after the first successful call).
    public func open() throws {
        guard pool == nil else { return }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        configuration.observesSuspensionNotifications = true
        configuration.prepareDatabase { db in
            var flag: CInt = 1
            let code = withUnsafeMutablePointer(to: &flag) { pointer in
                sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, pointer)
            }
            if code != SQLITE_OK {
                Log.logger(.storage).error("could not set SQLITE_FCNTL_PERSIST_WAL (code \(code))")
            }
        }

        let openedPool = try Self.coordinatedOpen(at: fileURL, configuration: configuration)

        let migrator = Self.migrator()
        if try openedPool.read({ try migrator.hasBeenSuperseded($0) }) {
            log.warning("database schema has been superseded by a newer app version — opening read-only")
            isReadOnly = true
        } else {
            try migrator.migrate(openedPool)
            isReadOnly = false
        }
        pool = openedPool
        state = .open
    }

    /// Posts GRDB's `Database.resumeNotification` (§6.11.2). Call from
    /// `viewWillAppear` / `NSExtensionHostWillEnterForeground`.
    public func resume() {
        guard let pool else { return }
        NotificationCenter.default.post(name: Database.resumeNotification, object: pool)
        state = .open
    }

    /// Posts GRDB's `Database.suspendNotification` (§6.11.2). Call from
    /// `viewDidDisappear` / `NSExtensionHostDidEnterBackground`, so a
    /// suspended process never holds a database lock (§2.1 C14).
    public func suspend() {
        guard let pool else { return }
        NotificationCenter.default.post(name: Database.suspendNotification, object: pool)
        state = .suspended
    }

    public func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await requirePool().read(block)
    }

    public func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        guard !isReadOnly else { throw DatabaseManagerError.readOnly }
        return try await requirePool().write(block)
    }

    private func requirePool() throws -> DatabasePool {
        guard let pool else { throw DatabaseManagerError.notOpen }
        return pool
    }

    /// `NSFileCoordinator.coordinate(writingItemAt:options: .forMerging)`,
    /// per GRDB's "Sharing a Database" guide — required so the app and the
    /// keyboard don't open the WAL files in an inconsistent state relative
    /// to each other.
    private static func coordinatedOpen(at url: URL, configuration: Configuration) throws -> DatabasePool {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var openResult: Result<DatabasePool, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { coordinatedURL in
            openResult = Result { try DatabasePool(path: coordinatedURL.path, configuration: configuration) }
        }
        if let coordinatorError {
            throw coordinatorError
        }
        switch openResult {
        case let .success(pool):
            return pool
        case let .failure(error):
            throw error
        case nil:
            throw DatabaseManagerError.failedToOpen
        }
    }

    private static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v0_meta") { db in
            try db.create(table: "meta") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }
        registerV1Clips(&migrator)
        registerV1Snippets(&migrator)
        return migrator
    }

    /// §6.11.3's `clip` table (Phase 5).
    private static func registerV1Clips(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_clips") { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("kind", .text).notNull().check { ["text", "url", "image"].contains($0) }
                t.column("text", .text)
                t.column("searchKey", .text).notNull().defaults(to: "")
                t.column("imageFile", .text)
                t.column("thumbFile", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("charCount", .integer).notNull().defaults(to: 0)
                t.column("isTruncated", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .double).notNull()
                t.column("lastCopiedAt", .double).notNull()
                t.column("lastUsedAt", .double)
                t.column("copyCount", .integer).notNull().defaults(to: 1)
                t.column("useCount", .integer).notNull().defaults(to: 0)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("pinnedOrder", .double)
                t.column("isSensitive", .boolean).notNull().defaults(to: false)
                t.column("expiresAt", .double)
                t.column("source", .text).notNull()
            }
            try db.create(index: "clip_recent", on: "clip", columns: ["isPinned", "lastCopiedAt"])
            try db.create(
                index: "clip_expiry", on: "clip", columns: ["expiresAt"],
                condition: Column("expiresAt") != nil
            )
        }
    }

    /// §6.11.3's `snippet_folder`/`snippet` tables — real Phase 10
    /// functionality, but the plan explicitly allows creating the schema
    /// now "if convenient" (it is: no data depends on this yet, and it
    /// avoids a later migration for an unrelated phase).
    private static func registerV1Snippets(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_snippets") { db in
            try db.create(table: "snippet_folder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("sortOrder", .double).notNull()
            }
            try db.create(table: "snippet") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("folderId", .integer).references("snippet_folder", onDelete: .setNull)
                t.column("title", .text)
                t.column("text", .text).notNull()
                t.column("searchKey", .text).notNull()
                t.column("shortcut", .text).unique()
                t.column("sortOrder", .double).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
                t.column("useCount", .integer).notNull().defaults(to: 0)
            }
        }
    }
}
