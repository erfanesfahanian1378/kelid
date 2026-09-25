import KelidCore
import KeyboardLayout

/// What a focused field's traits require, independent of the user's own
/// settings (§6.4.7 "Forced English", §6.4.11 "page selection"): the
/// keyboard must show English for ASCII-only/email/URL fields, and the
/// numeric pad or symbols page for number-only fields, regardless of the
/// user's preferred language or page.
public struct FieldRequirements: Sendable, Equatable {
    public var forcedLanguage: LanguageID?
    public var forcedPage: KeyboardPage?

    public static func resolve(for traits: FieldTraits) -> FieldRequirements {
        FieldRequirements(
            forcedLanguage: forcedLanguage(for: traits.keyboardType),
            forcedPage: forcedPage(for: traits.keyboardType)
        )
    }

    /// §6.4.7: "Forced English: in `.asciiCapable`, `.emailAddress` and
    /// `.URL` fields." (Verbatim scope — not extended to `.twitter` or
    /// `.webSearch`, which §6.2.6 treats as respecting the current language.)
    private static func forcedLanguage(for keyboardType: KeyboardTypeTrait) -> LanguageID? {
        switch keyboardType {
        case .asciiCapable, .emailAddress, .url:
            .en
        default:
            nil
        }
    }

    /// §6.4.11: "`.numberPad`/`.decimalPad`/`.asciiCapableNumberPad` →
    /// numpad. `.numbersAndPunctuation` → symbols1."
    private static func forcedPage(for keyboardType: KeyboardTypeTrait) -> KeyboardPage? {
        switch keyboardType {
        case .numberPad, .decimalPad, .asciiCapableNumberPad:
            .numpad
        case .numbersAndPunctuation:
            .symbols1
        default:
            nil
        }
    }
}
