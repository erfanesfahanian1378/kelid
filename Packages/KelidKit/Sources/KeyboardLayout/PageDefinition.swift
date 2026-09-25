/// One page's key rows (PLAN.md §6.2.1). Rows are written in **visual**
/// left-to-right order, even for Persian (ض is the leftmost key, in the Q
/// position) — only text direction is RTL.
public struct PageDefinition: Codable, Sendable, Equatable {
    public var rows: [[KeyDefinition]]

    public init(rows: [[KeyDefinition]]) {
        self.rows = rows
    }
}
