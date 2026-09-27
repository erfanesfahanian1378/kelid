#if canImport(UIKit)
    import SwiftUI
    import ThemeKit

    /// Task 11.2's "panels (a SwiftUI environment value `KelidTheme`)" —
    /// the same resolved `Theme` `KeyStyle.make(from:themeStore:)` converts
    /// for UIKit, converted to SwiftUI `Color` instead, for the panels that
    /// are hosted as SwiftUI (`ClipboardPanelView` and friends).
    public struct KelidTheme: Sendable, Equatable {
        public let panelBackground: Color
        public let panelRowFill: Color
        public let panelText: Color
        public let panelSecondaryText: Color
        public let panelAccent: Color
        public let isDark: Bool

        public init(theme: Theme) {
            func color(_ hex: String, fallback: Color) -> Color {
                guard let parsed = ThemeHexColor(hex: hex) else { return fallback }
                return Color(red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha)
            }
            panelBackground = color(theme.panel.background, fallback: theme.isDark ? .black : .white)
            panelRowFill = color(theme.panel.rowFill, fallback: theme.isDark ? Color(white: 0.15) : Color(white: 0.95))
            panelText = color(theme.panel.text, fallback: theme.isDark ? .white : .black)
            panelSecondaryText = color(theme.panel.secondaryText, fallback: .gray)
            panelAccent = color(theme.panel.accent, fallback: .blue)
            isDark = theme.isDark
        }

        /// The same fallback every unstyled panel used before Phase 11 —
        /// system-default coloring, not tied to any specific theme.
        public static let systemDefault = KelidTheme(theme: .fallbackLight)
    }

    private struct KelidThemeKey: EnvironmentKey {
        static let defaultValue = KelidTheme.systemDefault
    }

    public extension EnvironmentValues {
        var kelidTheme: KelidTheme {
            get { self[KelidThemeKey.self] }
            set { self[KelidThemeKey.self] = newValue }
        }
    }
#endif
