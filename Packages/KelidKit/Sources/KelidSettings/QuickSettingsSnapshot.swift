import CoreGraphics
import KelidCore

/// The exact set of fields task 4.6's in-keyboard Quick Settings panel (and
/// task 4.7's app-side Size & Layout screen) edit — a flat, orientation-
/// resolved view onto the nested `KeyboardSettings` blob, so the UI layer
/// doesn't need to know which `SizeProfile` (`portrait`/`landscape`) is
/// "current" or repeat that branch at every field.
public struct QuickSettingsSnapshot: Equatable, Sendable {
    // Size (§6.1.3)
    public var rowHeight: CGFloat
    public var bottomLift: CGFloat
    public var oneHanded: OneHandedMode
    public var oneHandedWidthRatio: Double
    public var keyGapH: CGFloat
    public var keyGapV: CGFloat
    public var fontScale: Double
    public var showNumberRow: Bool

    // Typing (§6.1.2/§6.1.8)
    public var keyPopups: Bool
    public var sound: SoundChoice
    public var haptics: HapticsChoice
    public var spaceTrackpad: SpaceTrackpadMode

    // Appearance/theme (§6.1.8, task 11.9)
    public var themeMode: ThemeMode
    public var lightThemeID: String
    public var darkThemeID: String
    public var fixedThemeID: String

    // Language (§6.1.2)
    public var enabledLanguages: [LanguageID]
    public var persianDigits: PersianDigitsMode

    // Clipboard (§6.1.7, task 5.11)
    public var clipboardEnabled: Bool
    public var clipboardCaptureMode: ClipboardCaptureMode
    public var clipboardMaxItems: Int
    public var clipboardRetentionDays: Int?
    public var clipboardShowChip: Bool
    public var clipboardSkipSensitive: Bool
    public var clipboardCaptureImages: Bool

    // Prediction (§6.1.5, task 7.11/9.8) — for `language` specifically (the
    // keyboard panel passes its current typing language; `toolbarMode` is
    // the one field here that isn't per-language).
    public var predictionLanguage: LanguageID
    public var predictionEnabled: Bool
    public var predictionSuggestionCount: Int
    public var predictionShowVerbatimSlot: Bool
    public var predictionPreferZWNJForms: Bool
    public var predictionSource: PredictionSource
    public var predictionPersonalWeight: Double
    public var toolbarMode: ToolbarMode

    /// Learning (§6.1.6, task 9.8) — not per-language; `incognito` is
    /// intentionally excluded here, since it's also mirrored on the
    /// session-only `KeyboardState.incognito` the toolbar toggle (task 9.7)
    /// flips — `QuickSettingsView` binds its incognito toggle straight to a
    /// dedicated callback instead of round-tripping through this snapshot's
    /// generic `apply(to:)`, so the two never fight over which one is current.
    public var learningEnabled: Bool

    public init(settings: KeyboardSettings, orientation: SizeOrientation, language: LanguageID = .fa) {
        let profile = settings.size.profile(for: orientation)
        rowHeight = profile.rowHeight
        bottomLift = profile.bottomLift
        oneHanded = profile.oneHanded
        oneHandedWidthRatio = profile.oneHandedWidthRatio
        keyGapH = profile.keyGapH
        keyGapV = profile.keyGapV
        fontScale = profile.fontScale
        showNumberRow = settings.general.showNumberRow
        keyPopups = settings.general.keyPopups
        sound = settings.appearance.sound
        haptics = settings.appearance.haptics
        spaceTrackpad = settings.general.spaceTrackpad
        themeMode = settings.appearance.themeMode
        lightThemeID = settings.appearance.lightThemeID
        darkThemeID = settings.appearance.darkThemeID
        fixedThemeID = settings.appearance.fixedThemeID
        enabledLanguages = settings.general.enabledLanguages
        persianDigits = settings.general.persianDigits
        clipboardEnabled = settings.clipboard.enabled
        clipboardCaptureMode = settings.clipboard.captureMode
        clipboardMaxItems = settings.clipboard.maxItems
        clipboardRetentionDays = settings.clipboard.retentionDays
        clipboardShowChip = settings.clipboard.showChip
        clipboardSkipSensitive = settings.clipboard.skipSensitive
        clipboardCaptureImages = settings.clipboard.captureImages
        predictionLanguage = language
        let prediction = settings.prediction[language]
        predictionEnabled = prediction.enabled
        predictionSuggestionCount = prediction.suggestionCount
        predictionShowVerbatimSlot = prediction.showVerbatimSlot
        predictionPreferZWNJForms = prediction.preferZWNJForms
        predictionSource = prediction.source
        predictionPersonalWeight = prediction.personalWeight
        toolbarMode = settings.toolbar.mode
        learningEnabled = settings.learning.enabled
    }

