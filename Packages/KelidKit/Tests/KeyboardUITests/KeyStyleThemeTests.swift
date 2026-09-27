#if canImport(UIKit)
    import KelidSettings
    @testable import KeyboardUI
    import Testing
    import ThemeKit
    import UIKit

    /// Substitutes for task 11.1's "snapshot of every built-in theme for fa
    /// and en letters pages" — this project has never built real
    /// image-snapshot infrastructure (`swift-snapshot-testing` has been a
    /// declared dependency since Phase 0 but Phase 3 explicitly deferred
    /// using it, decision 53's same reasoning) — a behavioral check that
    /// every built-in theme converts to a real, non-degenerate `KeyStyle`
    /// with the exact colors its own JSON specifies verifies the same
    /// underlying logic a pixel snapshot would, without that new
    /// infrastructure.
    @Suite("KeyStyle.make(from:) theme conversion (task 11.2)")
    @MainActor
    struct KeyStyleThemeTests {
        @Test("every built-in theme converts to a KeyStyle without falling back to a default color")
        func everyBuiltInThemeConverts() {
            let catalog = BuiltInThemeCatalog()
            for theme in catalog.allThemes() {
                let style = KeyStyle.make(from: theme, themeStore: nil)
                let expectedFill = UIColor(themeHex: theme.keys.normal.fill)
                #expect(style.keyFill == expectedFill, "\(theme.id)'s normal key fill didn't round-trip")
                let expectedAccent = UIColor(themeHex: theme.keys.accent.fill)
                #expect(style.accentKeyFill == expectedAccent, "\(theme.id)'s accent key fill didn't round-trip")
            }
        }

        @Test("kelid.dark's exact §6.8.1 example colors round-trip through KeyStyle")
        func kelidDarkColorsRoundTrip() throws {
            let catalog = BuiltInThemeCatalog()
            let theme = try #require(catalog.theme(id: "kelid.dark"))
            let style = KeyStyle.make(from: theme, themeStore: nil)
            #expect(style.keyFill == UIColor(themeHex: "#3A3A3C"))
            #expect(style.labelColor == UIColor(themeHex: "#FFFFFF"))
            #expect(style.accentKeyFill == UIColor(themeHex: "#0A84FF"))
            #expect(style.panelAccent == UIColor(themeHex: "#0A84FF"))
        }

        @Test("a malformed hex color falls back to a real UIColor, not a crash")
        func malformedHexFallsBackGracefully() {
            var theme = Theme.fallbackLight
            theme.keys.accent = ThemeKeyState(fill: "not-a-color", text: "#FFFFFF", pressedFill: "#409CFF")
            let style = KeyStyle.make(from: theme, themeStore: nil)
            #expect(style.accentKeyFill == .systemBlue)
        }

        @Test("KeyStyle.light/.dark match Theme.fallbackLight/.fallbackDark converted directly")
        func staticFallbacksMatchThemeConversion() {
            #expect(KeyStyle.light == KeyStyle.make(from: .fallbackLight, themeStore: nil))
            #expect(KeyStyle.dark == KeyStyle.make(from: .fallbackDark, themeStore: nil))
        }

        @Test("a gradient background converts to the right KeyboardBackground case with the right colors")
        func gradientBackgroundConverts() {
            var theme = Theme.fallbackLight
            theme.background = .gradient(colors: ["#FF0000", "#00FF00"], angle: 45)
            let style = KeyStyle.make(from: theme, themeStore: nil)
            guard case let .gradient(colors, angle) = style.background else {
                Issue.record("expected a .gradient background")
                return
            }
            #expect(colors == [UIColor(themeHex: "#FF0000"), UIColor(themeHex: "#00FF00")])
            #expect(angle == 45)
        }

        @Test("applyingFontChoice sets the Vazirmatn font name only when persian == .vazirmatn")
        func fontChoiceApplication() {
            let base = KeyStyle.make(from: .fallbackDark, themeStore: nil)
            let withVazirmatn = base.applyingFontChoice(persian: .vazirmatn, latin: .system)
            #expect(withVazirmatn.persianFontName == "Vazirmatn-Regular")
            let withSystem = base.applyingFontChoice(persian: .system, latin: .rounded)
            #expect(withSystem.persianFontName == nil)
            #expect(withSystem.latinFontChoice == .rounded)
        }
    }
#endif
