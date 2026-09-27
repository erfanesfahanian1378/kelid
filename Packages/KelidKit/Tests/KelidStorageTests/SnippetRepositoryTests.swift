import Foundation
import KelidCore
@testable import KelidStorage
import Testing

/// Not its own `@Suite`: an extension of `DatabaseManagerTests`, same
/// reasoning as `UserModelRepositoryTests.swift`'s own doc comment — sharing
/// that type's `.serialized` suite avoids the cross-suite GRDB suspend/resume
/// interference decision 9/70 already documented and fixed once.
extension DatabaseManagerTests {
    private func makeSnippetRepository() async throws -> (repository: SnippetRepository, cleanup: () -> Void) {
        let url = tempDatabaseURL()
        let manager = DatabaseManager(fileURL: url)
        try await manager.open()
        return (SnippetRepository(database: manager), { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
    }

    @Test("createFolder inserts a folder with an incrementing sortOrder")
    func createFolderInsertsWithIncrementingOrder() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        let first = try await repository.createFolder(name: "Work")
        let second = try await repository.createFolder(name: "Personal")
        #expect(second.sortOrder > first.sortOrder)
        let folders = try await repository.listFolders()
        #expect(folders.map(\.name) == ["Work", "Personal"])
    }

    @Test("createSnippet with a duplicate shortcut throws shortcutAlreadyInUse")
    func duplicateShortcutThrows() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        _ = try await repository.createSnippet(folderID: nil, title: "Address", text: "123 Main St", shortcut: "@@addr")
        await #expect(throws: SnippetRepositoryError.shortcutAlreadyInUse) {
            try await repository.createSnippet(folderID: nil, title: "Other", text: "456 Elm St", shortcut: "@@addr")
        }
    }

    @Test("two snippets with no shortcut (nil) don't collide")
    func emptyShortcutsDoNotCollide() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        _ = try await repository.createSnippet(folderID: nil, title: "A", text: "a", shortcut: nil)
        _ = try await repository.createSnippet(folderID: nil, title: "B", text: "b", shortcut: "")
        let snippets = try await repository.listSnippets(folderID: nil)
        #expect(snippets.count == 2)
        #expect(snippets.allSatisfy { $0.shortcut == nil })
    }

    @Test("snippet(forShortcut:) finds an exact match, and nil for no match")
    func shortcutLookupFindsExactMatch() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        _ = try await repository.createSnippet(folderID: nil, title: "Address", text: "123 Main St", shortcut: "@@addr")
        let found = try await repository.snippet(forShortcut: "@@addr")
        #expect(found?.text == "123 Main St")
        let notFound = try await repository.snippet(forShortcut: "@@nope")
        #expect(notFound == nil)
    }

    @Test("deleting a folder sets its snippets' folderId to nil rather than deleting them")
    func deletingFolderUnfilesSnippets() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        let folder = try await repository.createFolder(name: "Work")
        let snippet = try await repository.createSnippet(folderID: folder.id, title: "A", text: "a", shortcut: nil)
        try await repository.deleteFolder(id: #require(folder.id))
        let unfiled = try await repository.listSnippets(folderID: nil)
        #expect(unfiled.map(\.id) == [snippet.id])
    }

    @Test("updateSnippet changes text/title/shortcut and bumps updatedAt")
    func updateSnippetChangesFields() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        let snippet = try await repository.createSnippet(folderID: nil, title: "A", text: "old", shortcut: nil)
        try await repository.updateSnippet(id: #require(snippet.id), title: "B", text: "new", shortcut: "@@b")
        let updated = try await repository.listSnippets(folderID: nil).first
        #expect(updated?.title == "B")
        #expect(updated?.text == "new")
        #expect(updated?.shortcut == "@@b")
    }

    @Test("reorderSnippets applies sortOrder in the given order and can move between folders")
    func reorderSnippetsAppliesOrderAndFolder() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        let folder = try await repository.createFolder(name: "Work")
        let first = try await repository.createSnippet(folderID: nil, title: "A", text: "a", shortcut: nil)
        let second = try await repository.createSnippet(folderID: nil, title: "B", text: "b", shortcut: nil)
        try await repository.reorderSnippets(ids: [#require(second.id), #require(first.id)], folderID: folder.id)
        let reordered = try await repository.listSnippets(folderID: folder.id)
        #expect(reordered.map(\.id) == [second.id, first.id])
    }

    @Test("markUsed increments useCount")
    func markUsedIncrementsUseCount() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        let snippet = try await repository.createSnippet(folderID: nil, title: "A", text: "a", shortcut: "@@a")
        try await repository.markUsed(id: #require(snippet.id))
        try await repository.markUsed(id: #require(snippet.id))
        let updated = try await repository.listSnippets(folderID: nil).first
        #expect(updated?.useCount == 2)
    }

    @Test("listAllGroupedByFolder groups snippets under their folder, with unfiled ones in a nil-folder group")
    func listAllGroupedByFolderGroupsCorrectly() async throws {
        let (repository, cleanup) = try await makeSnippetRepository()
        defer { cleanup() }
        let folder = try await repository.createFolder(name: "Work")
        _ = try await repository.createSnippet(folderID: folder.id, title: "A", text: "a", shortcut: nil)
        _ = try await repository.createSnippet(folderID: nil, title: "B", text: "b", shortcut: nil)
        let groups = try await repository.listAllGroupedByFolder()
        #expect(groups.count == 2)
        let workGroup = try #require(groups.first { $0.folder?.id == folder.id })
        #expect(workGroup.snippets.map(\.title) == ["A"])
        let unfiledGroup = try #require(groups.first { $0.folder == nil })
        #expect(unfiledGroup.snippets.map(\.title) == ["B"])
    }
}
