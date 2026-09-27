import ClipboardKit
import Foundation
import KelidCore
import KelidSettings
import KelidStorage
import PersianText

/// §6.11.7's `.kelidbackup` format — a single UTF-8 JSON file, no zip
/// library needed. `themes` is omitted entirely rather than an empty
/// placeholder array: Kelid has no custom themes to back up until Phase 11
/// builds the theme editor, and adding the field now with nothing real to
/// put in it would just be dead schema.
nonisolated struct KelidBackup: Codable {
    var format = 1
    var createdAt: String
    var appVersion: String
    var settings: KeyboardSettings
    var snippetFolders: [BackupSnippetFolder]
    var snippets: [BackupSnippet]
    var pinnedClips: [BackupClip]
    /// `nil` when the person chose not to include personal words on export
    /// (§6.11.7: "optional (user choice)") — keyed by `LanguageID.rawValue`.
    var userWords: [String: [BackupUserWord]]?
}

nonisolated struct BackupSnippetFolder: Codable {
    var uuid: UUID
    var name: String
    var icon: String?
    var sortOrder: Double
}

nonisolated struct BackupSnippet: Codable {
    var uuid: UUID
    var folderUUID: UUID?
    var title: String?
    var text: String
    var shortcut: String?
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date
    var useCount: Int
}

/// Task 10.9's v1 scope covers text/URL clips only — an image clip's file
/// on disk would need to be embedded too (§6.11.7 sketches an
/// `imageBase64` field for exactly this), which this session didn't build;
/// image clips are silently skipped on export rather than exported broken.
nonisolated struct BackupClip: Codable {
    var uuid: UUID
    var kind: String
    var text: String
    var createdAt: Date
    var lastCopiedAt: Date
    var source: String
}

nonisolated struct BackupUserWord: Codable {
    var surface: String
    var matchKey: String
    var count: Double
    var lastUsedAt: Date
    var source: String
}

/// Builds and restores `.kelidbackup` files (task 10.9). A plain `enum`
/// namespace, not a type instance — every operation is a one-shot function
/// of `AppServices`' already-shared repositories, nothing to hold state on.
enum BackupService {
    /// `nonisolated`: `BackupDocument` (a `FileDocument`, which isn't
    /// `@MainActor`) needs to call this from outside the App target's
    /// default `@MainActor` isolation; `JSONEncoder`/`JSONDecoder` are
    /// themselves `Sendable` in this SDK, so no `(unsafe)` escape hatch is
    /// needed, just an explicit opt-out of the file's default isolation.
    nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @MainActor
    static func makeBackup(services: AppServices, includeUserWords: Bool = true) async -> KelidBackup {
        let groups = await (try? services.snippetRepository.listAllGroupedByFolder()) ?? []
        let folders = groups.compactMap(\.folder).map {
            BackupSnippetFolder(uuid: $0.uuid, name: $0.name, icon: $0.icon, sortOrder: $0.sortOrder)
        }
        let snippets = groups.flatMap { group in
            group.snippets.map { snippet in
                BackupSnippet(
                    uuid: snippet.uuid, folderUUID: group.folder?.uuid, title: snippet.title, text: snippet.text,
                    shortcut: snippet.shortcut, sortOrder: snippet.sortOrder, createdAt: snippet.createdAt,
                    updatedAt: snippet.updatedAt, useCount: snippet.useCount
                )
            }
        }
        let pinned = await (try? services.clipRepository.page(filter: .pinned, offset: 0, limit: 10000)) ?? []
        let pinnedClips: [BackupClip] = pinned.compactMap { clip in
            guard clip.kind != .image, let text = clip.text else { return nil } // v1 scope — see BackupClip's doc comment
            return BackupClip(
                uuid: clip.uuid, kind: clip.kind.rawValue, text: text, createdAt: clip.createdAt, lastCopiedAt: clip.lastCopiedAt,
                source: clip.source.rawValue
            )
        }
        var userWords: [String: [BackupUserWord]]?
        if includeUserWords {
            let repository = UserModelRepository(database: services.database)
            var byLanguage: [String: [BackupUserWord]] = [:]
            for language in LanguageID.allCases {
                let words = await (try? repository.loadWords(language: language, limit: 200_000)) ?? []
                byLanguage[language.rawValue] = words.map {
                    BackupUserWord(
                        surface: $0.surface,
                        matchKey: $0.matchKey,
                        count: $0.count,
                        lastUsedAt: $0.lastUsedAt,
                        source: $0.source.rawValue
                    )
                }
            }
            userWords = byLanguage
        }
        let formatter = ISO8601DateFormatter()
        return KelidBackup(
            createdAt: formatter.string(from: Date()),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            settings: services.settings.settings,
            snippetFolders: folders,
            snippets: snippets,
            pinnedClips: pinnedClips,
            userWords: userWords
        )
    }

