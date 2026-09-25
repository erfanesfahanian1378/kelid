import Foundation
import GRDB
@testable import KelidStorage
import Testing

// Serialized: GRDB's suspend/resume notifications are not scoped to the
// posting pool in practice — concurrently-running tests that suspend/resume
// different `DatabasePool`s were observed to interfere with each other.
@Suite("DatabaseManager", .serialized)
struct DatabaseManagerTests {
    private func tempDatabaseURL() -> URL {
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
}
