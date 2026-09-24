/// Placeholder public type for the `KeyboardLayout` module.
///
/// Phase 0 only proves that this module exists, builds for iOS and macOS,
/// and that its bundled `Layouts/` resource folder is wired up correctly
/// (currently a `.keep` marker; real layout JSON files, `LayoutValidator`
/// and `LayoutEngine` geometry are added in Phase 2 — see PLAN.md §6.2).
public struct KeyboardLayoutPlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
