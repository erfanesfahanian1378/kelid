import Foundation

/// PLAN.md §6.8.1's theme JSON schema, decoded as-is. Colors are plain
/// `#RRGGBB`/`#RRGGBBAA` hex strings, not `UIColor` — this module must stay
/// UIKit-free (CLAUDE.md: "ThemeKit model ... must not import UIKit"), so
/// hex-to-color conversion happens in `KeyboardUI` (`KeyStyle.make(from:)`)
/// and the App target's SwiftUI code.
public struct Theme: Codable, Sendable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var name: ThemeName
    public var isDark: Bool
    public var background: ThemeBackground
    public var keys: ThemeKeys
    public var fonts: ThemeFonts
    public var toolbar: ThemeToolbar
    public var callout: ThemeCallout
    public var panel: ThemePanel

    public init(
        schemaVersion: Int = 1, id: String, name: ThemeName, isDark: Bool, background: ThemeBackground, keys: ThemeKeys,
        fonts: ThemeFonts = ThemeFonts(), toolbar: ThemeToolbar, callout: ThemeCallout, panel: ThemePanel
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.isDark = isDark
        self.background = background
        self.keys = keys
        self.fonts = fonts
        self.toolbar = toolbar
        self.callout = callout
        self.panel = panel
    }

    /// The deepest safety net `ThemeResolver` falls back to if even the
    /// bundled `BuiltInThemeCatalog` somehow fails to load `kelid.light`/
    /// `kelid.dark` (should be unreachable in a real build — bundled JSON
    /// resources don't go missing — but a resolver that can silently return
    /// no theme at all would be worse than one with a hardcoded last resort).
    /// Colors match `KeyboardUI.KeyStyle.light`/`.dark`'s original Phase 3 palette.
    public static let fallbackLight = Theme(
        id: "kelid.light", name: ThemeName(en: "Light", fa: "روشن"), isDark: false, background: .color("#D1D3D9"),
        keys: ThemeKeys(
            normal: ThemeKeyState(fill: "#FFFFFF", text: "#000000", pressedFill: "#DCDCDC"),
            special: ThemeKeyState(fill: "#ADADAD", text: "#000000", pressedFill: "#8E8E93"),
            accent: ThemeKeyState(fill: "#007AFF", text: "#FFFFFF", pressedFill: "#409CFF"),
            cornerRadius: 5, borderWidth: 0, borderColor: "#00000000",
            shadow: ThemeShadow(color: "#000000", opacity: 0.35, radius: 0, offsetY: 1), hintText: "#8E8E93"
        ),
        toolbar: ThemeToolbar(background: "#D1D3D9", icon: "#000000", suggestionText: "#000000", divider: "#C7C7CC", chipFill: "#FFFFFF"),
        callout: ThemeCallout(fill: "#FFFFFF", text: "#000000"),
        panel: ThemePanel(background: "#F2F2F7", rowFill: "#FFFFFF", text: "#000000", secondaryText: "#8E8E93", accent: "#007AFF")
    )

    public static let fallbackDark = Theme(
        id: "kelid.dark", name: ThemeName(en: "Dark", fa: "تیره"), isDark: true, background: .color("#1C1C1E"),
        keys: ThemeKeys(
            normal: ThemeKeyState(fill: "#3A3A3C", text: "#FFFFFF", pressedFill: "#5A5A5E"),
            special: ThemeKeyState(fill: "#2C2C2E", text: "#FFFFFF", pressedFill: "#48484A"),
            accent: ThemeKeyState(fill: "#0A84FF", text: "#FFFFFF", pressedFill: "#409CFF"),
            cornerRadius: 5, borderWidth: 0, borderColor: "#00000000",
            shadow: ThemeShadow(color: "#000000", opacity: 0.35, radius: 0, offsetY: 1), hintText: "#9A9A9E"
        ),
        toolbar: ThemeToolbar(background: "#00000000", icon: "#EBEBF5", suggestionText: "#FFFFFF", divider: "#48484A", chipFill: "#3A3A3C"),
        callout: ThemeCallout(fill: "#6C6C70", text: "#FFFFFF"),
        panel: ThemePanel(background: "#1C1C1E", rowFill: "#2C2C2E", text: "#FFFFFF", secondaryText: "#8E8E93", accent: "#0A84FF")
    )
}

public struct ThemeName: Codable, Sendable, Equatable {
    public var en: String
    public var fa: String

    public init(en: String, fa: String) {
        self.en = en
        self.fa = fa
    }

    /// `Locale.current`-independent — callers pass the app's own current
    /// `LanguageID`/UI language rather than relying on system locale, same
    /// reasoning as every other fa/en string pair in this project.
    public func localized(fa: Bool) -> String {
        fa ? self.fa : en
    }
}

