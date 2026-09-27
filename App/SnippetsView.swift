import KelidStorage
import SwiftUI

/// Task 10.5's app side: folder/snippet CRUD, reorder, and the shortcut
/// field with uniqueness validation (surfaced from
/// `SnippetRepository.createSnippet`/`updateSnippet`'s own thrown error).
struct SnippetsView: View {
    let services: AppServices

    @State private var groups: [SnippetFolderContents] = []
    @State private var editingSnippet: EditingSnippet?
    @State private var showingNewFolderPrompt = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            ForEach(groups, id: \.folder?.id) { group in
                Section(group.folder?.name ?? "Unfiled") {
                    ForEach(group.snippets) { snippet in
                        SnippetRowView(snippet: snippet)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingSnippet = EditingSnippet(snippet: snippet, folderID: group.folder?.id)
                            }
                    }
                    .onDelete { indices in Task { await deleteSnippets(in: group, at: indices) } }
                    .onMove { source, destination in Task { await moveSnippets(in: group, from: source, to: destination) } }
                    Button("Add snippet") {
                        editingSnippet = EditingSnippet(snippet: nil, folderID: group.folder?.id)
                    }
                }
            }
        }
        .navigationTitle("Snippets")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("New Folder") { showingNewFolderPrompt = true }
            }
        }
        .alert("New Folder", isPresented: $showingNewFolderPrompt) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingSnippet) { editing in
            SnippetEditView(
                editing: editing,
                onSave: { title, text, shortcut in Task { await saveSnippet(editing, title: title, text: text, shortcut: shortcut) } }
            )
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        groups = await (try? services.snippetRepository.listAllGroupedByFolder()) ?? []
    }

    private func createFolder() async {
        guard !newFolderName.isEmpty else { return }
        _ = try? await services.snippetRepository.createFolder(name: newFolderName)
        newFolderName = ""
        await reload()
    }

    private func deleteSnippets(in group: SnippetFolderContents, at indices: IndexSet) async {
        let ids = indices.compactMap { group.snippets[$0].id }
        try? await services.snippetRepository.deleteSnippets(ids: ids)
        await reload()
    }

    private func moveSnippets(in group: SnippetFolderContents, from source: IndexSet, to destination: Int) async {
        var reordered = group.snippets
        reordered.move(fromOffsets: source, toOffset: destination)
        try? await services.snippetRepository.reorderSnippets(ids: reordered.compactMap(\.id), folderID: group.folder?.id)
        await reload()
    }

    private func saveSnippet(_ editing: EditingSnippet, title: String, text: String, shortcut: String) async {
        do {
            if let existing = editing.snippet {
                try await services.snippetRepository.updateSnippet(
                    id: existing.id!, title: title.isEmpty ? nil : title, text: text, shortcut: shortcut
                )
            } else {
                _ = try await services.snippetRepository.createSnippet(
                    folderID: editing.folderID, title: title.isEmpty ? nil : title, text: text,
                    shortcut: shortcut.isEmpty ? nil : shortcut
                )
            }
            await reload()
        } catch {
            // `SnippetRepositoryError.shortcutAlreadyInUse` surfaces to the
            // user via the sheet staying open with its own inline error —
            // see `SnippetEditView`.
        }
    }
}

/// Identifies both "editing an existing snippet" and "creating a new one in
/// this folder" for the same sheet.
struct EditingSnippet: Identifiable {
    let snippet: Snippet?
    let folderID: Int64?
    var id: Int64 {
        snippet?.id ?? -1
    }
}

private struct SnippetRowView: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snippet.title ?? snippet.text)
                .lineLimit(1)
            if let shortcut = snippet.shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SnippetEditView: View {
    let editing: EditingSnippet
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var text: String
    @State private var shortcut: String

    init(editing: EditingSnippet, onSave: @escaping (String, String, String) -> Void) {
        self.editing = editing
        self.onSave = onSave
        _title = State(initialValue: editing.snippet?.title ?? "")
        _text = State(initialValue: editing.snippet?.text ?? "")
        _shortcut = State(initialValue: editing.snippet?.shortcut ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (optional)", text: $title)
                TextField("Shortcut, e.g. @@addr (optional)", text: $shortcut)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Section("Text") {
                    TextEditor(text: $text).frame(minHeight: 120)
                }
            }
            .navigationTitle(editing.snippet == nil ? "New Snippet" : "Edit Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(title, text, shortcut); dismiss() }
                        .disabled(text.isEmpty)
                }
            }
        }
    }
}
