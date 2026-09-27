import SwiftUI
import ThemeKit
import UniformTypeIdentifiers

extension UTType {
    /// §6.8.7's `.kelidtheme` — declared as `UTExportedTypeDeclarations` in
    /// `project.yml`'s Info.plist properties, same pattern as `.kelidBackup`.
    nonisolated static let kelidTheme = UTType(exportedAs: "com.example.kelid.theme", conformingTo: .json)
}

/// A `FileDocument` wrapper around one `Theme` — the export/import format is
/// literally the same JSON `Theme.swift` already reads/writes for custom
/// theme storage (§6.8.7 doesn't ask for anything richer than that; an
/// `.image` background's file is referenced by name only, same limitation
/// `BackupClip` accepts for v1 — the image itself isn't embedded in the
/// exported file). `nonisolated`, same reasoning as `BackupDocument`.
nonisolated struct ThemeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.kelidTheme]

    let theme: Theme

    init(theme: Theme) {
        self.theme = theme
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        theme = try JSONDecoder().decode(Theme.self, from: data)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(theme)) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
