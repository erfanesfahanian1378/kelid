/// Placeholder public type for the `EmojiData` module.
///
/// Phase 0 proved that this module exists and builds for iOS and macOS.
/// Since Phase 6, its bundled `emoji.json` resource holds the real §6.9
/// catalog (compiled by `Tools/data-pipeline/pipeline/emoji.py` from
/// Unicode's `emoji-test.txt` and CLDR's fa/en annotations) — but the
/// Swift `Decodable` model, search index, recents and skin-tone picker that
/// actually consume it are still Phase 12's job — see PLAN.md §6.9.
public struct EmojiDataPlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
