import KelidSettings

/// §6.1.2/§6.2.4: `showNumberRow` prepends a digits row to the letters
/// page. Storing `rowHeight` rather than total height (§6.3.1) means this
/// adds exactly one row.
public enum NumberRowBuilder {
    private static let persianDigits = ["۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹", "۰"]
    private static let latinDigits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    public static func row(mode: PersianDigitsMode) -> [KeyDefinition] {
        (mode == .latin ? latinDigits : persianDigits).map { KeyDefinition(out: $0) }
    }

    public static func prepending(_ page: PageDefinition, mode: PersianDigitsMode, showNumberRow: Bool) -> PageDefinition {
        guard showNumberRow else { return page }
        return PageDefinition(rows: [row(mode: mode)] + page.rows)
    }
}
