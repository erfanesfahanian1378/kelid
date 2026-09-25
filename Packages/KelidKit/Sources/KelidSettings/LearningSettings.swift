/// PLAN.md §6.1.6.
public struct LearningSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var newWordThreshold: Int
    public var learnPhrases: Bool
    public var halfLifeDays: Int
    public var maxUserWords: Int
    public var useTextReplacements: Bool
    public var useContactNames: Bool
    public var incognito: Bool

    public init(
        enabled: Bool = true,
        newWordThreshold: Int = 2,
        learnPhrases: Bool = true,
        halfLifeDays: Int = 60,
        maxUserWords: Int = 50000,
        useTextReplacements: Bool = true,
        useContactNames: Bool = false,
        incognito: Bool = false
    ) {
        self.enabled = enabled
        self.newWordThreshold = newWordThreshold
        self.learnPhrases = learnPhrases
        self.halfLifeDays = halfLifeDays
        self.maxUserWords = maxUserWords
        self.useTextReplacements = useTextReplacements
        self.useContactNames = useContactNames
        self.incognito = incognito
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, newWordThreshold, learnPhrases, halfLifeDays, maxUserWords
        case useTextReplacements, useContactNames, incognito
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c.value(.enabled, default: d.enabled)
        newWordThreshold = c.value(.newWordThreshold, default: d.newWordThreshold)
        learnPhrases = c.value(.learnPhrases, default: d.learnPhrases)
        halfLifeDays = c.value(.halfLifeDays, default: d.halfLifeDays)
        maxUserWords = c.value(.maxUserWords, default: d.maxUserWords)
        useTextReplacements = c.value(.useTextReplacements, default: d.useTextReplacements)
        useContactNames = c.value(.useContactNames, default: d.useContactNames)
        incognito = c.value(.incognito, default: d.incognito)
    }

    public func clamped() -> LearningSettings {
        var copy = self
        copy.newWordThreshold = copy.newWordThreshold.clamped(to: 1 ... 5)
        copy.halfLifeDays = copy.halfLifeDays.clamped(to: 7 ... 365)
        copy.maxUserWords = copy.maxUserWords.clamped(to: 5000 ... 200_000)
        return copy
    }
}
