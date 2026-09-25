/// PLAN.md §6.1.10.
public struct SnippetsSettings: Codable, Sendable, Equatable {
    /// A snippet's shortcut followed by space is replaced by its text.
    public var expansionEnabled: Bool

    public init(expansionEnabled: Bool = true) {
        self.expansionEnabled = expansionEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case expansionEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        expansionEnabled = c.value(.expansionEnabled, default: d.expansionEnabled)
    }

    public func clamped() -> SnippetsSettings {
        self
    }
}
