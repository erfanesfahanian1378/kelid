import ClipboardKit
import PersianText
import SwiftUI

/// Task 10.4: the Clipboard tab (§6.10) — pinned/recent lists, search,
/// full-text edit, pin/unpin, reorder pinned, multi-select delete, "Add
/// from clipboard," clear history, and a Snippets sub-tab (task 10.5's app
/// side).
struct ClipboardManagerView: View {
    let services: AppServices

    @State private var filter: ClipFilter = .recent
    @State private var clips: [Clip] = []
    @State private var searchText = ""
    @State private var editingClip: Clip?
    @State private var selection = Set<Int64>()
    @State private var isEditing = false
    @State private var showingClearConfirmation = false
    @State private var isLocked = false

    var body: some View {
        Group {
            if isLocked {
                lockedView
            } else {
                contentView
            }
        }
        .navigationTitle("Clipboard")
        .task { await checkLock() }
    }

    private var lockedView: some View {
        ContentUnavailableView {
            Label("Locked", systemImage: "lock.fill")
        } description: {
            Text("Unlock with Face ID to view your clipboard.")
        } actions: {
            Button("Unlock") { Task { await checkLock() } }
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $filter) {
                Text("Recent").tag(ClipFilter.recent)
                Text("Pinned").tag(ClipFilter.pinned)
            }
            .pickerStyle(.segmented)
            .padding()

            List(selection: $selection) {
                ForEach(displayedClips) { clip in
                    ClipRowView(clip: clip)
                        .swipeActions(edge: .leading) {
                            Button(clip.isPinned ? "Unpin" : "Pin") { Task { await togglePin(clip) } }
                                .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { Task { await delete([clip.id!]) } }
                        }
                        .onTapGesture {
                            if !isEditing {
                                editingClip = clip
                            }
                        }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search clips")
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(isEditing ? "Done" : "Select") { isEditing.toggle() }
                    if isEditing, !selection.isEmpty {
                        Button("Delete Selected", role: .destructive) { Task { await delete(Array(selection)) } }
                    }
                    NavigationLink("Snippets") { SnippetsView(services: services) }
                    NavigationLink("Clipboard Settings") { ClipboardSettingsView(services: services) }
                    Button("Clear History", role: .destructive) { showingClearConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                PasteControlView(onPaste: { text in Task { await addFromClipboard(text) } })
                    .fixedSize()
            }
        }
        .confirmationDialog(
            filter == .pinned ? "Clear all pinned clips?" : "Clear clipboard history?", isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { Task { await clearHistory() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingClip) { clip in
            ClipEditView(clip: clip, onSave: { newText in Task { await save(clip, text: newText) } })
        }
        .task(id: filter) { await reload() }
        .onChange(of: searchText) { _, newValue in Task { await search(newValue) } }
    }

    private var displayedClips: [Clip] {
        searchText.isEmpty ? clips : clips.filter { $0.text?.localizedCaseInsensitiveContains(searchText) ?? false }
    }

    private func checkLock() async {
        guard services.settings.settings.clipboard.lockWithFaceID else {
            isLocked = false
            return
        }
        isLocked = await !(BiometricLock.authenticate(reason: "Unlock your clipboard"))
    }

    private func reload() async {
        clips = await (try? services.clipRepository.page(filter: filter, offset: 0, limit: 500)) ?? []
    }

    private func search(_ query: String) async {
        guard !query.isEmpty else { return }
        clips = await (try? services.clipRepository.search(query: query, limit: 200)) ?? clips
    }

    private func togglePin(_ clip: Clip) async {
        try? await (clip.isPinned ? services.clipRepository.unpin(id: clip.id!) : services.clipRepository.pin(id: clip.id!))
        await reload()
    }

    private func delete(_ ids: [Int64]) async {
        _ = try? await services.clipRepository.delete(ids: ids)
        selection.removeAll()
        await reload()
    }

    private func clearHistory() async {
        _ = try? await services.clipRepository.deleteAll(keepPinned: filter == .recent)
        await reload()
    }

    private func save(_ clip: Clip, text: String) async {
        // Editing a clip's text is a delete-then-recapture-as-a-new-draft:
        // `ClipRepository` has no direct "update text in place" — its own
        // upsert path is keyed by content hash, which a text edit
        // necessarily changes anyway.
        _ = try? await services.clipRepository.delete(ids: [clip.id!])
        let draft = ClipDraft(
            kind: .text, text: text, searchKey: PersianNormalization.searchKey(text),
            contentHash: ClipClassifier.sha256Hex(PersianNormalization.canonical(text)), source: .app
        )
        if let inserted = try? await services.clipRepository.upsert(draft), clip.isPinned {
            try? await services.clipRepository.pin(id: inserted.id!)
        }
        await reload()
    }

    private func addFromClipboard(_ text: String) async {
        let draft = ClipDraft(
            kind: .text, text: text, searchKey: PersianNormalization.searchKey(text),
            contentHash: ClipClassifier.sha256Hex(PersianNormalization.canonical(text)), source: .app
        )
        _ = try? await services.clipRepository.upsert(draft)
        await reload()
    }
}

private struct ClipRowView: View {
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.text ?? "(image)")
                .lineLimit(2)
            Text(clip.lastCopiedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClipEditView: View {
    let clip: Clip
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(clip: Clip, onSave: @escaping (String) -> Void) {
        self.clip = clip
        self.onSave = onSave
        _text = State(initialValue: clip.text ?? "")
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Edit Clip")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(text); dismiss() }
                    }
                }
        }
    }
}
