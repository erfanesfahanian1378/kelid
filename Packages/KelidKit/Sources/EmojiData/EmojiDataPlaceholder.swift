/// Placeholder public type for the `EmojiData` module.
///
/// Phase 0 only proves that this module exists, builds for iOS and macOS,
/// and that its bundled `emoji.json` resource (currently `[]`) loads
/// correctly. The real emoji dataset, search index, recents and skin tones
/// are added in Phase 12 — see PLAN.md §6.9.
public struct EmojiDataPlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
