import SwiftUI
import ThemeKit
import UIKit

/// `ColorPicker` needs a `Binding<Color>`, but every color field in `Theme`
/// is a plain `#RRGGBB(AA)` string (`ThemeKit` stays UIKit/SwiftUI-free) —
/// this bridges the two, going through `UIColor` to read back the exact
/// components `ColorPicker`'s own system color picker produced.
enum ThemeColorBinding {
    static func binding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { color(from: hex.wrappedValue) },
            set: { hex.wrappedValue = hexString(from: $0) }
        )
    }

    static func color(from hex: String) -> Color {
        guard let parsed = ThemeHexColor(hex: hex) else { return .gray }
        return Color(red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha)
    }

    static func hexString(from color: Color) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func component(_ value: CGFloat) -> String {
            String(format: "%02X", max(0, min(255, Int((value * 255).rounded()))))
        }
        let base = "#\(component(red))\(component(green))\(component(blue))"
        return alpha < 0.999 ? base + component(alpha) : base
    }
}
