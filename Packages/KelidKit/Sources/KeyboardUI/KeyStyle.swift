#if canImport(UIKit)
    import UIKit

    /// Two hard-coded styles (light/dark) matching iOS closely (task 3.15).
    /// Colors come from a struct now — not read directly from asset catalogs by
    /// `KeyView` — specifically so real theming (Phase 11) only has to produce
    /// a different `KeyStyle`, never touch `KeyView` itself.
    public struct KeyStyle: Sendable, Equatable {
        public var keyFill: UIColor
        public var specialKeyFill: UIColor
        public var pressedKeyFill: UIColor
        public var pressedSpecialKeyFill: UIColor
        public var labelColor: UIColor
        public var specialLabelColor: UIColor
        public var keyboardBackground: UIColor
        public var cornerRadius: CGFloat
        public var shadowOpacity: Float
        public var shadowRadius: CGFloat
        public var shadowOffsetY: CGFloat
        public var labelFontWeight: UIFont.Weight
        public var specialLabelFontWeight: UIFont.Weight

        public static let light = KeyStyle(
            keyFill: .white,
            specialKeyFill: UIColor(white: 0.68, alpha: 1),
            pressedKeyFill: UIColor(white: 0.86, alpha: 1),
            pressedSpecialKeyFill: UIColor(white: 0.56, alpha: 1),
            labelColor: .black,
            specialLabelColor: .black,
            keyboardBackground: UIColor(white: 0.82, alpha: 1),
            cornerRadius: 5,
            shadowOpacity: 0.35,
            shadowRadius: 0,
            shadowOffsetY: 1,
            labelFontWeight: .regular,
            specialLabelFontWeight: .regular
        )

        public static let dark = KeyStyle(
            keyFill: UIColor(white: 0.34, alpha: 1),
            specialKeyFill: UIColor(white: 0.19, alpha: 1),
            pressedKeyFill: UIColor(white: 0.46, alpha: 1),
            pressedSpecialKeyFill: UIColor(white: 0.10, alpha: 1),
            labelColor: .white,
            specialLabelColor: .white,
            keyboardBackground: .black,
            cornerRadius: 5,
            shadowOpacity: 0.6,
            shadowRadius: 0,
            shadowOffsetY: 1,
            labelFontWeight: .regular,
            specialLabelFontWeight: .regular
        )

        /// §3.15: resolved from `keyboardAppearance` (field trait) or the
        /// system trait — never both; the field trait wins when the host sets
        /// one explicitly.
        public static func resolve(traitAppearance: UIKeyboardAppearance, fieldAppearance: UIKeyboardAppearance?) -> KeyStyle {
            switch fieldAppearance ?? traitAppearance {
            case .dark: .dark
            default: .light
            }
        }
    }
#endif
