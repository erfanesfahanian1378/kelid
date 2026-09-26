@testable import ClipboardKit
import Foundation
import KelidCore
import KelidSettings
@testable import KelidStorage
import Testing

@MainActor
@Suite("ClipboardMonitor", .serialized)
struct ClipboardMonitorTests {
    private func makeRepository() async throws -> ClipRepository {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelid-monitor-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("test.sqlite")
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()
        return ClipRepository(database: manager, darwinNotifier: .shared, appGroupIdentifier: nil)
    }

    private let now = Date(timeIntervalSince1970: 1000)

    @Test("no read happens when changeCount is unchanged")
    func noReadWhenChangeCountUnchanged() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 5
        pasteboard.string = "hello"
        pasteboard.hasStrings = true
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 5)

        let outcome = await monitor.check(fullAccess: true, incognito: false, settings: ClipboardSettings(), now: now)
        #expect(outcome == .noChange)
        let stored = try await repo.page(filter: .recent, offset: 0)
        #expect(stored.isEmpty)
    }

    @Test(".onTap mode never reads content, only reports pendingTap")
    func onTapDoesNotReadContent() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.string = "secret content"
        pasteboard.hasStrings = true
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        var settings = ClipboardSettings()
        settings.captureMode = .onTap
        let outcome = await monitor.check(fullAccess: true, incognito: false, settings: settings, now: now)
        #expect(outcome == .pendingTap)
        let stored = try await repo.page(filter: .recent, offset: 0)
        #expect(stored.isEmpty) // never stored without an explicit readNow()
    }

    @Test("own writes update lastSeenChangeCount so they aren't re-captured")
    func ownWritesAreNotRecaptured() async throws {
        let pasteboard = FakePasteboardClient()
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        pasteboard.setString("keyboard wrote this") // bumps changeCount internally
        monitor.noteOwnWrite()

        let outcome = await monitor.check(fullAccess: true, incognito: false, settings: ClipboardSettings(), now: now)
        #expect(outcome == .noChange)
    }

    @Test("incognito blocks capture even when changeCount changed")
    func incognitoBlocksCapture() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.string = "hello"
        pasteboard.hasStrings = true
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        let outcome = await monitor.check(fullAccess: true, incognito: true, settings: ClipboardSettings(), now: now)
        #expect(outcome == .blocked)
        #expect(try await repo.page(filter: .recent, offset: 0).isEmpty)
    }

    @Test("without Full Access, capture is blocked")
    func noFullAccessBlocksCapture() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.string = "hello"
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        let outcome = await monitor.check(fullAccess: false, incognito: false, settings: ClipboardSettings(), now: now)
        #expect(outcome == .blocked)
    }

    @Test(".auto mode reads, classifies and stores text content, changing the pasteboard change count marker")
    func autoModeStoresContent() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.string = "hello world"
        pasteboard.hasStrings = true
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        var settings = ClipboardSettings()
        settings.captureMode = .auto
        let outcome = await monitor.check(fullAccess: true, incognito: false, settings: settings, now: now)
        guard case let .captured(clip) = outcome else {
            Issue.record("expected .captured, got \(outcome)")
            return
        }
        #expect(clip.text == "hello world")
        #expect(try await repo.page(filter: .recent, offset: 0).count == 1)
    }

    @Test("skipSensitive blocks capture when a sensitive pasteboard type is present")
    func skipSensitiveBlocksCapture() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.typeIdentifiers = ["org.nspasteboard.ConcealedType"]
        pasteboard.string = "1Password generated this"
        pasteboard.hasStrings = true
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        let outcome = await monitor.check(fullAccess: true, incognito: false, settings: ClipboardSettings(), now: now)
        #expect(outcome == .skippedSensitiveType)
        #expect(try await repo.page(filter: .recent, offset: 0).isEmpty)
    }

    @Test("image content is reported as imageCaptureNeeded, not stored directly")
    func imageContentReportedNotStored() async throws {
        let pasteboard = FakePasteboardClient()
        pasteboard.changeCount = 1
        pasteboard.hasImages = true
        pasteboard.imageData = Data([0x01, 0x02, 0x03])
        let repo = try await makeRepository()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repo, initialChangeCount: 0)

        var settings = ClipboardSettings()
        settings.captureMode = .auto
        let outcome = await monitor.check(fullAccess: true, incognito: false, settings: settings, now: now)
        #expect(outcome == .imageCaptureNeeded(Data([0x01, 0x02, 0x03])))
        #expect(try await repo.page(filter: .recent, offset: 0).isEmpty)
    }
}
