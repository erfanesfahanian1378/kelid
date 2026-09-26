import Foundation
import GRDB
@testable import KelidStorage
import Testing

// Serialized: GRDB's suspend/resume notifications are not scoped to the
// posting pool in practice — concurrently-running tests that suspend/resume
// different `DatabasePool`s were observed to interfere with each other.
@Suite("DatabaseManager", .serialized)
struct DatabaseManagerTests {
    /// `internal` (not `private`): `UserModelRepositoryTests.swift` (an
    /// extension of this same type, in a separate file — see its own doc
    /// comment for why) calls this too. Swift's `private` is file-scoped
    /// even across extensions of the same type.
    func tempDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kelid-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("test.sqlite")
    }

    @Test("open() creates the file and runs the v0_meta migration")
    func openCreatesFileAndMigrates() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()

        #expect(FileManager.default.fileExists(atPath: url.path))
        let tableExists = try await manager.read { db in
            try db.tableExists("meta")
        }
        #expect(tableExists)
    }

    @Test("open() is idempotent")
    func openIsIdempotent() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()
        try await manager.open()
    }

    @Test("read/write round-trip once open")
    func readWriteRoundTrip() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()

        try await manager.write { db in
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?)", arguments: ["greeting", "hello"])
        }
        let value = try await manager.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: ["greeting"])
        }
        #expect(value == "hello")
    }

    @Test("a write before open() throws .notOpen")
    func writeBeforeOpenThrows() async {
        let manager = DatabaseManager(fileURL: tempDatabaseURL())
        await #expect(throws: DatabaseManagerError.notOpen) {
            try await manager.write { _ in }
        }
    }

    @Test("a write while suspended throws, and succeeds again after resume")
    func writeWhileSuspendedThrowsThenSucceedsAfterResume() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()

        await manager.suspend()
        var threwWhileSuspended = false
        do {
            try await manager.write { db in
                try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?)", arguments: ["a", "b"])
            }
        } catch {
            threwWhileSuspended = true
        }
        #expect(threwWhileSuspended)

        await manager.resume()
        try await manager.write { db in
            try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?)", arguments: ["a", "b"])
        }
        let value = try await manager.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: ["a"])
        }
        #expect(value == "b")
    }

    @Test("open() also runs the v1_clips and v1_snippets migrations (task 5.1, §6.11.3)")
    func openCreatesClipAndSnippetTables() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()

        let tables = try await manager.read { db -> [Bool] in
            try [
                db.tableExists("clip"),
                db.tableExists("snippet_folder"),
                db.tableExists("snippet"),
            ]
        }
        #expect(tables == [true, true, true])

        // A round-trip insert exercises the column set/constraints for real,
        // not just "the table exists".
        try await manager.write { db in
            try db.execute(
                sql: """
                INSERT INTO clip (uuid, kind, text, searchKey, contentHash, createdAt, lastCopiedAt, source)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: ["u1", "text", "hello", "hello", "hash1", 1000, 1000, "capture"]
            )
        }
        let storedText = try await manager.read { db in
            try String.fetchOne(db, sql: "SELECT text FROM clip WHERE uuid = ?", arguments: ["u1"])
        }
        #expect(storedText == "hello")
    }

    @Test("open() also runs the v1_user_model migration (task 9.1, §6.11.3)")
    func openCreatesUserModelTables() async throws {
        let url = tempDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()

        let tables = try await manager.read { db -> [Bool] in
            try [
                db.tableExists("user_word"),
                db.tableExists("user_bigram"),
                db.tableExists("user_trigram"),
                db.tableExists("user_correction_block"),
            ]
        }
        #expect(tables == [true, true, true, true])

        // Round-trip inserts that exercise the real constraints, not just
        // "the table exists": UNIQUE(lang, surface) on user_word, and the
        // WITHOUT ROWID composite primary keys on the n-gram tables.
        try await manager.write { db in
            try db.execute(
                sql: "INSERT INTO user_word (lang, surface, matchKey, count, lastUsedAt, firstSeenAt) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: ["fa", "سلام", "سلام", 1.0, 1000, 1000]
            )
            try db.execute(
                sql: "INSERT INTO user_bigram (lang, w1, w2, count, lastUsedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["fa", "سلام", "دوست", 1.0, 1000]
            )
            try db.execute(
                sql: "INSERT INTO user_trigram (lang, w1, w2, w3, count, lastUsedAt) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: ["fa", "سلام", "دوست", "من", 1.0, 1000]
            )
            try db.execute(
                sql: "INSERT INTO user_correction_block (lang, typed, corrected, createdAt) VALUES (?, ?, ?, ?)",
                arguments: ["en", "teh", "the", 1000]
            )
        }
        let wordCount = try await manager.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM user_word") }
        #expect(wordCount == 1)

        // A duplicate (lang, surface) must be rejected by the UNIQUE constraint.
        await #expect(throws: (any Error).self) {
            try await manager.write { db in
                try db.execute(
                    sql: "INSERT INTO user_word (lang, surface, matchKey, count, lastUsedAt, firstSeenAt) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: ["fa", "سلام", "سلام", 2.0, 2000, 2000]
                )
            }
        }
    }
}
