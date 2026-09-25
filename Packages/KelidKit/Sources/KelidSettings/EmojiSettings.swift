import KelidCore

/// "None + 5 Fitzpatrick tones" (§6.1.9).
public enum SkinTone: String, Codable, Sendable, CaseIterable {
    case none
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark
}

/// PLAN.md §6.1.9.
public struct EmojiSettings: Codable, Sendable, Equatable {
    public var defaultSkinTone: SkinTone
    public var recentsLimit: Int
    public var searchLanguages: [LanguageID]

    public init(
        defaultSkinTone: SkinTone = .none,
        recentsLimit: Int = 32,
        searchLanguages: [LanguageID] = [.fa, .en]
    ) {
        self.defaultSkinTone = defaultSkinTone
        self.recentsLimit = recentsLimit
        self.searchLanguages = searchLanguages
    }

    private enum CodingKeys: String, CodingKey {
        case defaultSkinTone, recentsLimit, searchLanguages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        defaultSkinTone = c.value(.defaultSkinTone, default: d.defaultSkinTone)
        recentsLimit = c.value(.recentsLimit, default: d.recentsLimit)
        searchLanguages = c.value(.searchLanguages, default: d.searchLanguages)
    }

    public func clamped() -> EmojiSettings {
        var copy = self
        copy.recentsLimit = copy.recentsLimit.clamped(to: 16 ... 64)
        return copy
    }
}
