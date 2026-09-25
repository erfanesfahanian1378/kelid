import InputEngine
import UIKit

/// Wraps `UITextDocumentProxy` behind the UIKit-free `TextDocument`
/// protocol (rule 5.1.5) — the only place in the keyboard target allowed to
/// touch `UITextDocumentProxy` directly.
///
/// `documentIdentifier` is a fresh UUID per instance. For Phase 1 that's
/// enough (nothing depends on it yet); Phase 3 makes document-change
/// detection precise (the shadow buffer, §6.4.8) and decides exactly when
/// `KeyboardViewController` should create a new `ProxyTextDocument` versus
/// reusing one.
@MainActor
final class ProxyTextDocument: TextDocument {
    private let proxyProvider: () -> UITextDocumentProxy

    let documentIdentifier = UUID()

    init(proxyProvider: @escaping () -> UITextDocumentProxy) {
        self.proxyProvider = proxyProvider
    }

    private var proxy: UITextDocumentProxy {
        proxyProvider()
    }

    var contextBefore: String? {
        proxy.documentContextBeforeInput
    }

    var contextAfter: String? {
        proxy.documentContextAfterInput
    }

    var selectedText: String? {
        proxy.selectedText
    }

    var hasText: Bool {
        proxy.hasText
    }

    var traits: FieldTraits {
        FieldTraits(
            keyboardType: Self.map(proxy.keyboardType),
            returnKeyType: Self.map(proxy.returnKeyType),
            autocapitalization: Self.map(proxy.autocapitalizationType),
            autocorrection: Self.map(proxy.autocorrectionType),
            spellChecking: Self.map(proxy.spellCheckingType),
            keyboardAppearance: Self.map(proxy.keyboardAppearance),
            textContentType: proxy.textContentType?.rawValue
        )
    }

    func insertText(_ text: String) {
        proxy.insertText(text)
    }

    func deleteBackward() {
        proxy.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    // MARK: - Trait mapping (UIKit -> our own UIKit-free enums)

    private static func map(_ type: UIKeyboardType?) -> KeyboardTypeTrait {
        switch type {
        case .asciiCapable: .asciiCapable
        case .numbersAndPunctuation: .numbersAndPunctuation
        case .URL: .url
        case .numberPad: .numberPad
        case .phonePad: .phonePad
        case .namePhonePad: .namePhonePad
        case .emailAddress: .emailAddress
        case .decimalPad: .decimalPad
        case .twitter: .twitter
        case .webSearch: .webSearch
        case .asciiCapableNumberPad: .asciiCapableNumberPad
        default: .default
        }
    }

    private static func map(_ type: UIReturnKeyType?) -> ReturnKeyTypeTrait {
        switch type {
        case .go: .go
        case .google: .google
        case .join: .join
        case .next: .next
        case .route: .route
        case .search: .search
        case .send: .send
        case .yahoo: .yahoo
        case .done: .done
        case .emergencyCall: .emergencyCall
        case .continue: .continue
        default: .default
        }
    }

    private static func map(_ type: UITextAutocapitalizationType?) -> AutocapitalizationTrait {
        switch type {
        case .words: .words
        case .sentences: .sentences
        case .allCharacters: .allCharacters
        default: .none
        }
    }

    private static func map(_ type: UITextAutocorrectionType?) -> AutocorrectionTrait {
        switch type {
        case .no: .no
        case .yes: .yes
        default: .default
        }
    }

    private static func map(_ type: UITextSpellCheckingType?) -> SpellCheckingTrait {
        switch type {
        case .no: .no
        case .yes: .yes
        default: .default
        }
    }

    private static func map(_ appearance: UIKeyboardAppearance?) -> KeyboardAppearanceTrait {
        switch appearance {
        case .dark: .dark
        case .light: .light
        default: .default
        }
    }
}
