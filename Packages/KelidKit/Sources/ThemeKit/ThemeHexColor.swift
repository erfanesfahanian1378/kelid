import Foundation

/// Parses `#RRGGBB`/`#RRGGBBAA` theme color strings into plain component
/// values — no `UIColor`/`Color` here, so this stays usable from the
/// UIKit-free `ThemeValidator` and from tests on macOS. `KeyboardUI`/App
/// code converts these same hex strings to `UIColor`/`Color` themselves.
public struct ThemeHexColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// `nil` for a malformed string (missing `#`, wrong length, non-hex
    /// characters) rather than a crash or a silent black fallback — callers
    /// (the validator, tests) decide what "malformed" should mean for them.
    public init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") {
            s.removeFirst()
        }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        } else {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }
    }

    /// WCAG relative luminance (sRGB), used by `ThemeValidator`'s contrast
    /// check (§6.8.1: "validator checks text/fill contrast ≥ 3:1").
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colors, always ≥ 1.
    public static func contrastRatio(_ a: ThemeHexColor, _ b: ThemeHexColor) -> Double {
        let l1 = a.relativeLuminance
        let l2 = b.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
