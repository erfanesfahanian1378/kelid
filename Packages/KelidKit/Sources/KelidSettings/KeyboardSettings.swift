import Foundation

/// The one versioned, tolerant `Codable` blob (D-05) holding every Kelid
/// setting — including groups whose features don't exist until a later
/// phase (they're just data; PLAN.md §6.1 lists the phase each is edited
/// starting from). Stored as JSON under `settings.v1` in the App Group
/// `UserDefaults` (shared) and mirrored in the keyboard's local
/// `UserDefaults` (§6.1.1) — see `SettingsStore`.
public struct KeyboardSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var updatedAt: Date
    public var general: GeneralSettings
    public var size: SizeSettings
    public var toolbar: ToolbarSettings
    public var prediction: PredictionLanguageSettings
    public var learning: LearningSettings
    public var clipboard: ClipboardSettings
    public var appearance: AppearanceSettings
    public var emoji: EmojiSettings
    public var snippets: SnippetsSettings
    public var advanced: AdvancedSettings

    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = KeyboardSettings.currentSchemaVersion,
        updatedAt: Date = Date(),
        general: GeneralSettings = GeneralSettings(),
        size: SizeSettings = SizeSettings(),
        toolbar: ToolbarSettings = ToolbarSettings(),
        prediction: PredictionLanguageSettings = PredictionLanguageSettings(),
        learning: LearningSettings = LearningSettings(),
        clipboard: ClipboardSettings = ClipboardSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        emoji: EmojiSettings = EmojiSettings(),
        snippets: SnippetsSettings = SnippetsSettings(),
        advanced: AdvancedSettings = AdvancedSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.general = general
        self.size = size
        self.toolbar = toolbar
        self.prediction = prediction
        self.learning = learning
        self.clipboard = clipboard
        self.appearance = appearance
        self.emoji = emoji
        self.snippets = snippets
        self.advanced = advanced
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, general, size, toolbar, prediction
        case learning, clipboard, appearance, emoji, snippets, advanced
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        schemaVersion = c.value(.schemaVersion, default: d.schemaVersion)
        updatedAt = c.value(.updatedAt, default: d.updatedAt)
        general = c.value(.general, default: d.general)
        size = c.value(.size, default: d.size)
        toolbar = c.value(.toolbar, default: d.toolbar)
        prediction = c.value(.prediction, default: d.prediction)
        learning = c.value(.learning, default: d.learning)
        clipboard = c.value(.clipboard, default: d.clipboard)
        appearance = c.value(.appearance, default: d.appearance)
        emoji = c.value(.emoji, default: d.emoji)
        snippets = c.value(.snippets, default: d.snippets)
        advanced = c.value(.advanced, default: d.advanced)
    }

    /// Enforces every range in §6.1. Runs after decoding and before saving
    /// (§6.1.1). Does not touch `updatedAt`/`schemaVersion` — callers that
    /// are about to save set `updatedAt` themselves (`SettingsStore.update`).
    public func clamped() -> KeyboardSettings {
        var copy = self
        copy.general = general.clamped()
        copy.size = size.clamped()
        copy.toolbar = toolbar.clamped()
        copy.prediction = prediction.clamped()
        copy.learning = learning.clamped()
        copy.clipboard = clipboard.clamped()
        copy.appearance = appearance.clamped()
        copy.emoji = emoji.clamped()
        copy.snippets = snippets.clamped()
        copy.advanced = advanced.clamped()
        return copy
    }
}
