/// Text direction of a layout (PLAN.md §6.2.1). Rows are always written in
/// **visual** left-to-right order regardless of this — only text direction
/// and bottom-row slot order are RTL (§8 Phase 2 pitfall).
public enum Direction: String, Codable, Sendable, Equatable {
    case ltr
    case rtl
}
