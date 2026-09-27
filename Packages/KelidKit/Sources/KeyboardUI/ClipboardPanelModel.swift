#if canImport(UIKit)
    import ClipboardKit
    import KelidStorage
    import Observation

    /// §6.5.6's clipboard panel state. `KeyboardController` populates this
    /// (one fetch of up to 50 rows per tab/search when the panel opens or a
    /// mutation happens — not true infinite-scroll paging, a reasonable
    /// scope simplification for a keyboard-extension-sized list) and wires
    /// the action closures; the SwiftUI view only ever reads/calls this.
    @MainActor
    @Observable
    public final class ClipboardPanelModel {
        public enum Tab: Sendable, Equatable {
            case recent
            case pinned
            /// Task 10.5: browse-and-insert only — folder/snippet CRUD is
            /// the app's Clipboard → Snippets sub-tab job (§6.10), not this
            /// panel's.
            case snippets
        }

        public var tab: Tab = .recent
        public var searchQuery = ""
        public var isSearching = false
        public var recentClips: [Clip] = []
        public var pinnedClips: [Clip] = []
        public var searchResults: [Clip] = []
        public var snippetGroups: [SnippetFolderContents] = []
        public var isCapturePaused: Bool
        public let hasFullAccess: Bool
        /// Clips whose sensitive mask the user has long-press-revealed —
        /// cleared whenever the panel reloads.
        public var revealedIDs: Set<Int64> = []

        var onTapClip: ((Clip) -> Void)?
        var onTogglePin: ((Clip) -> Void)?
        var onDelete: ((Clip) -> Void)?
        var onClearAll: (() -> Void)?
        var onTogglePause: (() -> Void)?
        var onSearchQueryChanged: ((String) -> Void)?
        var onOpenFullAccessSettings: (() -> Void)?
        var onTapSnippet: ((Snippet) -> Void)?
        var onDone: (() -> Void)?

        public init(hasFullAccess: Bool, isCapturePaused: Bool) {
            self.hasFullAccess = hasFullAccess
            self.isCapturePaused = isCapturePaused
        }
    }
#endif
