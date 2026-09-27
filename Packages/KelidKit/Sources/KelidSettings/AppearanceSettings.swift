public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case fixed
    case followSystem
    case followApp
}

public enum PersianFontChoice: String, Codable, Sendable, CaseIterable {
    case system
    case vazirmatn
}

public enum LatinFontChoice: String, Codable, Sendable, CaseIterable {
    case system
    case rounded
    case monospaced
}

public enum KeyPressAnimation: String, Codable, Sendable, CaseIterable {
    case none
    case pop
    case fade
}

public enum SoundChoice: String, Codable, Sendable, CaseIterable {
    case off
    case system
    case soft
    case typewriter
}

public enum HapticsChoice: String, Codable, Sendable, CaseIterable {
    case off
    case light
    case medium
    case rigid
}

/// PLAN.md §6.1.8. No numeric ranges here, so `clamped()` is a no-op kept
/// only for interface consistency with the other settings groups.
public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var themeMode: ThemeMode
    public var lightThemeID: String
    public var darkThemeID: String
    public var fixedThemeID: String
    public var persianFont: PersianFontChoice
    public var latinFont: LatinFontChoice
    public var keyPressAnimation: KeyPressAnimation
    public var sound: SoundChoice
    public var haptics: HapticsChoice
    public var reduceHapticsInLowPower: Bool

    public init(
        themeMode: ThemeMode = .followApp,
        lightThemeID: String = "kelid.glass.light",
        darkThemeID: String = "kelid.glass.dark",
        fixedThemeID: String = "kelid.glass.light",
        persianFont: PersianFontChoice = .system,
        latinFont: LatinFontChoice = .system,
        keyPressAnimation: KeyPressAnimation = .pop,
        sound: SoundChoice = .off,
        haptics: HapticsChoice = .light,
        reduceHapticsInLowPower: Bool = true
    ) {
        self.themeMode = themeMode
        self.lightThemeID = lightThemeID
        self.darkThemeID = darkThemeID
        self.fixedThemeID = fixedThemeID
        self.persianFont = persianFont
        self.latinFont = latinFont
        self.keyPressAnimation = keyPressAnimation
        self.sound = sound
        self.haptics = haptics
        self.reduceHapticsInLowPower = reduceHapticsInLowPower
    }

    private enum CodingKeys: String, CodingKey {
        case themeMode, lightThemeID, darkThemeID, fixedThemeID, persianFont, latinFont
        case keyPressAnimation, sound, haptics, reduceHapticsInLowPower
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        themeMode = c.value(.themeMode, default: d.themeMode)
        lightThemeID = c.value(.lightThemeID, default: d.lightThemeID)
        darkThemeID = c.value(.darkThemeID, default: d.darkThemeID)
        fixedThemeID = c.value(.fixedThemeID, default: d.fixedThemeID)
        persianFont = c.value(.persianFont, default: d.persianFont)
        latinFont = c.value(.latinFont, default: d.latinFont)
        keyPressAnimation = c.value(.keyPressAnimation, default: d.keyPressAnimation)
        sound = c.value(.sound, default: d.sound)
        haptics = c.value(.haptics, default: d.haptics)
        reduceHapticsInLowPower = c.value(.reduceHapticsInLowPower, default: d.reduceHapticsInLowPower)
    }

    public func clamped() -> AppearanceSettings {
        self
    }
}
