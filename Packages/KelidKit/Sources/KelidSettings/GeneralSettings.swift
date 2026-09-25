import KelidCore

public enum PersianLayoutID: String, Codable, Sendable, CaseIterable {
    case standard
    case compact
    case standard4Row
}

public enum EnglishLayoutID: String, Codable, Sendable, CaseIterable {
    case qwerty
}

public enum LanguageSwitchMode: String, Codable, Sendable, CaseIterable {
    case key
    case spaceSwipe
    case both
}

public enum PersianDigitsMode: String, Codable, Sendable, CaseIterable {
    case persian
    case latin
}

public enum NumpadDigitsMode: String, Codable, Sendable, CaseIterable {
    case latin
    case persian
}

public enum SpaceTrackpadMode: String, Codable, Sendable, CaseIterable {
    case off
    case drag
    case longPress
}

public enum BackspaceRepeatSpeed: String, Codable, Sendable, CaseIterable {
    case slow
    case normal
    case fast
}

/// PLAN.md §6.1.2.
public struct GeneralSettings: Codable, Sendable, Equatable {
    public var enabledLanguages: [LanguageID]
    public var persianLayout: PersianLayoutID
    public var englishLayout: EnglishLayoutID
    public var languageSwitch: LanguageSwitchMode
    public var rememberLastLanguage: Bool
    public var showNumberRow: Bool
    public var persianDigits: PersianDigitsMode
    public var numpadDigits: NumpadDigitsMode
    public var longPressDelayMs: Int
    public var keyPopups: Bool
    public var keyHints: Bool
    public var doubleSpacePeriod: Bool
    public var autoCapitalize: Bool
    public var smartPunctuationSpacing: Bool
    public var spaceTrackpad: SpaceTrackpadMode
    public var cursorSpeed: Double
    public var rtlVisualCursor: Bool
    public var backspaceSwipeDeletesWords: Bool
    public var backspaceRepeat: BackspaceRepeatSpeed
    public var bottomRowEmojiKey: Bool

    public init(
        enabledLanguages: [LanguageID] = [.fa, .en],
        persianLayout: PersianLayoutID = .standard,
        englishLayout: EnglishLayoutID = .qwerty,
        languageSwitch: LanguageSwitchMode = .key,
        rememberLastLanguage: Bool = true,
        showNumberRow: Bool = false,
        persianDigits: PersianDigitsMode = .persian,
        numpadDigits: NumpadDigitsMode = .latin,
        longPressDelayMs: Int = 350,
        keyPopups: Bool = true,
        keyHints: Bool = false,
        doubleSpacePeriod: Bool = true,
        autoCapitalize: Bool = true,
        smartPunctuationSpacing: Bool = true,
        spaceTrackpad: SpaceTrackpadMode = .drag,
        cursorSpeed: Double = 1.0,
        rtlVisualCursor: Bool = true,
        backspaceSwipeDeletesWords: Bool = true,
        backspaceRepeat: BackspaceRepeatSpeed = .normal,
        bottomRowEmojiKey: Bool = false
    ) {
        self.enabledLanguages = enabledLanguages
        self.persianLayout = persianLayout
        self.englishLayout = englishLayout
        self.languageSwitch = languageSwitch
        self.rememberLastLanguage = rememberLastLanguage
        self.showNumberRow = showNumberRow
        self.persianDigits = persianDigits
        self.numpadDigits = numpadDigits
        self.longPressDelayMs = longPressDelayMs
        self.keyPopups = keyPopups
        self.keyHints = keyHints
        self.doubleSpacePeriod = doubleSpacePeriod
        self.autoCapitalize = autoCapitalize
        self.smartPunctuationSpacing = smartPunctuationSpacing
        self.spaceTrackpad = spaceTrackpad
        self.cursorSpeed = cursorSpeed
        self.rtlVisualCursor = rtlVisualCursor
        self.backspaceSwipeDeletesWords = backspaceSwipeDeletesWords
        self.backspaceRepeat = backspaceRepeat
        self.bottomRowEmojiKey = bottomRowEmojiKey
    }

    private enum CodingKeys: String, CodingKey {
        case enabledLanguages, persianLayout, englishLayout, languageSwitch, rememberLastLanguage
        case showNumberRow, persianDigits, numpadDigits, longPressDelayMs, keyPopups, keyHints
        case doubleSpacePeriod, autoCapitalize, smartPunctuationSpacing, spaceTrackpad, cursorSpeed
        case rtlVisualCursor, backspaceSwipeDeletesWords, backspaceRepeat, bottomRowEmojiKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabledLanguages = c.value(.enabledLanguages, default: d.enabledLanguages)
        persianLayout = c.value(.persianLayout, default: d.persianLayout)
        englishLayout = c.value(.englishLayout, default: d.englishLayout)
        languageSwitch = c.value(.languageSwitch, default: d.languageSwitch)
        rememberLastLanguage = c.value(.rememberLastLanguage, default: d.rememberLastLanguage)
        showNumberRow = c.value(.showNumberRow, default: d.showNumberRow)
        persianDigits = c.value(.persianDigits, default: d.persianDigits)
        numpadDigits = c.value(.numpadDigits, default: d.numpadDigits)
        longPressDelayMs = c.value(.longPressDelayMs, default: d.longPressDelayMs)
        keyPopups = c.value(.keyPopups, default: d.keyPopups)
        keyHints = c.value(.keyHints, default: d.keyHints)
        doubleSpacePeriod = c.value(.doubleSpacePeriod, default: d.doubleSpacePeriod)
        autoCapitalize = c.value(.autoCapitalize, default: d.autoCapitalize)
        smartPunctuationSpacing = c.value(.smartPunctuationSpacing, default: d.smartPunctuationSpacing)
        spaceTrackpad = c.value(.spaceTrackpad, default: d.spaceTrackpad)
        cursorSpeed = c.value(.cursorSpeed, default: d.cursorSpeed)
        rtlVisualCursor = c.value(.rtlVisualCursor, default: d.rtlVisualCursor)
        backspaceSwipeDeletesWords = c.value(.backspaceSwipeDeletesWords, default: d.backspaceSwipeDeletesWords)
        backspaceRepeat = c.value(.backspaceRepeat, default: d.backspaceRepeat)
        bottomRowEmojiKey = c.value(.bottomRowEmojiKey, default: d.bottomRowEmojiKey)
    }

    public func clamped() -> GeneralSettings {
        var copy = self
        if copy.enabledLanguages.isEmpty {
            copy.enabledLanguages = [.fa]
        }
        copy.longPressDelayMs = copy.longPressDelayMs.clamped(to: 200 ... 800)
        copy.cursorSpeed = copy.cursorSpeed.clamped(to: 0.5 ... 2.0)
        return copy
    }
}
