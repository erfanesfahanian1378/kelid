/// Structural checks for a `KeyboardLayoutFile` (PLAN.md §6.2.1). Applied to
/// every bundled layout by `LayoutRepository` at load time; invalid files
/// fail tests and log an error at runtime, falling back to `en.qwerty`.
public enum LayoutValidationError: Error, Sendable, Equatable {
    case emptyRow(page: String, rowIndex: Int)
    case nonPositiveWidth(page: String, rowIndex: Int, keyIndex: Int)
    case emptyOutOnCharKey(page: String, rowIndex: Int, keyIndex: Int)
    case noPages
}

public enum LayoutValidator {
    public static func validate(_ file: KeyboardLayoutFile) throws {
        guard !file.pages.isEmpty else {
            throw LayoutValidationError.noPages
        }
        for (page, definition) in file.pages {
            for (rowIndex, row) in definition.rows.enumerated() {
                guard !row.isEmpty else {
                    throw LayoutValidationError.emptyRow(page: page, rowIndex: rowIndex)
                }
                for (keyIndex, key) in row.enumerated() {
                    if key.isSpacer {
                        guard let spacer = key.spacer, spacer > 0 else {
                            throw LayoutValidationError.nonPositiveWidth(page: page, rowIndex: rowIndex, keyIndex: keyIndex)
                        }
                        continue
                    }
                    guard key.width > 0 else {
                        throw LayoutValidationError.nonPositiveWidth(page: page, rowIndex: rowIndex, keyIndex: keyIndex)
                    }
                    // "actions known" is enforced by KeyAction being a
                    // closed Codable enum: an unrecognized action string
                    // already fails to decode before validation runs.
                    if key.action == .char, key.out?.isEmpty ?? true {
                        throw LayoutValidationError.emptyOutOnCharKey(page: page, rowIndex: rowIndex, keyIndex: keyIndex)
                    }
                }
            }
        }
    }

    /// §6.2.2: every one of the 32 Persian letters appears exactly once in
    /// `fa.standard`'s letters page. Not enforced as a general rule for
    /// every `fa.*` file — `fa.compact` deliberately omits چ as a standalone
    /// key (it's reachable only as ج's long-press alternate, §6.2.2), which
    /// would otherwise directly contradict a blanket "every fa.* file" rule.
    public static let persianAlphabet: [Character] = Array("ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی")

    public static func validatePersianAlphabetComplete(_ file: KeyboardLayoutFile) throws {
        guard let lettersPage = file[.letters] else {
            throw LayoutValidationError.noPages
        }
        var counts: [Character: Int] = [:]
        for row in lettersPage.rows {
            for key in row {
                guard let out = key.out, out.count == 1, let char = out.first else { continue }
                counts[char, default: 0] += 1
            }
        }
        for letter in persianAlphabet {
            guard counts[letter] == 1 else {
                throw LayoutValidationError.emptyOutOnCharKey(page: KeyboardPage.letters.rawValue, rowIndex: -1, keyIndex: -1)
            }
        }
    }
}
