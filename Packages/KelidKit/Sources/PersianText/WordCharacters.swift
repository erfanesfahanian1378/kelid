import Foundation

/// §6.6.3: word characters and direction — the minimal slice of Persian
/// text processing `InputProcessor` (Phase 3) needs for ZWNJ rules and
/// word-boundary backspace, ahead of the full `PersianText` module the plan
/// otherwise assigns to Phase 7 (§6.6 proper: canonicalization, match/search
/// keys). Kept intentionally small — do not grow this file into full §6.6
/// scope; that belongs in its own Phase 7 files.
public enum WordCharacters {
    private static let zwnjScalar: Unicode.Scalar = "\u{200C}"
    private static let zwjScalar: Unicode.Scalar = "\u{200D}"

    /// §6.6.3: "Unicode letters (L*), marks (M*), decimal digits (Nd), ZWNJ,
    /// ZWJ. Apostrophes count only between letters (English contractions)."
    /// The apostrophe-between-letters case needs neighbors, so it's handled
    /// by `isWordCharacter(at:in:)` below, not here.
    ///
    /// Checked scalar-by-scalar, not as a whole `Character`: ZWNJ commonly
    /// *fuses* with the preceding letter into a single extended grapheme
    /// cluster (e.g. "ی" + ZWNJ in "می‌خوام" is one `Character`), so a
    /// whole-cluster check against a bare ZWNJ constant would miss it.
    public static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            if scalar == zwnjScalar || scalar == zwjScalar {
                return true
            }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber:
                return true
            default:
                return false
            }
        }
    }

    /// Same as `isWordCharacter(_:)`, but also treats `'`/`’` as a word
    /// character when both neighbors (in `text`, at `index`) are letters —
    /// English contractions ("don't") stay one word.
    public static func isWordCharacter(at index: String.Index, in text: String) -> Bool {
        let character = text[index]
        if character == "'" || character == "\u{2019}" {
            guard index > text.startIndex else { return false }
            let before = text.index(before: index)
            guard before >= text.startIndex, text.index(after: before) == index else { return false }
            let afterIndex = text.index(after: index)
            guard afterIndex < text.endIndex else { return false }
            return isLetter(text[before]) && isLetter(text[afterIndex])
        }
        return isWordCharacter(character)
    }

    private static func isLetter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            switch $0.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                true
            default:
                false
            }
        }
    }
}

/// Text direction of the "first strong character" (§6.6.5) — used for
/// clip-row alignment (later phases) and RTL-aware cursor movement
/// (§6.4.4's space trackpad).
public enum TextDirectionDetector {
    /// RTL Unicode blocks: Hebrew/Arabic (U+0590–U+08FF), Arabic
    /// Presentation Forms-A (U+FB1D–U+FDFF), Arabic Presentation Forms-B
    /// (U+FE70–U+FEFF).
    private static let rtlRanges: [ClosedRange<UInt32>] = [
        0x0590 ... 0x08FF,
        0xFB1D ... 0xFDFF,
        0xFE70 ... 0xFEFF,
    ]

    public enum Strength: Sendable, Equatable {
        case rtl
        case ltr
        case neutral
    }

    public static func strength(of scalar: Unicode.Scalar) -> Strength {
        guard scalar.properties.isAlphabetic else { return .neutral }
        if rtlRanges.contains(where: { $0.contains(scalar.value) }) {
            return .rtl
        }
        return .ltr
    }

    /// The direction of the first strong (non-neutral) character in `text`;
    /// `.neutral` if there is none.
    public static func dominantDirection(_ text: String) -> Strength {
        for scalar in text.unicodeScalars {
            let strength = strength(of: scalar)
            if strength != .neutral {
                return strength
            }
        }
        return .neutral
    }
}
