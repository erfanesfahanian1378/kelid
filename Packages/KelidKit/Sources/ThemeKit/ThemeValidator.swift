import Foundation

/// §6.8.1: "The validator checks text/fill contrast ≥ 3:1 (a warning, not
/// an error)" — a custom theme with poor contrast still loads and applies;
/// this only surfaces something the app's theme editor (task 11.8) can show
/// the user, e.g. next to a "Contrast may be hard to read" hint.
public enum ThemeValidator {
    public struct Warning: Sendable, Equatable {
        public let field: String
        public let message: String
    }

    private static let minContrastRatio = 3.0

    /// Malformed hex strings are reported as warnings too (not thrown) —
    /// same "surface it, don't refuse to load the theme" reasoning.
    public static func validate(_ theme: Theme) -> [Warning] {
        var warnings: [Warning] = []

        func checkContrast(_ field: String, fill: String, text: String) {
            guard let fillColor = ThemeHexColor(hex: fill) else {
                warnings.append(Warning(field: field, message: "'\(fill)' is not a valid #RRGGBB(AA) color"))
                return
            }
            guard let textColor = ThemeHexColor(hex: text) else {
                warnings.append(Warning(field: field, message: "'\(text)' is not a valid #RRGGBB(AA) color"))
                return
            }
            let ratio = ThemeHexColor.contrastRatio(fillColor, textColor)
            if ratio < minContrastRatio {
                warnings.append(Warning(
                    field: field,
                    message: "contrast ratio \(String(format: "%.2f", ratio)):1 is below the 3:1 minimum"
                ))
            }
        }

        checkContrast("keys.normal", fill: theme.keys.normal.fill, text: theme.keys.normal.text)
        checkContrast("keys.special", fill: theme.keys.special.fill, text: theme.keys.special.text)
        checkContrast("keys.accent", fill: theme.keys.accent.fill, text: theme.keys.accent.text)
        checkContrast("toolbar", fill: theme.toolbar.background, text: theme.toolbar.suggestionText)
        checkContrast("callout", fill: theme.callout.fill, text: theme.callout.text)
        checkContrast("panel", fill: theme.panel.background, text: theme.panel.text)

        if theme.id.isEmpty {
            warnings.append(Warning(field: "id", message: "theme id must not be empty"))
        }
        if theme.schemaVersion != 1 {
            warnings.append(Warning(field: "schemaVersion", message: "unrecognized schema version \(theme.schemaVersion), expected 1"))
        }

        return warnings
    }
}