/// `background.type` (§6.8.1): color, gradient, a pre-baked image, or a
/// system material. Encoded/decoded as a `"type"`-discriminated object,
/// matching the JSON schema exactly rather than Swift's default
/// one-case-per-key enum encoding.
public enum ThemeBackground: Codable, Sendable, Equatable {
    case color(String)
    case gradient(colors: [String], angle: Double)
    /// `file` is a filename only (e.g. `"kelid.saffron.jpg"`), resolved
    /// against `ContainerPaths.themesDirectoryURL.appendingPathComponent("Images")`
    /// — never an absolute path, so a theme stays portable across devices.
    case image(file: String, blur: Double, dim: Double)
    /// `style` is a `UIBlurEffect.Style` case name (e.g. `"systemMaterial"`),
    /// kept as a plain string since `UIBlurEffect.Style` lives in UIKit.
    case material(style: String)
    /// The real Liquid Glass material (iOS 26+, `UIGlassEffect`/`glassEffect`)
    /// — an optional `#RRGGBB(AA)` tint, `nil` for the neutral/untinted look
    /// most themes want. Falls back to `.material(style: "systemMaterial")`'s
    /// rendering on iOS versions before 26 (`KeyStyle+Theme.swift`/
    /// `KeyboardRootView` decide that at the UIKit layer — this module stays
    /// UIKit-free per CLAUDE.md).
    case glass(tint: String?)

    private enum CodingKeys: String, CodingKey {
        case type, color, colors, angle, file, blur, dim, style, tint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "gradient":
            self = try .gradient(
                colors: c.decode([String].self, forKey: .colors),
                angle: c.decodeIfPresent(Double.self, forKey: .angle) ?? 0
            )
        case "image":
            self = try .image(
                file: c.decode(String.self, forKey: .file), blur: c.decodeIfPresent(Double.self, forKey: .blur) ?? 0,
                dim: c.decodeIfPresent(Double.self, forKey: .dim) ?? 0
            )
        case "material":
            self = try .material(style: c.decode(String.self, forKey: .style))
        case "glass":
            self = try .glass(tint: c.decodeIfPresent(String.self, forKey: .tint))
        default:
            self = try .color(c.decode(String.self, forKey: .color))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .color(hex):
            try c.encode("color", forKey: .type)
            try c.encode(hex, forKey: .color)
        case let .gradient(colors, angle):
            try c.encode("gradient", forKey: .type)
            try c.encode(colors, forKey: .colors)
            try c.encode(angle, forKey: .angle)
        case let .image(file, blur, dim):
            try c.encode("image", forKey: .type)
            try c.encode(file, forKey: .file)
            try c.encode(blur, forKey: .blur)
            try c.encode(dim, forKey: .dim)
        case let .material(style):
            try c.encode("material", forKey: .type)
            try c.encode(style, forKey: .style)
        case let .glass(tint):
            try c.encode("glass", forKey: .type)
            try c.encodeIfPresent(tint, forKey: .tint)
        }
    }
}

public struct ThemeKeyState: Codable, Sendable, Equatable {
    public var fill: String
    public var text: String
    public var pressedFill: String

    public init(fill: String, text: String, pressedFill: String) {
        self.fill = fill
        self.text = text
        self.pressedFill = pressedFill
    }
}

public struct ThemeShadow: Codable, Sendable, Equatable {
    public var color: String
    public var opacity: Double
    public var radius: Double
    public var offsetY: Double

    public init(color: String, opacity: Double, radius: Double, offsetY: Double) {
        self.color = color
        self.opacity = opacity
        self.radius = radius
        self.offsetY = offsetY
    }
}

public struct ThemeKeys: Codable, Sendable, Equatable {
    public var normal: ThemeKeyState
    public var special: ThemeKeyState
    public var accent: ThemeKeyState
    public var cornerRadius: Double
    public var borderWidth: Double
    public var borderColor: String
    public var shadow: ThemeShadow
    public var hintText: String

    public init(
        normal: ThemeKeyState, special: ThemeKeyState, accent: ThemeKeyState, cornerRadius: Double, borderWidth: Double,
        borderColor: String, shadow: ThemeShadow, hintText: String
    ) {
        self.normal = normal
        self.special = special
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.shadow = shadow
        self.hintText = hintText
    }
}

/// §6.8.1 also lists per-theme `persian`/`latin` font-family hints, but this
/// model deliberately omits them: `AppearanceSettings.persianFont`/`latinFont`
/// (§6.1.8, already a global user setting since Phase 1) is the single
/// source of truth for font *family*, so a theme can't silently override a
/// choice the user made elsewhere. `weight`/`scale` are genuine per-theme
/// flavor (e.g. the Glass themes' "bolder labels") with no other owner, so
/// they're kept.
public struct ThemeFonts: Codable, Sendable, Equatable {
    public var weight: String
    public var scale: Double

    public init(weight: String = "regular", scale: Double = 1.0) {
        self.weight = weight
        self.scale = scale
    }
}

public struct ThemeToolbar: Codable, Sendable, Equatable {
    public var background: String
    public var icon: String
    public var suggestionText: String
    public var divider: String
    public var chipFill: String

    public init(background: String, icon: String, suggestionText: String, divider: String, chipFill: String) {
        self.background = background
        self.icon = icon
        self.suggestionText = suggestionText
        self.divider = divider
        self.chipFill = chipFill
    }
}

public struct ThemeCallout: Codable, Sendable, Equatable {
    public var fill: String
    public var text: String

    public init(fill: String, text: String) {
        self.fill = fill
        self.text = text
    }
}

public struct ThemePanel: Codable, Sendable, Equatable {
    public var background: String
    public var rowFill: String
    public var text: String
    public var secondaryText: String
    public var accent: String

    public init(background: String, rowFill: String, text: String, secondaryText: String, accent: String) {
        self.background = background
        self.rowFill = rowFill
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
    }
}
