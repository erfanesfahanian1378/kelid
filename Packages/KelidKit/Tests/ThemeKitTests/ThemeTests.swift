import Foundation
import Testing
@testable import ThemeKit

@Suite("Theme decoding (task 11.1)")
struct ThemeTests {
    private static let sampleJSON = """
    {
      "schemaVersion": 1, "id": "kelid.dark", "name": { "en": "Dark", "fa": "تیره" }, "isDark": true,
      "background": { "type": "color", "color": "#1C1C1E" },
      "keys": {
        "normal":  { "fill": "#3A3A3C", "text": "#FFFFFF", "pressedFill": "#5A5A5E" },
        "special": { "fill": "#2C2C2E", "text": "#FFFFFF", "pressedFill": "#48484A" },
        "accent":  { "fill": "#0A84FF", "text": "#FFFFFF", "pressedFill": "#409CFF" },
        "cornerRadius": 5.0, "borderWidth": 0.0, "borderColor": "#00000000",
        "shadow": { "color": "#000000", "opacity": 0.35, "radius": 0.0, "offsetY": 1.0 },
        "hintText": "#9A9A9E"
      },
      "fonts": { "weight": "regular", "scale": 1.0 },
      "toolbar": { "background": "#00000000", "icon": "#EBEBF5", "suggestionText": "#FFFFFF",
                   "divider": "#48484A", "chipFill": "#3A3A3C" },
      "callout": { "fill": "#6C6C70", "text": "#FFFFFF" },
      "panel": { "background": "#1C1C1E", "rowFill": "#2C2C2E", "text": "#FFFFFF",
                 "secondaryText": "#8E8E93", "accent": "#0A84FF" }
    }
    """

    @Test("the §6.8.1 example JSON decodes into the expected model")
    func decodesExampleJSON() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
        #expect(theme.id == "kelid.dark")
        #expect(theme.isDark)
        #expect(theme.background == .color("#1C1C1E"))
        #expect(theme.keys.normal.fill == "#3A3A3C")
        #expect(theme.toolbar.icon == "#EBEBF5")
        #expect(theme.panel.accent == "#0A84FF")
    }

    @Test("background variants (gradient/image/material) round-trip through encode/decode")
    func backgroundVariantsRoundTrip() throws {
        let variants: [ThemeBackground] = [
            .color("#FFFFFF"),
            .gradient(colors: ["#FF0000", "#0000FF"], angle: 45),
            .image(file: "sunset.jpg", blur: 12, dim: 0.3),
            .material(style: "systemMaterialDark"),
        ]
        for background in variants {
            let theme = Theme.fallbackLight
            var mutated = theme
            mutated.background = background
            let data = try JSONEncoder().encode(mutated)
            let decoded = try JSONDecoder().decode(Theme.self, from: data)
            #expect(decoded.background == background)
        }
    }

    @Test("an exported theme imports back identical (export/import round trip, task 11.8)")
    func exportImportRoundTrip() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(Theme.fallbackDark)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded == Theme.fallbackDark)
    }
}

@Suite("ThemeValidator contrast checks (task 11.1)")
struct ThemeValidatorTests {
    @Test("both fallback themes pass contrast validation with no warnings")
    func fallbackThemesPassValidation() {
        #expect(ThemeValidator.validate(.fallbackLight).isEmpty)
        #expect(ThemeValidator.validate(.fallbackDark).isEmpty)
    }

    @Test("low-contrast key colors are reported as a warning, not thrown")
    func lowContrastIsWarned() {
        var theme = Theme.fallbackLight
        theme.keys.normal = ThemeKeyState(fill: "#FFFFFF", text: "#FEFEFE", pressedFill: "#DDDDDD")
        let warnings = ThemeValidator.validate(theme)
        #expect(warnings.contains { $0.field == "keys.normal" })
    }

    @Test("a malformed hex color is reported as a warning")
    func malformedHexIsWarned() {
        var theme = Theme.fallbackLight
        theme.keys.accent = ThemeKeyState(fill: "not-a-color", text: "#FFFFFF", pressedFill: "#409CFF")
        let warnings = ThemeValidator.validate(theme)
        #expect(warnings.contains { $0.field == "keys.accent" })
    }
}

@Suite("BuiltInThemeCatalog (task 11.1)")
struct BuiltInThemeCatalogTests {
    @Test("all ≥12 bundled built-in themes decode and pass validation")
    func allBuiltInsDecodeAndValidate() {
        let catalog = BuiltInThemeCatalog()
        let themes = catalog.allThemes()
        #expect(themes.count >= 12)
        for theme in themes {
            let warnings = ThemeValidator.validate(theme)
            #expect(warnings.isEmpty, "\(theme.id) has validator warnings: \(warnings)")
        }
    }

    @Test("kelid.light and kelid.dark are both present, matching their isDark flag")
    func lightAndDarkPresent() {
        let catalog = BuiltInThemeCatalog()
        #expect(catalog.theme(id: "kelid.light")?.isDark == false)
        #expect(catalog.theme(id: "kelid.dark")?.isDark == true)
    }

    @Test("theme ids are unique")
    func idsAreUnique() {
        let ids = BuiltInThemeCatalog().allThemes().map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
