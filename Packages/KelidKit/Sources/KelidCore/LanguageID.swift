/// One of Kelid's two supported typing languages (PLAN.md §1, D-09: one
/// keyboard extension with internal language switching, not two separate
/// extensions). Lives in `KelidCore` because it's needed by both
/// `KelidSettings` (per-language settings groups) and lower-level modules
/// that depend on `KelidCore` but not on each other.
public enum LanguageID: String, Codable, Sendable, CaseIterable, Identifiable {
    case fa
    case en

    public var id: String {
        rawValue
    }
}
