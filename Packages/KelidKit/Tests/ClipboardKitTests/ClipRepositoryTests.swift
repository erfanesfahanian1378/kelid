@testable import ClipboardKit
import Foundation
import KelidCore
import KelidSettings
@testable import KelidStorage
import Testing

@Suite("ClipRepository", .serialized)
struct ClipRepositoryTests {
    private func makeRepository(clock: Clock = TestClock()) async throws -> ClipRepository {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelid-clip-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("test.sqlite")
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()
        return ClipRepository(database: manager, darwinNotifier: .shared, appGroupIdentifier: nil, clock: clock)
    }

    private func draft(text: String, hash: String, source: ClipSource = .capture) -> ClipDraft {
        ClipDraft(kind: .text, text: text, searchKey: text, contentHash: hash, charCount: text.count, source: source)
    }

    @Test("upsert inserts a new clip and returns it with an id")
    func upsertInsertsNewClip() async throws {
        let repo = try await makeRepository()
        let clip = try await repo.upsert(draft(text: "hello", hash: "h1"))
        #expect(clip.id != nil)
        #expect(clip.text == "hello")
        #expect(clip.copyCount == 1)
    }

    @Test("upsert with an existing contentHash bumps copyCount and lastCopiedAt instead of inserting")
    func upsertDedupesByHash() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1000))
        let repo = try await makeRepository(clock: clock)
        let first = try await repo.upsert(draft(text: "hello", hash: "h1"))

        clock.advance(by: 60)
        let second = try await repo.upsert(draft(text: "hello", hash: "h1"))

        #expect(first.id == second.id)
        #expect(second.copyCount == 2)
        #expect(second.lastCopiedAt == Date(timeIntervalSince1970: 1060))

        let page = try await repo.page(filter: .recent, offset: 0)
        #expect(page.count == 1)
    }

    @Test("page(.recent) orders newest first and excludes pinned")
    func pageRecentOrdering() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        let repo = try await makeRepository(clock: clock)
        let first = try await repo.upsert(draft(text: "one", hash: "h1"))
        clock.advance(by: 10)
        let second = try await repo.upsert(draft(text: "two", hash: "h2"))
        clock.advance(by: 10)
        try await repo.pin(id: #require(second.id))

        let recent = try await repo.page(filter: .recent, offset: 0)
        #expect(recent.map(\.text) == ["one"]) // "two" is pinned, excluded from .recent

        let pinned = try await repo.page(filter: .pinned, offset: 0)
        #expect(pinned.map(\.text) == ["two"])
        _ = first
    }

    @Test("search finds ی when querying ي (searchKey normalization)")
    func searchNormalizesQuery() async throws {
        let repo = try await makeRepository()
        _ = try await repo.upsert(ClipDraft(kind: .text, text: "علی", searchKey: "علی", contentHash: "h1", source: .capture))
        let results = try await repo.search(query: "علي")
        #expect(results.map(\.text) == ["علی"])
    }

    @Test("pin then unpin round-trips isPinned")
    func pinUnpinRoundTrip() async throws {
        let repo = try await makeRepository()
        let clip = try await repo.upsert(draft(text: "hello", hash: "h1"))
        try await repo.pin(id: #require(clip.id))
        #expect(try await repo.page(filter: .pinned, offset: 0).count == 1)
        try await repo.unpin(id: #require(clip.id))
        #expect(try await repo.page(filter: .pinned, offset: 0).count == 0)
        #expect(try await repo.page(filter: .recent, offset: 0).count == 1)
    }

    @Test("delete removes the row and returns its file paths for cleanup")
    func deleteReturnsFilePaths() async throws {
        let repo = try await makeRepository()
        let clip = try await repo.upsert(
            ClipDraft(kind: .image, imageFile: "img.jpg", thumbFile: "thumb.jpg", contentHash: "h1", source: .capture)
        )
        let removedFiles = try await repo.delete(ids: [#require(clip.id)])
        #expect(Set(removedFiles) == ["img.jpg", "thumb.jpg"])
        #expect(try await repo.page(filter: .recent, offset: 0).isEmpty)
    }

    @Test("deleteAll(keepPinned: true) removes only non-pinned rows")
    func deleteAllKeepsPinned() async throws {
        let repo = try await makeRepository()
        let pinned = try await repo.upsert(draft(text: "keep", hash: "h1"))
        try await repo.pin(id: #require(pinned.id))
        _ = try await repo.upsert(draft(text: "gone", hash: "h2"))

        try await repo.deleteAll(keepPinned: true)

        #expect(try await repo.page(filter: .pinned, offset: 0).map(\.text) == ["keep"])
        #expect(try await repo.page(filter: .recent, offset: 0).isEmpty)
    }

    @Test("enforceLimits deletes expired rows")
    func enforceLimitsDeletesExpired() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1000))
        let repo = try await makeRepository(clock: clock)
        _ = try await repo.upsert(ClipDraft(
            kind: .text,
            text: "otp",
            searchKey: "otp",
            contentHash: "h1",
            expiresAt: Date(timeIntervalSince1970: 500),
            source: .capture
        ))
        _ = try await repo.upsert(draft(text: "keep", hash: "h2"))

        try await repo.enforceLimits(settings: ClipboardSettings(), now: clock.now())

        let remaining = try await repo.page(filter: .recent, offset: 0)
        #expect(remaining.map(\.text) == ["keep"])
    }

    @Test("enforceLimits deletes non-pinned rows older than retentionDays, keeping pinned")
    func enforceLimitsAppliesRetention() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 100 * 86400))
        let repo = try await makeRepository(clock: clock)
        let old = try await repo.upsert(draft(text: "old", hash: "h1"))
        try await repo.pin(id: #require(old.id)) // pinned: exempt from retention
        clock.set(Date(timeIntervalSince1970: 0))
        let oldUnpinned = try await repo.upsert(draft(text: "old-unpinned", hash: "h2"))
        clock.set(Date(timeIntervalSince1970: 100 * 86400))

        var settings = ClipboardSettings()
        settings.retentionDays = 30
        try await repo.enforceLimits(settings: settings, now: clock.now())

        let pinned = try await repo.page(filter: .pinned, offset: 0)
        #expect(pinned.map(\.text) == ["old"])
        let recent = try await repo.page(filter: .recent, offset: 0)
        #expect(recent.isEmpty)
        _ = oldUnpinned
    }

    @Test("enforceLimits trims non-pinned rows beyond maxItems, oldest first")
    func enforceLimitsAppliesMaxItems() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        let repo = try await makeRepository(clock: clock)
        for i in 0 ..< 5 {
            _ = try await repo.upsert(draft(text: "clip\(i)", hash: "h\(i)"))
            clock.advance(by: 1)
        }
        var settings = ClipboardSettings()
        settings.retentionDays = nil
        settings.maxItems = 3
        try await repo.enforceLimits(settings: settings, now: clock.now())

        let remaining = try await repo.page(filter: .recent, offset: 0)
        #expect(remaining.count == 3)
        #expect(Set(remaining.map(\.text)) == ["clip2", "clip3", "clip4"])
    }

    @Test("markUsed increments useCount and sets lastUsedAt")
    func markUsedUpdatesUsage() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 500))
        let repo = try await makeRepository(clock: clock)
        let clip = try await repo.upsert(draft(text: "hello", hash: "h1"))
        try await repo.markUsed(id: #require(clip.id))
        let page = try await repo.page(filter: .recent, offset: 0)
        #expect(page.first?.useCount == 1)
        #expect(page.first?.lastUsedAt == Date(timeIntervalSince1970: 500))
    }
}
