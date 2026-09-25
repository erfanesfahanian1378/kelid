import Foundation

/// ASCII rendering of a computed layout — rows of labels, with a width
/// annotation for anything wider than one unit (task 2.9). Used in test
/// output (and pasted into `PROGRESS.md`) so a human — or the AI itself —
/// can "see" a layout without a simulator.
public enum LayoutDebugRenderer {
    public static func render(_ layout: ComputedLayout) -> String {
        layout.rows.map { row in
            row.keys.map(label).joined(separator: " ")
        }.joined(separator: "\n")
    }

    private static func label(_ key: ComputedKey) -> String {
        let text = key.definition.label ?? key.definition.out ?? "[\(key.definition.action.rawValue)]"
        guard key.definition.width != 1.0 else { return text }
        // Shortest round-trippable form: 1.5 -> "1.5", 2.0 -> "2" (not
        // "1.50"/"2.0") — `%g`-style trimming that `%f` doesn't give directly.
        let width = key.definition.width.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", key.definition.width)
            : "\(key.definition.width)"
        return "\(text)(\(width))"
    }
}
