import KelidCore

public enum PredictionSource: String, Codable, Sendable, CaseIterable {
    case off
    case personalOnly
    case languageOnly
    case hybrid
}

public enum AutocorrectMode: String, Codable, Sendable, CaseIterable {
    case off
    case suggestOnly
    case auto
}

/// PLAN.md §6.1.5, one per language. Like `SizeProfile`, fa and en have
/// different defaults for some fields (`personalWeight`, `autocorrect`), so
/// this isn't itself `Decodable` — `PredictionLanguageSettings` below
/// decodes each side with the right default explicitly.
public struct PredictionSettings: Sendable, Equatable {
    public var enabled: Bool
    public var source: PredictionSource
    public var personalWeight: Double
    public var nextWord: Bool
    public var suggestionCount: Int
    public var autocorrect: AutocorrectMode
    public var autocorrectStrength: Double
    public var emojiSuggestions: Bool
    public var showVerbatimSlot: Bool
    /// fa only — suggestions use the canonical ZWNJ spelling (می‌خوام).
    /// Kept (unused) on the English side too, for structural simplicity.
    public var preferZWNJForms: Bool
    public var blockOffensive: Bool

    public init(
        enabled: Bool = true,
        source: PredictionSource = .hybrid,
        personalWeight: Double,
        nextWord: Bool = true,
        suggestionCount: Int = 3,
        autocorrect: AutocorrectMode,
        autocorrectStrength: Double = 0.5,
        emojiSuggestions: Bool = true,
        showVerbatimSlot: Bool = true,
        preferZWNJForms: Bool = true,
        blockOffensive: Bool = true
    ) {
        self.enabled = enabled
        self.source = source
        self.personalWeight = personalWeight
        self.nextWord = nextWord
        self.suggestionCount = suggestionCount
        self.autocorrect = autocorrect
        self.autocorrectStrength = autocorrectStrength
        self.emojiSuggestions = emojiSuggestions
        self.showVerbatimSlot = showVerbatimSlot
        self.preferZWNJForms = preferZWNJForms
        self.blockOffensive = blockOffensive
    }

    public static let faDefault = PredictionSettings(personalWeight: 0.6, autocorrect: .suggestOnly)
    public static let enDefault = PredictionSettings(personalWeight: 0.5, autocorrect: .auto)

    enum CodingKeys: String, CodingKey {
        case enabled, source, personalWeight, nextWord, suggestionCount, autocorrect
        case autocorrectStrength, emojiSuggestions, showVerbatimSlot, preferZWNJForms, blockOffensive
    }

    static func decode(from container: KeyedDecodingContainer<CodingKeys>, default d: PredictionSettings) -> PredictionSettings {
        PredictionSettings(
            enabled: container.value(.enabled, default: d.enabled),
            source: container.value(.source, default: d.source),
            personalWeight: container.value(.personalWeight, default: d.personalWeight),
            nextWord: container.value(.nextWord, default: d.nextWord),
            suggestionCount: container.value(.suggestionCount, default: d.suggestionCount),
            autocorrect: container.value(.autocorrect, default: d.autocorrect),
            autocorrectStrength: container.value(.autocorrectStrength, default: d.autocorrectStrength),
            emojiSuggestions: container.value(.emojiSuggestions, default: d.emojiSuggestions),
            showVerbatimSlot: container.value(.showVerbatimSlot, default: d.showVerbatimSlot),
            preferZWNJForms: container.value(.preferZWNJForms, default: d.preferZWNJForms),
            blockOffensive: container.value(.blockOffensive, default: d.blockOffensive)
        )
    }

    func encode(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(enabled, forKey: .enabled)
        try container.encode(source, forKey: .source)
        try container.encode(personalWeight, forKey: .personalWeight)
        try container.encode(nextWord, forKey: .nextWord)
        try container.encode(suggestionCount, forKey: .suggestionCount)
        try container.encode(autocorrect, forKey: .autocorrect)
        try container.encode(autocorrectStrength, forKey: .autocorrectStrength)
        try container.encode(emojiSuggestions, forKey: .emojiSuggestions)
        try container.encode(showVerbatimSlot, forKey: .showVerbatimSlot)
        try container.encode(preferZWNJForms, forKey: .preferZWNJForms)
        try container.encode(blockOffensive, forKey: .blockOffensive)
    }

    func clamped() -> PredictionSettings {
        var copy = self
        copy.personalWeight = copy.personalWeight.clamped(to: 0 ... 1)
        copy.suggestionCount = copy.suggestionCount.clamped(to: 3 ... 5)
        copy.autocorrectStrength = copy.autocorrectStrength.clamped(to: 0 ... 1)
        return copy
    }
}

/// PLAN.md §6.1.5: `prediction.fa`, `prediction.en`.
public struct PredictionLanguageSettings: Codable, Sendable, Equatable {
    public var fa: PredictionSettings
    public var en: PredictionSettings

    public init(fa: PredictionSettings = .faDefault, en: PredictionSettings = .enDefault) {
        self.fa = fa
        self.en = en
    }

    private enum CodingKeys: String, CodingKey {
        case fa, en
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.nestedContainer(keyedBy: PredictionSettings.CodingKeys.self, forKey: .fa) {
            fa = PredictionSettings.decode(from: nested, default: .faDefault)
        } else {
            fa = .faDefault
        }
        if let nested = try? c.nestedContainer(keyedBy: PredictionSettings.CodingKeys.self, forKey: .en) {
            en = PredictionSettings.decode(from: nested, default: .enDefault)
        } else {
            en = .enDefault
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var faContainer = c.nestedContainer(keyedBy: PredictionSettings.CodingKeys.self, forKey: .fa)
        try fa.encode(into: &faContainer)
        var enContainer = c.nestedContainer(keyedBy: PredictionSettings.CodingKeys.self, forKey: .en)
        try en.encode(into: &enContainer)
    }

    public func clamped() -> PredictionLanguageSettings {
        PredictionLanguageSettings(fa: fa.clamped(), en: en.clamped())
    }

    /// §6.1.5 resolved by language — the shape `SettingsStore.resolvedPrediction(for:)` (task 1.2) exposes.
    public subscript(language: LanguageID) -> PredictionSettings {
        switch language {
        case .fa: fa
        case .en: en
        }
    }
}
