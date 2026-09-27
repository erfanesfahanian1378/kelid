import KelidCore
import KelidSettings
import KelidStorage
import SwiftUI

/// Task 10.3/10.9/10.10: §6.1.11's advanced settings, plus backup/restore
/// (task 10.9 adds the actual `.kelidbackup` export/import UI here),
/// "reset all," and §6.12's "Delete all Kelid data."
struct AdvancedSettingsView: View {
    let services: AppServices
    @State private var showingResetConfirmation = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var backupDocument: BackupDocument?
    @State private var importResultMessage: String?
    @State private var includeUserWordsInBackup = true
    @State private var showingDeleteAllConfirmation = false

    var body: some View {
        formContent
            .navigationTitle("Advanced")
            .modifier(ResetConfirmationModifier(isPresented: $showingResetConfirmation, services: services))
            .modifier(DeleteAllConfirmationModifier(isPresented: $showingDeleteAllConfirmation, onConfirm: deleteAllData))
            .modifier(BackupFileModifiers(
                showingExporter: $showingExporter, showingImporter: $showingImporter, backupDocument: backupDocument,
                onImport: handleImport
            ))
            .alert("Restore", isPresented: Binding(get: { importResultMessage != nil }, set: { _ in importResultMessage = nil })) {
                Button("OK") {}
            } message: {
                Text(importResultMessage ?? "")
            }
    }

    private var formContent: some View {
        Form {
            debugSection
            backupSection
            resetSection
            deleteAllSection
        }
    }

    private var debugSection: some View {
        Section("Debug") {
            Toggle("Debug overlay", isOn: bind(\.advanced.debugOverlay))
        }
    }

    private var backupSection: some View {
        Section {
            Toggle("Include my learned words", isOn: $includeUserWordsInBackup)
            Button("Back up to file…") { prepareExport() }
            Button("Restore from file…") { showingImporter = true }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup includes your settings, snippets and pinned clips. Restoring merges it into what's already here.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset all settings", role: .destructive) { showingResetConfirmation = true }
        }
    }

    private var deleteAllSection: some View {
        Section {
            Button("Delete all Kelid data", role: .destructive) { showingDeleteAllConfirmation = true }
        } footer: {
            Text("Deletes your clipboard history, snippets, and learned words on this device. This can't be undone.")
        }
    }

    private func prepareExport() {
        Task {
            let backup = await BackupService.makeBackup(services: services, includeUserWords: includeUserWordsInBackup)
            backupDocument = BackupDocument(backup: backup)
            showingExporter = true
        }
    }

    private func deleteAllData() {
        Task {
            _ = try? await services.clipRepository.deleteAll(keepPinned: false)
            try? await services.snippetRepository.deleteAllSnippetsAndFolders()
            let userModelRepository = UserModelRepository(database: services.database)
            for language in LanguageID.allCases {
                try? await userModelRepository.deleteAll(language: language)
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                let summary = try await BackupService.restore(from: url, services: services)
                importResultMessage = summary
            } catch {
                importResultMessage = "Couldn't restore that file: \(error.localizedDescription)"
            }
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

/// Extracted `ViewModifier`s purely so `AdvancedSettingsView.body` stays a
/// short, fast-to-type-check expression — SwiftUI's type checker choked on
/// the original single chain of `Form` + 3 sheet-like modifiers, each with
/// its own multi-branch button closures.
private struct ResetConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let services: AppServices

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Reset all settings to their defaults?", isPresented: $isPresented, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { services.settings.update { $0 = KeyboardSettings() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct DeleteAllConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete all clipboard history, snippets and learned words?", isPresented: $isPresented, titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct BackupFileModifiers: ViewModifier {
    @Binding var showingExporter: Bool
    @Binding var showingImporter: Bool
    let backupDocument: BackupDocument?
    let onImport: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $showingExporter, document: backupDocument, contentType: .kelidBackup,
                defaultFilename: "Kelid Backup"
            ) { _ in }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.kelidBackup], onCompletion: onImport)
    }
}
