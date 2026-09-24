/// Placeholder public type for the `ThemeKit` module.
///
/// Phase 0 only proves that this module exists, builds for iOS and macOS,
/// and that its bundled `BuiltInThemes/` resource folder is wired up
/// correctly (currently a `.keep` marker; real theme JSON, the theme model
/// and resolver are added in Phase 11 — see PLAN.md §6.8).
public struct ThemeKitPlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
