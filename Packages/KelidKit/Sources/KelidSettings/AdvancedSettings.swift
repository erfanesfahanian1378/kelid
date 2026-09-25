/// PLAN.md §6.1.11.
public struct AdvancedSettings: Codable, Sendable, Equatable {
    public var debugOverlay: Bool
    /// Debug builds only — the app/keyboard UI is responsible for hiding
    /// this control in release builds; the setting itself has no notion of
    /// build configuration.
    public var pasteboardLab: Bool
    /// Not in §6.1.11's own table — an internal one-time marker for task
    /// 4.2's "device-class defaults computed at first run": once `true`,
    /// `SettingsStore.applyDeviceSizeDefaultsIfNeeded` never overwrites
    /// `size.portrait.rowHeight` again, so a later manual resize is never
    /// silently reverted. Lives here (the versioned settings blob) rather
    /// than a separate raw `UserDefaults` key so it gets the same
    /// local/shared sync semantics `SettingsStore` already provides.
    public var deviceSizeDefaultsApplied: Bool

    public init(debugOverlay: Bool = false, pasteboardLab: Bool = false, deviceSizeDefaultsApplied: Bool = false) {
        self.debugOverlay = debugOverlay
        self.pasteboardLab = pasteboardLab
        self.deviceSizeDefaultsApplied = deviceSizeDefaultsApplied
    }

    private enum CodingKeys: String, CodingKey {
        case debugOverlay, pasteboardLab, deviceSizeDefaultsApplied
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        debugOverlay = c.value(.debugOverlay, default: d.debugOverlay)
        pasteboardLab = c.value(.pasteboardLab, default: d.pasteboardLab)
        deviceSizeDefaultsApplied = c.value(.deviceSizeDefaultsApplied, default: d.deviceSizeDefaultsApplied)
    }

    public func clamped() -> AdvancedSettings {
        self
    }
}