    /// §6.3.7's "Reset size" safety net — a snapshot built from
    /// `SizeProfile`'s own static defaults, with `rowHeight` overridden to
    /// the *device-class* default (which those static defaults can't know,
    /// having no notion of the actual screen). Only the size-related fields
    /// are meant to be read from this; the rest just carry `KeyboardSettings()`'s
    /// plain defaults since nothing uses them.
    public static func deviceDefaults(orientation: SizeOrientation, deviceDefaultRowHeight: CGFloat) -> QuickSettingsSnapshot {
        var profile: SizeProfile = orientation == .portrait ? .portraitDefault : .landscapeDefault
        profile.rowHeight = deviceDefaultRowHeight
        var settings = KeyboardSettings()
        settings.size.setProfile(for: orientation) { $0 = profile }
        return QuickSettingsSnapshot(settings: settings, orientation: orientation)
    }

    /// Writes every field back to its place in `settings`, for the given
    /// orientation's `SizeProfile`. `settings.clamped()` is the caller's job
    /// (matches every other settings mutation path, e.g. `SettingsStore.update`).
    public func apply(to settings: inout KeyboardSettings, orientation: SizeOrientation) {
        settings.size.setProfile(for: orientation) { profile in
            profile.rowHeight = rowHeight
            profile.bottomLift = bottomLift
            profile.oneHanded = oneHanded
            profile.oneHandedWidthRatio = oneHandedWidthRatio
            profile.keyGapH = keyGapH
            profile.keyGapV = keyGapV
            profile.fontScale = fontScale
        }
        settings.general.showNumberRow = showNumberRow
        settings.general.keyPopups = keyPopups
        settings.appearance.sound = sound
        settings.appearance.haptics = haptics
        settings.general.spaceTrackpad = spaceTrackpad
        settings.appearance.themeMode = themeMode
        settings.appearance.lightThemeID = lightThemeID
        settings.appearance.darkThemeID = darkThemeID
        settings.appearance.fixedThemeID = fixedThemeID
        settings.general.enabledLanguages = enabledLanguages
        settings.general.persianDigits = persianDigits
        settings.clipboard.enabled = clipboardEnabled
        settings.clipboard.captureMode = clipboardCaptureMode
        settings.clipboard.maxItems = clipboardMaxItems
        settings.clipboard.retentionDays = clipboardRetentionDays
        settings.clipboard.showChip = clipboardShowChip
        settings.clipboard.skipSensitive = clipboardSkipSensitive
        settings.clipboard.captureImages = clipboardCaptureImages
        settings.prediction.setSettings(for: predictionLanguage) { prediction in
            prediction.enabled = predictionEnabled
            prediction.suggestionCount = predictionSuggestionCount
            prediction.showVerbatimSlot = predictionShowVerbatimSlot
            prediction.preferZWNJForms = predictionPreferZWNJForms
            prediction.source = predictionSource
            prediction.personalWeight = predictionPersonalWeight
        }
        settings.toolbar.mode = toolbarMode
        settings.learning.enabled = learningEnabled
    }
}

public extension PredictionLanguageSettings {
    mutating func setSettings(for language: LanguageID, _ transform: (inout PredictionSettings) -> Void) {
        switch language {
        case .fa: transform(&fa)
        case .en: transform(&en)
        }
    }
}

public extension SizeSettings {
    func profile(for orientation: SizeOrientation) -> SizeProfile {
        switch orientation {
        case .portrait: portrait
        case .landscape: landscape
        }
    }

    mutating func setProfile(for orientation: SizeOrientation, _ transform: (inout SizeProfile) -> Void) {
        switch orientation {
        case .portrait: transform(&portrait)
        case .landscape: transform(&landscape)
        }
    }
}
