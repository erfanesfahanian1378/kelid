import KelidCore
import KelidStorage
import PersianText
import SwiftUI

/// Task 10.6: per-language learned words — search, sort, add, block/unblock,
/// "Learn from text," statistics, and reset.
struct DictionaryView: View {
    let services: AppServices

    @State private var language: LanguageID = .fa
    @State private var words: [UserWord] = []
    @State private var blockedSurfaces: Set<String> = []
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .count
    @State private var showingAddWord = false
    @State private var newWordText = ""
    @State private var showingLearnFromText = false
    @State private var showingResetConfirmation = false

    enum SortOrder: String, CaseIterable {
        case count = "Count"
        case recent = "Recent"
        case alphabetical = "A–Z"
    }

    private var repository: UserModelRepository {
        UserModelRepository(database: services.database)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Language", selection: $language) {
                Text("Persian").tag(LanguageID.fa)
                Text("English").tag(LanguageID.en)
            }
            .pickerStyle(.segmented)
            .padding()

            Text("\(words.count) words")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(displayedWords, id: \.surface) { word in
                    WordRowView(word: word, isBlocked: blockedSurfaces.contains(word.surface))
                        .swipeActions(edge: .trailing) {
                            Button("Forget", role: .destructive) { Task { await forget(word) } }
                        }
                        .swipeActions(edge: .leading) {
                            Button(blockedSurfaces.contains(word.surface) ? "Unblock" : "Block") { Task { await toggleBlock(word) } }
                                .tint(.orange)
                        }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search words")
        }
        .navigationTitle("Dictionary")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button("Add word…") { showingAddWord = true }
                    Button("Learn from text…") { showingLearnFromText = true }
                    Button("Reset personal data", role: .destructive) { showingResetConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Add Word", isPresented: $showingAddWord) {
            TextField("Word", text: $newWordText)
            Button("Add") { Task { await addWord() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Reset all learned words for this language?", isPresented: $showingResetConfirmation, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { Task { await resetPersonalData() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingLearnFromText) {
            LearnFromTextView(services: services, language: language, onCommitted: { Task { await reload() } })
        }
        .task(id: language) { await reload() }
    }

    private var displayedWords: [UserWord] {
        var filtered = searchText.isEmpty ? words : words.filter { $0.surface.localizedCaseInsensitiveContains(searchText) }
        switch sortOrder {
        case .count: filtered.sort { $0.count > $1.count }
        case .recent: filtered.sort { $0.lastUsedAt > $1.lastUsedAt }
        case .alphabetical: filtered.sort { $0.surface < $1.surface }
        }
        return filtered
    }

    private func reload() async {
        let repo = repository
        words = await (try? repo.loadWords(language: language, limit: 5000)) ?? []
        blockedSurfaces = await (try? repo.loadBlockedWords(language: language)) ?? []
    }

    private func addWord() async {
        guard !newWordText.isEmpty else { return }
        try? await repository.addManualWord(surface: newWordText, language: language)
        newWordText = ""
        await reload()
    }

    private func forget(_ word: UserWord) async {
        try? await repository.forget(surface: word.surface, language: language)
        await reload()
    }

    private func toggleBlock(_ word: UserWord) async {
        let newValue = !blockedSurfaces.contains(word.surface)
        try? await repository.setBlocked(newValue, surface: word.surface, language: language)
        await reload()
    }

    private func resetPersonalData() async {
        try? await repository.deleteAll(language: language)
        await reload()
    }
}

private struct WordRowView: View {
    let word: UserWord
    let isBlocked: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(word.surface)
                    .strikethrough(isBlocked)
                Text("\(Int(word.count)) uses · \(word.source.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBlocked {
                Image(systemName: "eye.slash").foregroundStyle(.secondary)
            }
        }
    }
}
