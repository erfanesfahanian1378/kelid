import InputEngine
import UIKit

/// Wraps `UITextDocumentProxy` behind the UIKit-free `TextDocument`
/// protocol (rule 5.1.5) — the only place in the keyboard target allowed to
/// touch `UITextDocumentProxy` directly.
///
/// Holds `viewController` *weakly* and reads `textDocumentProxy` fresh on
/// every access (never stores the proxy itself) — `KeyboardViewController`
/// keeps exactly one long-lived instance of this type for its whole
/// lifetime (see its `document` property) rather than one per access: a
/// stable `documentIdentifier` is what lets `InputProcessor`'s shadow
/// buffer (§6.4.8) tell "same document, more typing" apart from "focus
/// moved to a different field" — recreating this on every keystroke would
/// reset that buffer every time. A weak back-reference (rather than the
/// closure Phase 1 used) means whichever object holds *this* instance
/// long-term — including a closure captured by `KeyboardController`,
/// Phase 3's actual long-term holder — can do so without creating a
/// reference cycle back to the view controller.
@MainActor
final class ProxyTextDocument: TextDocument {
    private weak var viewController: UIInputViewController?

    let documentIdentifier = UUID()

    init(viewController: UIInputViewController) {
        self.viewController = viewController
    }

    /// `nil` only once the view controller itself is gone — at which point
    /// nothing should still be calling into this instance anyway, so every
    /// accessor below degrades to an inert default rather than crashing.
    private var proxy: UITextDocumentProxy? {
        viewController?.textDocumentProxy
    }

    var contextBefore: String? {
        proxy?.documentContextBeforeInput
    }

    var contextAfter: String? {
        proxy?.documentContextAfterInput
    }

    var selectedText: String? {
        proxy?.selectedText
    }

    var hasText: Bool {
        proxy?.hasText ?? false
    }

    var traits: FieldTraits {
        guard let proxy else { return .default }
        return FieldTraits(
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
        proxy?.insertText(text)
    }

    func deleteBackward() {
        proxy?.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
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
