public enum ToolbarMode: String, Codable, Sendable, CaseIterable {
    case auto
    case suggestionsOnly
    case iconsOnly
    case hidden
}

public enum ToolbarItem: String, Codable, Sendable, CaseIterable {
    case clipboard
    case emoji
    case edit
    case resize
    case oneHanded
    case settings
    case incognito
    case snippets
    case dismiss
    case language
}

/// PLAN.md §6.1.4.
public struct ToolbarSettings: Codable, Sendable, Equatable {
    public var mode: ToolbarMode
    public var items: [ToolbarItem]

    public init(
        mode: ToolbarMode = .auto,
        items: [ToolbarItem] = [.clipboard, .emoji, .edit, .resize, .oneHanded, .settings]
    ) {
        self.mode = mode
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case mode, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        mode = c.value(.mode, default: d.mode)
        items = c.value(.items, default: d.items)
    }

    /// Up to 7 items (§6.1.4); extras beyond that are dropped rather than
    /// causing an error, keeping a too-long imported/edited list usable.
    public func clamped() -> ToolbarSettings {
        var copy = self
        if copy.items.count > 7 {
            copy.items = Array(copy.items.prefix(7))
        }
        return copy
    }
}
