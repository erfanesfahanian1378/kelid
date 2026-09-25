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

    // Language (§6.1.2)
    public var enabledLanguages: [LanguageID]
    public var persianDigits: PersianDigitsMode

    public init(settings: KeyboardSettings, orientation: SizeOrientation) {
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
        enabledLanguages = settings.general.enabledLanguages
        persianDigits = settings.general.persianDigits
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
        settings.general.enabledLanguages = enabledLanguages
        settings.general.persianDigits = persianDigits
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
