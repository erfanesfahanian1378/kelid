/// §6.2.5's numeric pad row 4 is conditional (a decimal point for
/// `.decimalPad`, a globe key when needed) so — like `BottomRowBuilder` for
/// the other pages — it's built in code rather than stored in `numpad.json`,
/// which only holds the fixed 1-9 grid (rows 1-3). Not a task PLAN.md names
/// explicitly; introduced to fill in §6.2.5's own conditional-row-4
/// description without hard-coding one variant into the JSON file.
public enum NumpadBuilder {
    public static func row4(showDecimalPoint: Bool, showGlobe: Bool) -> [KeyDefinition] {
        let leading = if showDecimalPoint {
            KeyDefinition(out: ".")
        } else if showGlobe {
            KeyDefinition(label: "🌐", action: .globe)
        } else {
            KeyDefinition(spacer: 1.0)
        }
        return [leading, KeyDefinition(out: "0"), KeyDefinition(label: "⌫", action: .backspace)]
    }
}
