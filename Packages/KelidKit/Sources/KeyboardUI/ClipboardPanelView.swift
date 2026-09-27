#if canImport(UIKit)
    import ClipboardKit
    import KelidStorage
    import SwiftUI

    /// Task 5.5/5.6/5.12's clipboard panel. `KeyboardController` populates
    /// `ClipboardPanelModel` and wires its action closures; this view only
    /// reads/calls it.
    public struct ClipboardPanelView: View {
        @Bindable var model: ClipboardPanelModel

        public init(model: ClipboardPanelModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                Group {
                    if !model.hasFullAccess {
                        noFullAccessState
                    } else if model.isSearching {
                        searchResultsList
                    } else {
                        tabbedList
                    }
                }
                .navigationTitle("Clipboard")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: { model.onDone?() })
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            model.onTogglePause?()
                        } label: {
                            Image(systemName: model.isCapturePaused ? "play.circle" : "pause.circle")
                        }
                        .accessibilityLabel(model.isCapturePaused ? "resume capture" : "pause capture")
                    }
                }
                .searchable(text: searchBinding, prompt: "Search clips")
            }
        }

        private var searchBinding: Binding<String> {
            Binding(get: { model.searchQuery }, set: { model.onSearchQueryChanged?($0) })
        }

        private var tabbedList: some View {
            VStack(spacing: 0) {
                Picker("Tab", selection: $model.tab) {
                    Text("Recent").tag(ClipboardPanelModel.Tab.recent)
                    Text("Pinned").tag(ClipboardPanelModel.Tab.pinned)
                    Text("Snippets").tag(ClipboardPanelModel.Tab.snippets)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)

                if model.tab == .snippets {
                    snippetsList
                } else {
                    clipsList
                }
            }
        }

        @ViewBuilder
        private var clipsList: some View {
            let clips = model.tab == .recent ? model.recentClips : model.pinnedClips
            if clips.isEmpty {
                emptyState
            } else {
                List(clips) { clip in
                    ClipRowView(clip: clip, isRevealed: model.revealedIDs.contains(clip.id ?? -1)) {
                        model.onTapClip?(clip)
                    } onReveal: {
                        if let id = clip.id {
                            model.revealedIDs.insert(id)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { model.onDelete?(clip) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button(clip.isPinned ? "Unpin" : "Pin") { model.onTogglePin?(clip) }
                        Button("Delete", role: .destructive) { model.onDelete?(clip) }
                    }
                }
                .listStyle(.plain)
                if model.tab == .recent {
                    Button("Clear (keep pinned)", role: .destructive) { model.onClearAll?() }
                        .padding(.vertical, 6)
                }
            }
        }

        // MARK: - Snippets tab (task 10.5)

        /// Task 10.5: browse-and-tap-to-insert only, grouped by folder
        /// exactly like the app's own Snippets sub-tab — no CRUD here.
        @ViewBuilder
        private var snippetsList: some View {
            if model.snippetGroups.allSatisfy(\.snippets.isEmpty) {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No snippets yet — add some from the Kelid app")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(model.snippetGroups, id: \.folder?.id) { group in
                        if !group.snippets.isEmpty {
                            Section(group.folder?.name ?? "Unfiled") {
                                ForEach(group.snippets) { snippet in
                                    Button(snippet.title ?? snippet.text) { model.onTapSnippet?(snippet) }
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }

        @ViewBuilder
        private var searchResultsList: some View {
            if model.searchResults.isEmpty {
                ContentUnavailableView.search
            } else {
                List(model.searchResults) { clip in
                    ClipRowView(clip: clip, isRevealed: model.revealedIDs.contains(clip.id ?? -1)) {
                        model.onTapClip?(clip)
                    } onReveal: {
                        if let id = clip.id {
                            model.revealedIDs.insert(id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }

        private var emptyState: some View {
            VStack(spacing: 8) {
                Spacer()
                if model.isCapturePaused {
                    Text("Capture is paused")
                    Button("Resume", action: { model.onTogglePause?() })
                } else {
                    Text(model.tab == .recent ? "Copy something and it appears here" : "No pinned clips yet")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }

        /// §6.5.6's no-Full-Access empty state.
        private var noFullAccessState: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Clipboard needs Full Access")
                    .font(.headline)
                Text("Settings → General → Keyboard → Keyboards → Kelid → Allow Full Access")
                    .font(.subheadline)
                Text("Kelid never sends your clipboard anywhere — everything stays on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings", action: { model.onOpenFullAccessSettings?() })
                Spacer()
            }
            .padding()
        }
    }

    private struct ClipRowView: View {
        let clip: Clip
        let isRevealed: Bool
        let onTap: () -> Void
        let onReveal: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack {
                    icon
                    Text(displayText)
                        .lineLimit(2)
                        .multilineTextAlignment(alignment)
                        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
                    if clip.isPinned {
                        Image(systemName: "pin.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .onLongPressGesture {
                if clip.isSensitive {
                    onReveal()
                }
            }
        }

        private var icon: Image {
            switch clip.kind {
            case .text: Image(systemName: "doc.text")
            case .url: Image(systemName: "link")
            case .image: Image(systemName: "photo")
            }
        }

        private var displayText: String {
            if clip.kind == .image {
                return "Image"
            }
            guard let text = clip.text else { return "" }
            return clip.isSensitive && !isRevealed ? "••••••" : text
        }

        /// §6.5.6: RTL if the first strong character is RTL.
        private var alignment: TextAlignment {
            guard let first = displayText.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return .leading }
            let isRTL = (0x0590 ... 0x08FF).contains(first.value) || (0xFB1D ... 0xFDFF).contains(first.value) || (0xFE70 ... 0xFEFF)
                .contains(first.value)
            return isRTL ? .trailing : .leading
        }
    }

#endif
