import KelidCore
import KelidSettings

/// The slice of `KeyboardSettings` (§6.1) `InputProcessor` actually reads.
/// A narrow struct rather than the whole settings blob, so
/// `InputProcessor`'s tests don't need to construct (or care about) clip,
/// prediction, theme, etc. settings that have nothing to do with it.
public struct InputSettings: Sendable, Equatable {
    public var enabledLanguages: [LanguageID]
    public var doubleSpacePeriod: Bool
    public var autoCapitalize: Bool
    public var smartPunctuationSpacing: Bool
    public var backspaceSwipeDeletesWords: Bool
    public var backspaceRepeat: BackspaceRepeatSpeed
    public var spaceTrackpad: SpaceTrackpadMode
    public var cursorSpeed: Double
    public var rtlVisualCursor: Bool
    public var longPressDelayMs: Int
    public var languageSwitch: LanguageSwitchMode
    /// `ClipboardSettings.smartSpacing` (§6.5.5) — lives here, not fetched
    /// from `ClipboardKit` directly, since `InputEngine` doesn't depend on
    /// it (module boundary: `InputProcessor` never touches clip storage,
    /// only already-resolved text via `.insertClip`).
    public var clipSmartSpacing: Bool

    public init(
        enabledLanguages: [LanguageID] = [.fa, .en],
        doubleSpacePeriod: Bool = true,
        autoCapitalize: Bool = true,
        smartPunctuationSpacing: Bool = true,
        backspaceSwipeDeletesWords: Bool = true,
        backspaceRepeat: BackspaceRepeatSpeed = .normal,
        spaceTrackpad: SpaceTrackpadMode = .drag,
        cursorSpeed: Double = 1.0,
        rtlVisualCursor: Bool = true,
        longPressDelayMs: Int = 350,
        languageSwitch: LanguageSwitchMode = .key,
        clipSmartSpacing: Bool = true
    ) {
        self.enabledLanguages = enabledLanguages
        self.doubleSpacePeriod = doubleSpacePeriod
        self.autoCapitalize = autoCapitalize
        self.smartPunctuationSpacing = smartPunctuationSpacing
        self.backspaceSwipeDeletesWords = backspaceSwipeDeletesWords
        self.backspaceRepeat = backspaceRepeat
        self.spaceTrackpad = spaceTrackpad
        self.cursorSpeed = cursorSpeed
        self.rtlVisualCursor = rtlVisualCursor
        self.longPressDelayMs = longPressDelayMs
        self.languageSwitch = languageSwitch
        self.clipSmartSpacing = clipSmartSpacing
    }

    public init(_ general: GeneralSettings, clipSmartSpacing: Bool = true) {
        self.init(
            enabledLanguages: general.enabledLanguages,
            doubleSpacePeriod: general.doubleSpacePeriod,
            autoCapitalize: general.autoCapitalize,
            smartPunctuationSpacing: general.smartPunctuationSpacing,
            backspaceSwipeDeletesWords: general.backspaceSwipeDeletesWords,
            backspaceRepeat: general.backspaceRepeat,
            spaceTrackpad: general.spaceTrackpad,
            cursorSpeed: general.cursorSpeed,
            rtlVisualCursor: general.rtlVisualCursor,
            longPressDelayMs: general.longPressDelayMs,
            languageSwitch: general.languageSwitch,
            clipSmartSpacing: clipSmartSpacing
        )
    }
}
