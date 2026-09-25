/// PLAN.md §6.1.11.
public struct AdvancedSettings: Codable, Sendable, Equatable {
    public var debugOverlay: Bool
    /// Debug builds only — the app/keyboard UI is responsible for hiding
    /// this control in release builds; the setting itself has no notion of
    /// build configuration.
    public var pasteboardLab: Bool

    public init(debugOverlay: Bool = false, pasteboardLab: Bool = false) {
        self.debugOverlay = debugOverlay
        self.pasteboardLab = pasteboardLab
    }

    private enum CodingKeys: String, CodingKey {
        case debugOverlay, pasteboardLab
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        debugOverlay = c.value(.debugOverlay, default: d.debugOverlay)
        pasteboardLab = c.value(.pasteboardLab, default: d.pasteboardLab)
    }

    public func clamped() -> AdvancedSettings {
        self
    }
}
