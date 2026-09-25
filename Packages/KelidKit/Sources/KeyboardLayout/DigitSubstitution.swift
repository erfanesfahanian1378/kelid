import KelidSettings

/// §6.2.4: "when `persianDigits == .latin`, Persian pages and the number
/// row use 0–9, and the Persian digits become the alternates."
public enum DigitSubstitution {
    static let persianToLatin: [Character: Character] = [
        "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
        "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
    ]

    /// Applies the swap to a single page. A no-op when `mode == .persian`.
    public static func apply(to page: PageDefinition, mode: PersianDigitsMode) -> PageDefinition {
        guard mode == .latin else { return page }
        return PageDefinition(rows: page.rows.map { $0.map(swapIfDigit) })
    }

    private static func swapIfDigit(_ key: KeyDefinition) -> KeyDefinition {
        guard let out = key.out, out.count == 1, let char = out.first, let latin = persianToLatin[char] else {
            return key
        }
        var updated = key
        updated.out = String(latin)
        if key.label == out {
            updated.label = String(latin)
        }
        updated.alternates = [String(char)] + (key.alternates ?? [])
        return updated
    }
}
