import Foundation

/// §6.6.2's `canonical(_:)` and §6.6.4's `matchKey(_:)`/`searchKey(_:)` —
/// used for clipboard/snippet/emoji search (Phase 5+), the prediction
/// engine's trie lookups (Phase 7+), and the keyboard's own suggestion
/// output/hashing. **Never** applied to silently rewrite what a user
/// actually typed (§6.6.2's own rule) — only to the keyboard's own output,
/// and to keys/hashes derived from stored text.
///
/// The Python data pipeline (Phase 6) must apply the exact same rules;
/// `Tests/PersianTextTests/vectors.json` is the shared vector file both
/// Swift and Python tests read.
public enum PersianNormalization {
    private static let zwnjScalar: Unicode.Scalar = "\u{200C}"
    private static let zwjScalar: Unicode.Scalar = "\u{200D}"

    /// Whether `text` contains a ZWNJ anywhere — at the **Unicode scalar**
    /// level, not `String.contains(Character)`/grapheme level. ZWNJ fuses
    /// with the preceding letter into a single `Character` (e.g. "می‌خواهم"
    /// has no standalone ZWNJ *grapheme cluster* to find), so
    /// `text.contains("\u{200C}")` silently returns `false` even when a
    /// ZWNJ is present — the same landmine `WordCharacters`/`InputProcessor`
    /// already work around by operating on `.unicodeScalars` directly.
    public static func containsZWNJ(_ text: String) -> Bool {
        text.unicodeScalars.contains(zwnjScalar)
    }

    private static let arabicIndicToPersianDigit: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{0660}": "\u{06F0}", "\u{0661}": "\u{06F1}", "\u{0662}": "\u{06F2}", "\u{0663}": "\u{06F3}",
        "\u{0664}": "\u{06F4}", "\u{0665}": "\u{06F5}", "\u{0666}": "\u{06F6}", "\u{0667}": "\u{06F7}",
        "\u{0668}": "\u{06F8}", "\u{0669}": "\u{06F9}",
    ]

    private static let persianDigitToASCII: [Character: Character] = [
        "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
        "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
    ]

    // MARK: - canonical (§6.6.2)

    /// Used for storage, dedupe and the keyboard's own suggestion output.
    public static func canonical(_ text: String) -> String {
        var mapped: [Unicode.Scalar] = []
        mapped.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{064A}", "\u{0649}": // ي, ى → ی
                mapped.append("\u{06CC}")
            case "\u{0643}": // ك → ک
                mapped.append("\u{06A9}")
            case "\u{0640}": // tatweel — removed
                continue
            default:
                if let digit = arabicIndicToPersianDigit[scalar] {
                    mapped.append(digit)
                } else if isNormalizableSpace(scalar) {
                    mapped.append(" ")
                } else {
                    mapped.append(scalar)
                }
            }
        }
        let spacesNormalized = String(String.UnicodeScalarView(mapped))
        let zwnjCollapsed = collapseZWNJEdgeCases(spacesNormalized)
        return removeZWJBetweenPersianLetters(zwnjCollapsed)
    }

    /// "Repeated ZWNJ, ZWNJ at word start or end, ZWNJ next to a space →
    /// removed." Operates on scalars (not `Character`s): a kept ZWNJ fuses
    /// with the preceding letter into one grapheme cluster, which would
    /// make "is this ZWNJ at a word boundary" awkward to ask post-fusion.
    private static func collapseZWNJEdgeCases(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var kept: [Unicode.Scalar] = []
        kept.reserveCapacity(scalars.count)
        for (index, scalar) in scalars.enumerated() {
            guard scalar == zwnjScalar else {
                kept.append(scalar)
                continue
            }
            let previousKept = kept.last
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil
            let atStart = previousKept == nil
            let atEnd = next == nil
            let adjacentToSpace = previousKept == " " || next == " "
            let adjacentToZWNJ = previousKept == zwnjScalar || next == zwnjScalar
            guard !atStart, !atEnd, !adjacentToSpace, !adjacentToZWNJ else {
                continue // drop this ZWNJ
            }
            kept.append(scalar)
        }
        return String(String.UnicodeScalarView(kept))
    }

    private static func removeZWJBetweenPersianLetters(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var kept: [Unicode.Scalar] = []
        kept.reserveCapacity(scalars.count)
        for (index, scalar) in scalars.enumerated() {
            guard scalar == zwjScalar else {
                kept.append(scalar)
                continue
            }
            let previous: Unicode.Scalar? = index > 0 ? scalars[index - 1] : nil
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil
            if let previous, let next, isPersianLetter(previous), isPersianLetter(next) {
                continue // drop this ZWJ
            }
            kept.append(scalar)
        }
        return String(String.UnicodeScalarView(kept))
    }

    private static func isPersianLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .otherLetter && (0x0600 ... 0x06FF).contains(scalar.value)
    }

    private static func isNormalizableSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x00A0 || scalar.properties.generalCategory == .spaceSeparator
    }

    // MARK: - matchKey (§6.6.4)

    /// Lossy on purpose — for trie lookups/matching, never for display.
    public static func matchKey(_ text: String) -> String {
        var result = canonical(text)

        // Diacritics (U+064B–U+065F, U+0670), ZWNJ, ZWJ — removed.
        result = String(String.UnicodeScalarView(result.unicodeScalars.filter { scalar in
            let isDiacritic = (0x064B ... 0x065F).contains(scalar.value) || scalar.value == 0x0670
            return !isDiacritic && scalar != zwnjScalar && scalar != zwjScalar
        }))

        // آ أ إ ٱ → ا · ؤ → و · ئ → ی · ۀ / ة → ه
        result = String(result.map { character -> Character in
            switch character {
            case "آ", "أ", "إ", "ٱ": "ا"
            case "ؤ": "و"
            case "ئ": "ی"
            case "ۀ", "ة": "ه"
            default: character
            }
        })

        // Latin lowercase; ' → '.
        result = result.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")

        // All digits → ASCII digits (canonical already normalized
        // Arabic-Indic to Persian, so only the Persian→ASCII map is needed).
        result = String(result.map { persianDigitToASCII[$0] ?? $0 })

        return result
    }

    // MARK: - searchKey (§6.6.4)

    /// `matchKey` + collapsed whitespace + (Latin) accent removal. Used for
    /// clipboard, snippet and emoji search.
    public static func searchKey(_ text: String) -> String {
        let key = matchKey(text)
        let collapsed = key
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.folding(options: .diacriticInsensitive, locale: nil)
    }
}
