/// Placeholder public type for the `KelidCore` module.
///
/// Phase 0 only proves that this module exists, builds for iOS and macOS,
/// and is wired into the package graph correctly. Real functionality
/// (AppGroup paths, DarwinNotifier, Clock, MemoryProbe, Signposts — see
/// PLAN.md §4.2) is added in Phase 1.
public struct KelidCorePlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