    /// Import **merges** (§6.11.7): by `uuid` for snippet folders/snippets
    /// and clips, by `surface` for user words (sum counts) — never a
    /// destructive wholesale replace, except for `settings`, which a
    /// restore is naturally expected to overwrite outright (there's no
    /// sensible per-field "merge" for a settings blob). Returns a short
    /// human-readable summary for the caller to show.
    @MainActor
    static func restore(from url: URL, services: AppServices) async throws -> String {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let backup = try decoder.decode(KelidBackup.self, from: data)

        services.settings.update { $0 = backup.settings }

        var folderIDByUUID: [UUID: Int64] = [:]
        for folder in backup.snippetFolders {
            let id = try await services.snippetRepository.importFolder(
                uuid: folder.uuid, name: folder.name, icon: folder.icon, sortOrder: folder.sortOrder
            )
            folderIDByUUID[folder.uuid] = id
        }
        for snippet in backup.snippets {
            try await services.snippetRepository.importSnippet(
                SnippetImportRecord(
                    uuid: snippet.uuid, folderID: snippet.folderUUID.flatMap { folderIDByUUID[$0] }, title: snippet.title,
                    text: snippet.text, shortcut: snippet.shortcut, sortOrder: snippet.sortOrder, createdAt: snippet.createdAt,
                    updatedAt: snippet.updatedAt, useCount: snippet.useCount
                )
            )
        }

        var importedClipCount = 0
        for clip in backup.pinnedClips {
            guard let kind = ClipKind(rawValue: clip.kind), let source = ClipSource(rawValue: clip.source) else { continue }
            // `ClipDraft` has no `createdAt`/`lastCopiedAt` of its own —
            // `ClipRepository.upsert(_:)` always stamps "now" on insert, so
            // a restored clip's original timestamps (still recorded in the
            // backup JSON itself) aren't preserved on the row; a reasonable
            // trade-off against adding a whole new repository method just
            // for backup restore's sake.
            let draft = ClipDraft(
                kind: kind, text: clip.text, searchKey: PersianNormalization.searchKey(clip.text),
                contentHash: ClipClassifier.sha256Hex(PersianNormalization.canonical(clip.text)), source: source
            )
            let inserted = try await services.clipRepository.upsert(draft)
            try await services.clipRepository.pin(id: inserted.id!)
            importedClipCount += 1
        }

        var importedWordCount = 0
        if let userWords = backup.userWords {
            let repository = UserModelRepository(database: services.database)
            for (languageRaw, words) in userWords {
                guard let language = LanguageID(rawValue: languageRaw) else { continue }
                let deltas = words.map {
                    UserWordDelta(
                        surface: $0.surface, matchKey: $0.matchKey, count: $0.count, lastUsedAt: $0.lastUsedAt,
                        source: UserWordSource(rawValue: $0.source) ?? .typed
                    )
                }
                try await repository.importWords(deltas, language: language)
                importedWordCount += deltas.count
            }
        }

        return "Restored \(backup.snippets.count) snippets, \(importedClipCount) pinned clips"
            + (backup.userWords != nil ? ", \(importedWordCount) learned words" : "") + "."
    }
}
