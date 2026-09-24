/// Placeholder public type for the `ClipboardKit` module.
///
/// Phase 0 only proves that this module exists, builds for iOS and macOS,
/// and is wired into the package graph correctly. Real functionality is
/// added by later phases (see PLAN.md §4.2 and §8).
public struct ClipboardKitPlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
