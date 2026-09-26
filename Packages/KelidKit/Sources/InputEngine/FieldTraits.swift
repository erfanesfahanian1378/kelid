/// Mirrors `UIKeyboardType` (task 1.3) without importing UIKit — `InputEngine`
/// must stay UIKit-free so `swift test` runs on macOS. `ProxyTextDocument`
/// (keyboard target) maps to/from the real `UIKeyboardType`.
public enum KeyboardTypeTrait: Sendable, Equatable {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case url
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
    case asciiCapableNumberPad
}

/// Mirrors `UIReturnKeyType` (§6.4.10).
public enum ReturnKeyTypeTrait: Sendable, Equatable {
    case `default`
    case go
    case google
    case join
    case next
    case route
    case search
    case send
    case yahoo
    case done
    case emergencyCall
    case `continue`
}

/// Mirrors `UITextAutocapitalizationType`.
public enum AutocapitalizationTrait: Sendable, Equatable {
    case none
    case words
    case sentences
    case allCharacters
}

/// Mirrors `UITextAutocorrectionType`.
public enum AutocorrectionTrait: Sendable, Equatable {
    case `default`
    case no
    case yes
}

/// Mirrors `UITextSpellCheckingType`.
public enum SpellCheckingTrait: Sendable, Equatable {
    case `default`
    case no
    case yes
}

/// Mirrors `UIKeyboardAppearance`.
public enum KeyboardAppearanceTrait: Sendable, Equatable {
    case `default`
    case dark
    case light
}

/// The current text field's traits, translated from UIKit's
/// `UITextInputTraits` into our own UIKit-free vocabulary (rule 5.1.5:
/// `UITextDocumentProxy` only through `TextDocument`).
///
/// `textContentType` is kept as a raw `String?` rather than an enum:
/// `UITextContentType` is an extensible string type with many
/// system-defined values (and can carry arbitrary custom ones), so
/// enumerating every case here would only go stale.
public struct FieldTraits: Sendable, Equatable {
    public var keyboardType: KeyboardTypeTrait
    public var returnKeyType: ReturnKeyTypeTrait
    public var autocapitalization: AutocapitalizationTrait
    public var autocorrection: AutocorrectionTrait
    public var spellChecking: SpellCheckingTrait
    public var keyboardAppearance: KeyboardAppearanceTrait
    public var textContentType: String?
    /// `UITextInputTraits.isSecureTextEntry` — task 8.6's §6.7.9 rule 1
    /// ("not sensitive") reads this to keep autocorrect off in password
    /// fields, same spirit as ClipboardKit's own password-like detection.
    public var isSensitive: Bool

    public init(
        keyboardType: KeyboardTypeTrait = .default,
        returnKeyType: ReturnKeyTypeTrait = .default,
        autocapitalization: AutocapitalizationTrait = .sentences,
        autocorrection: AutocorrectionTrait = .default,
        spellChecking: SpellCheckingTrait = .default,
        keyboardAppearance: KeyboardAppearanceTrait = .default,
        textContentType: String? = nil,
        isSensitive: Bool = false
    ) {
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.autocapitalization = autocapitalization
        self.autocorrection = autocorrection
        self.spellChecking = spellChecking
        self.keyboardAppearance = keyboardAppearance
        self.textContentType = textContentType
        self.isSensitive = isSensitive
    }

    public static let `default` = FieldTraits()

    /// §6.7.9 rule 1 (task 8.6): "The field allows it (`autocorrectionType
    /// != .no`, not sensitive)."
    public var allowsAutocorrect: Bool {
        autocorrection != .no && !isSensitive
    }
}
