import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// §6.11.7's `.kelidbackup` — declared as `UTExportedTypeDeclarations`
    /// in `project.yml`'s Info.plist properties so `fileExporter`/
    /// `fileImporter` (task 10.9) recognize the extension. `nonisolated`:
    /// referenced from `BackupDocument`'s own `nonisolated` context.
    nonisolated static let kelidBackup = UTType(exportedAs: "com.example.kelid.backup", conformingTo: .json)
}

/// A `FileDocument` wrapper around an already-encoded `KelidBackup` — built
/// fresh by `BackupService.makeBackup(services:)` right before presenting
/// the exporter, so it never goes stale sitting in view state. `nonisolated`:
/// `FileDocument`'s requirements are synchronous and not `@MainActor`, but
/// this whole target defaults to `@MainActor` isolation — this pure-data
/// type has no actor-isolated state to protect, so opting it out entirely
/// is simpler than isolating each member individually.
nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.kelidBackup]

    let data: Data

    init(backup: KelidBackup) {
        data = (try? BackupService.encoder.encode(backup)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
