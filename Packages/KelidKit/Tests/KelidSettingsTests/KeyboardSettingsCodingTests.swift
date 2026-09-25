import Foundation
import KelidCore
@testable import KelidSettings
import Testing

@Suite("KeyboardSettings decoding")
struct KeyboardSettingsCodingTests {
    @Test("missing keys fall back to defaults at every nesting level")
    func missingKeysFallBackToDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: json)
        let defaults = KeyboardSettings()

        #expect(settings.schemaVersion == defaults.schemaVersion)
        #expect(settings.general.persianLayout == .standard)
        #expect(settings.general.enabledLanguages == [.fa, .en])
        #expect(settings.size.portrait.rowHeight == SizeProfile.portraitDefault.rowHeight)
        #expect(settings.size.landscape.rowHeight == SizeProfile.landscapeDefault.rowHeight)
        #expect(settings.prediction.fa.personalWeight == 0.6)
        #expect(settings.prediction.en.personalWeight == 0.5)
        #expect(settings.clipboard.maxItems == 200)
    }

    @Test("an unknown enum raw value falls back to the default instead of throwing")
    func unknownEnumValueFallsBackToDefault() throws {
        let json = """
        { "general": { "persianLayout": "not-a-real-layout" } }
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: json)
        #expect(settings.general.persianLayout == .standard)
    }

    @Test("extra, unrecognized keys are ignored rather than causing a decode failure")
    func extraKeysAreIgnored() throws {
        let json = """
        { "general": { "keyPopups": false, "aFieldFromTheFuture": 42 }, "somethingElseEntirely": "x" }
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: json)
        #expect(settings.general.keyPopups == false)
    }

    @Test("round trip: encode then decode reproduces the same value")
    func roundTrip() throws {
        var original = KeyboardSettings()
        original.general.showNumberRow = true
        original.size.portrait.rowHeight = 60
        original.prediction.en.source = .personalOnly
        original.clipboard.ignorePatterns = ["\\d{4}-\\d{4}-\\d{4}-\\d{4}"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: data)
        #expect(decoded == original)
    }
}
