#if canImport(UIKit)
    import KelidSettings
    import ThemeKit
    import UIKit

    extension UIColor {
        /// Parses `#RRGGBB`/`#RRGGBBAA` (§6.8.1's theme color format) via
        /// `ThemeHexColor` — `nil` (not black) for a malformed string, so a
        /// broken custom theme degrades per-field rather than turning solid
        /// black. Callers pick their own fallback.
        convenience init?(themeHex hex: String) {
            guard let parsed = ThemeHexColor(hex: hex) else { return nil }
            self.init(red: parsed.red, green: parsed.green, blue: parsed.blue, alpha: parsed.alpha)
        }
    }

    public extension KeyStyle {
        /// Converts a `ThemeKit.Theme` (plain hex strings, UIKit-free) into a
        /// real `KeyStyle` (`UIColor`s, `UIBlurEffect.Style`, resolved font
        /// names) — the one place theme JSON meets UIKit. `themeStore` is
        /// only needed to resolve an `.image` background's filename into a
        /// real file URL; `nil` is fine for themes that don't use one (both
        /// fallback themes, most built-ins).
        static func make(from theme: Theme, themeStore: ThemeStore?) -> KeyStyle {
            func color(_ hex: String, fallback: UIColor) -> UIColor {
                UIColor(themeHex: hex) ?? fallback
            }

            let background: KeyboardBackground = switch theme.background {
            case let .color(hex):
                .color(color(hex, fallback: theme.isDark ? .black : .white))
            case let .gradient(hexes, angle):
                .gradient(colors: hexes.map { color($0, fallback: .clear) }, angleDegrees: angle)
            case let .image(file, _, _):
                themeStore.map { .image(url: $0.imageURL(filename: file)) } ?? .color(theme.isDark ? .black : .white)
            case let .material(style):
                .material(UIBlurEffect.Style(themeName: style))
            case let .glass(tint):
                .glass(tint: tint.flatMap { UIColor(themeHex: $0) })
            }

            let baseBackgroundColor: UIColor = if case let .color(hex) = theme.background {
                color(hex, fallback: theme.isDark ? .black : .white)
            } else {
                theme.isDark ? .black : .white
            }

            return KeyStyle(
                keyFill: color(theme.keys.normal.fill, fallback: .white),
                specialKeyFill: color(theme.keys.special.fill, fallback: .lightGray),
                pressedKeyFill: color(theme.keys.normal.pressedFill, fallback: .lightGray),
                pressedSpecialKeyFill: color(theme.keys.special.pressedFill, fallback: .darkGray),
                accentKeyFill: color(theme.keys.accent.fill, fallback: .systemBlue),
                pressedAccentKeyFill: color(theme.keys.accent.pressedFill, fallback: .systemBlue),
                labelColor: color(theme.keys.normal.text, fallback: theme.isDark ? .white : .black),
                specialLabelColor: color(theme.keys.special.text, fallback: theme.isDark ? .white : .black),
                accentLabelColor: color(theme.keys.accent.text, fallback: .white),
                hintTextColor: color(theme.keys.hintText, fallback: .gray),
                keyboardBackground: baseBackgroundColor,
                background: background,
                cornerRadius: theme.keys.cornerRadius,
                borderWidth: theme.keys.borderWidth,
                borderColor: color(theme.keys.borderColor, fallback: .clear),
                shadowOpacity: Float(theme.keys.shadow.opacity),
                shadowRadius: theme.keys.shadow.radius,
                shadowOffsetY: theme.keys.shadow.offsetY,
                labelFontWeight: UIFont.Weight(themeWeight: theme.fonts.weight),
                specialLabelFontWeight: UIFont.Weight(themeWeight: theme.fonts.weight),
                persianFontName: nil,
                latinFontChoice: .system,
                fontScale: CGFloat(theme.fonts.scale),
                toolbarBackground: color(theme.toolbar.background, fallback: baseBackgroundColor),
                toolbarIcon: color(theme.toolbar.icon, fallback: theme.isDark ? .white : .black),
                toolbarSuggestionText: color(theme.toolbar.suggestionText, fallback: theme.isDark ? .white : .black),
                toolbarDivider: color(theme.toolbar.divider, fallback: .separator),
                toolbarChipFill: color(theme.toolbar.chipFill, fallback: .systemGray5),
                calloutFill: color(theme.callout.fill, fallback: .darkGray),
                calloutText: color(theme.callout.text, fallback: .white),
                panelBackground: color(theme.panel.background, fallback: baseBackgroundColor),
                panelRowFill: color(theme.panel.rowFill, fallback: .secondarySystemBackground),
                panelText: color(theme.panel.text, fallback: theme.isDark ? .white : .black),
                panelSecondaryText: color(theme.panel.secondaryText, fallback: .secondaryLabel),
                panelAccent: color(theme.panel.accent, fallback: .systemBlue)
            )
        }

        /// Applies the user's global font-family choice (§6.1.8's
        /// `AppearanceSettings.persianFont`/`latinFont`, independent of the
        /// theme itself — see `ThemeFonts`'s own doc comment) on top of an
        /// already-`make(from:themeStore:)`-built style.
        func applyingFontChoice(persian: PersianFontChoice, latin: LatinFontChoice) -> KeyStyle {
            var copy = self
            copy.persianFontName = persian == .vazirmatn ? "Vazirmatn-Regular" : nil
            copy.latinFontChoice = latin
            return copy
        }
    }

    extension UIBlurEffect.Style {
        /// §6.8.1: `background.type == "material"`'s `style` is a plain
        /// string naming a `UIBlurEffect.Style` case. Unrecognized names
        /// (a theme authored against a future OS's new style name) fall
        /// back to `.systemMaterial` rather than failing to load the theme.
        init(themeName: String) {
            self = switch themeName {
            case "systemMaterialLight": .systemMaterialLight
            case "systemMaterialDark": .systemMaterialDark
            case "systemThinMaterial": .systemThinMaterial
            case "systemThinMaterialLight": .systemThinMaterialLight
            case "systemThinMaterialDark": .systemThinMaterialDark
            case "systemThickMaterial": .systemThickMaterial
            case "systemChromeMaterial": .systemChromeMaterial
            default: .systemMaterial
            }
        }
    }

    extension UIFont.Weight {
        init(themeWeight: String) {
            self = switch themeWeight {
            case "medium": .medium
            case "semibold": .semibold
            case "bold": .bold
            case "light": .light
            default: .regular
            }
        }
    }
#endif
