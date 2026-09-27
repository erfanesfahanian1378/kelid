import AppIntents
import ClipboardKit
import KelidCore
import KelidStorage
import PersianText

/// Task 10.8: "Save to Kelid" (Shortcuts, Back Tap). Runs in-process
/// without ever opening Kelid's UI — `Back Tap → Shortcuts → Save to Kelid`
/// is meant to be a two-tap capture from anywhere (§6.5.1's `intent` clip
/// source), so this must work headless.
struct SaveTextToKelidIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Save Text to Kelid"
    nonisolated static let description = IntentDescription("Saves the given text to Kelid's clipboard history.")

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult {
        let paths = ContainerPaths.resolve(fullAccess: true)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        try await manager.open()
        await manager.resume()
        let repository = ClipRepository(database: manager)
        let draft = ClipDraft(
            kind: .text, text: text, searchKey: PersianNormalization.searchKey(text),
            contentHash: ClipClassifier.sha256Hex(PersianNormalization.canonical(text)), charCount: text.count, source: .intent
        )
        _ = try await repository.upsert(draft)
        await manager.suspend()
        return .result()
    }
}

/// Task 10.8's other named intent — clears clipboard history (pinned clips
/// are kept, same "keepPinned" default the app's own Clear History button
/// uses for the Recent list).
struct ClearKelidHistoryIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Clear Kelid Clipboard History"
    nonisolated static let description = IntentDescription("Clears Kelid's clipboard history, keeping pinned clips.")

    func perform() async throws -> some IntentResult {
        let paths = ContainerPaths.resolve(fullAccess: true)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        try await manager.open()
        await manager.resume()
        let repository = ClipRepository(database: manager)
        _ = try? await repository.deleteAll(keepPinned: true)
        await manager.suspend()
        return .result()
    }
}

/// Task 10.8: "an `AppShortcutsProvider` with English and Persian phrases."
struct KelidAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveTextToKelidIntent(),
            phrases: [
                "Save to \(.applicationName)",
                "Save text to \(.applicationName)",
                "\(.applicationName) ذخیره در",
            ],
            shortTitle: "Save to Kelid",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: ClearKelidHistoryIntent(),
            phrases: [
                "Clear \(.applicationName) history",
                "\(.applicationName) پاک کردن تاریخچه",
            ],
            shortTitle: "Clear History",
            systemImageName: "trash"
        )
    }
}
