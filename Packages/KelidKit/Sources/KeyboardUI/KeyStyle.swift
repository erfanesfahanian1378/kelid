#if canImport(UIKit)
    import KelidSettings
    import UIKit

    /// Colors come from a struct — not read directly from asset catalogs by
    /// `KeyView` — specifically so real theming only has to produce a
    /// different `KeyStyle` (via `KeyStyle.make(from:themeStore:)`, in
    /// `KeyStyle+Theme.swift`), never touch `KeyView`/`ToolbarStripView`/etc.
    /// themselves. `.light`/`.dark` (task 3.15's original two hard-coded
    /// styles) are now just `Theme.fallbackLight`/`.fallbackDark` run
    /// through that same conversion — one source of truth for both the
    /// "no theme resolved yet" fallback and the real built-in themes.
    public struct KeyStyle: Sendable, Equatable {
        public var keyFill: UIColor
        public var specialKeyFill: UIColor
        public var pressedKeyFill: UIColor
        public var pressedSpecialKeyFill: UIColor
        public var accentKeyFill: UIColor
        public var pressedAccentKeyFill: UIColor
        public var labelColor: UIColor
        public var specialLabelColor: UIColor
        public var accentLabelColor: UIColor
        public var hintTextColor: UIColor
        public var keyboardBackground: UIColor
        public var background: KeyboardBackground
        public var cornerRadius: CGFloat
        public var borderWidth: CGFloat
        public var borderColor: UIColor
        public var shadowOpacity: Float
        public var shadowRadius: CGFloat
        public var shadowOffsetY: CGFloat
        public var labelFontWeight: UIFont.Weight
        public var specialLabelFontWeight: UIFont.Weight
        public var persianFontName: String?
        public var latinFontChoice: LatinFontChoice
        public var fontScale: CGFloat

        public var toolbarBackground: UIColor
        public var toolbarIcon: UIColor
        public var toolbarSuggestionText: UIColor
        public var toolbarDivider: UIColor
        public var toolbarChipFill: UIColor

        public var calloutFill: UIColor
        public var calloutText: UIColor

        public var panelBackground: UIColor
        public var panelRowFill: UIColor
        public var panelText: UIColor
        public var panelSecondaryText: UIColor
        public var panelAccent: UIColor

        public static let light = KeyStyle.make(from: .fallbackLight, themeStore: nil)
        public static let dark = KeyStyle.make(from: .fallbackDark, themeStore: nil)
    }

    /// The keyboard's own background (§6.8.1's `background.type`), separate
    /// from `keyboardBackground` (a plain solid color kept for surfaces —
    /// the toolbar's own tint fallback, `BottomLiftView`, etc. — that don't
    /// bother rendering a gradient/image/material of their own).
    public enum KeyboardBackground: Sendable, Equatable {
        case color(UIColor)
        case gradient(colors: [UIColor], angleDegrees: Double)
        /// Blur and dim are already baked into the file at save time
        /// (§6.8.1) — the keyboard just displays it.
        case image(url: URL)
        case material(UIBlurEffect.Style)
    }
#endif
