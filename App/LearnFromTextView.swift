import KelidCore
import KelidStorage
import PersianText
import SwiftUI
import UniformTypeIdentifiers

/// Task 10.6's "Learn from text": paste or import a `.txt` file, tokenize,
/// preview the top new words and their counts, then commit. §6.7.6's own
/// increment table gives "learn from text' import" a 0.5-per-occurrence
/// weight (half of a real typed/accepted commit) — reflected here directly
/// in the imported count, rather than going through `UserModel.recordCommit`
/// one occurrence at a time.
struct LearnFromTextView: View {
    let services: AppServices
    let language: LanguageID
    let onCommitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var preview: [WordFrequencyCounter.WordCount] = []
    @State private var showingImporter = false
    @State private var isCommitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                    Button("Import .txt file…") { showingImporter = true }
                    Button("Preview") { buildPreview() }
                        .disabled(text.isEmpty)
                }
                if !preview.isEmpty {
                    Section("New words (\(preview.count))") {
                        ForEach(preview.prefix(50), id: \.surface) { item in
                            LabeledContent(item.surface, value: "\(item.count)×")
                        }
                    }
                }
            }
            .navigationTitle("Learn from Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") { Task { await commit() } }
                        .disabled(preview.isEmpty || isCommitting)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.plainText]) { result in
                if let url = try? result.get() {
                    loadFile(url)
                }
            }
        }
    }

    private func loadFile(_ url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        buildPreview()
    }

    private func buildPreview() {
        preview = WordFrequencyCounter.count(in: text)
    }

    private func commit() async {
        isCommitting = true
        defer { isCommitting = false }
        let repository = UserModelRepository(database: services.database)
        let now = Date()
        let deltas = preview.map {
            UserWordDelta(
                surface: $0.surface, matchKey: PersianNormalization.matchKey($0.surface), count: Double($0.count) * 0.5, lastUsedAt: now,
                source: .importSource
            )
        }
        try? await repository.importWords(deltas, language: language)
        onCommitted()
        dismiss()
    }
}
