import KelidCore

/// Which special field type (if any) forces a different bottom row
/// (§6.2.6). Deliberately separate from `InputEngine`'s `KeyboardTypeTrait`:
/// `InputEngine` depends on `KeyboardLayout` (not the other way around), so
/// this is a small, independent enum scoped to exactly the cases
/// bottom-row composition branches on. A caller with a full `FieldTraits`
/// maps its `keyboardType` down to this.
public enum BottomRowKeyboardType: Sendable, Equatable {
    case `default`
    case emailAddress
    case url
    case webSearch
    case twitter
}

/// What `BottomRowBuilder` needs to compose the right row (task 2.4).
public struct BottomRowContext: Sendable, Equatable {
    public var page: KeyboardPage
    public var language: LanguageID
    public var languagesCount: Int
    public var needsGlobe: Bool
    public var keyboardType: BottomRowKeyboardType
    /// `appearance.bottomRowEmojiKey` (§6.1.8/§6.2.6): an emoji key goes
    /// right after the language-toggle key, when there is one.
    public var showEmojiKey: Bool

    public init(
        page: KeyboardPage,
        language: LanguageID,
        languagesCount: Int,
        needsGlobe: Bool,
        keyboardType: BottomRowKeyboardType = .default,
        showEmojiKey: Bool = false
    ) {
        self.page = page
        self.language = language
        self.languagesCount = languagesCount
        self.needsGlobe = needsGlobe
        self.keyboardType = keyboardType
        self.showEmojiKey = showEmojiKey
    }
}

/// Builds the bottom row from context (§6.2.6) — never stored in a layout
/// JSON file, since it depends on page, language count, the globe key, the
/// keyboard type and settings, not just the language.
public enum BottomRowBuilder {
    public static func build(_ context: BottomRowContext) -> [KeyDefinition] {
        switch context.keyboardType {
        case .emailAddress: return emailRow(context)
        case .url: return urlRow(context)
        case .twitter: return twitterRow(context)
        case .default, .webSearch:
            // .webSearch is structurally identical to the plain letters/
            // symbols row — only the return key's *label* differs ("Search"
            // / "جستجو"), which is a rendering concern, not a structural one
            // (Phase 2 is pure logic, no rendering — §8 Phase 2 out-of-scope).
            break
        }
        switch context.page {
        case .letters: return lettersRow(context)
        case .symbols1, .symbols2: return symbolsRow(context)
        case .numpad: return [] // "numpad | none" (§6.2.6)
        }
    }

    private static func globeKey(_ context: BottomRowContext) -> KeyDefinition? {
        context.needsGlobe ? KeyDefinition(label: "🌐", action: .globe, width: 1.25) : nil
    }

    private static func emojiKey() -> KeyDefinition {
        KeyDefinition(label: "😀", action: .emoji, width: 1.25)
    }

    private static func returnKey(width: Double = 1.75) -> KeyDefinition {
        KeyDefinition(label: "⏎", action: .return, width: width)
    }

    private static func spaceKey(_: BottomRowContext, label: String? = nil) -> KeyDefinition {
        KeyDefinition(label: label, action: .space, flex: true)
    }

    private static func lettersRow(_ context: BottomRowContext) -> [KeyDefinition] {
        var keys: [KeyDefinition] = [
            KeyDefinition(out: context.language == .fa ? "۱۲۳" : "123", action: .pageSymbols1, width: 1.25),
        ]
        if let globe = globeKey(context) {
            keys.append(globe)
        }
        if context.languagesCount > 1 {
            keys.append(KeyDefinition(out: context.language == .fa ? "EN" : "فا", action: .language, width: 1.25))
            if context.showEmojiKey {
                keys.append(emojiKey())
            }
        }
        if context.language == .fa {
            keys.append(KeyDefinition(label: "ZWNJ", action: .zwnj, width: 1.25))
        }
        keys.append(spaceKey(context, label: context.language == .fa ? "فارسی" : "English"))
        // "." here relies on the letters layout file's own top-level
        // `alternates["."]` entry (، ؛ ؟ ! : … for fa, , ? ! ' " for en) —
        // both fa.standard.json and en.qwerty.json already define it, so
        // this key doesn't need to repeat it.
        keys.append(KeyDefinition(out: "."))
        keys.append(returnKey())
        return keys
    }

    private static func symbolsRow(_ context: BottomRowContext) -> [KeyDefinition] {
        var keys: [KeyDefinition] = [
            KeyDefinition(out: context.language == .fa ? "ابپ" : "ABC", action: .pageLetters, width: 1.25),
        ]
        if let globe = globeKey(context) {
            keys.append(globe)
        }
        keys.append(spaceKey(context, label: context.language == .fa ? "فارسی" : "English"))
        keys.append(returnKey())
        return keys
    }

    private static func emailRow(_ context: BottomRowContext) -> [KeyDefinition] {
        var keys: [KeyDefinition] = [
            KeyDefinition(out: "123", action: .pageSymbols1, width: 1.25),
        ]
        if let globe = globeKey(context) {
            keys.append(globe)
        }
        // §6.2.6: "space(flex, ≥ 3)" — a stated minimum this simple flex
        // model doesn't separately enforce; in practice the email row has
        // few enough fixed-width keys that the remaining space always
        // exceeds 3 units anyway.
        keys.append(spaceKey(context))
        keys.append(KeyDefinition(out: "@"))
        keys.append(KeyDefinition(out: "."))
        keys.append(returnKey())
        return keys
    }

    private static func urlRow(_ context: BottomRowContext) -> [KeyDefinition] {
        var keys: [KeyDefinition] = [
            KeyDefinition(out: "123", action: .pageSymbols1, width: 1.25),
        ]
        if let globe = globeKey(context) {
            keys.append(globe)
        }
        keys.append(KeyDefinition(out: "."))
        keys.append(KeyDefinition(out: "/"))
        keys.append(KeyDefinition(out: ".com", width: 1.5, alternates: [".ir", ".org", ".net", ".edu"]))
        keys.append(returnKey(width: 2.0))
        return keys
    }

    private static func twitterRow(_ context: BottomRowContext) -> [KeyDefinition] {
        var keys: [KeyDefinition] = [
            KeyDefinition(out: "123", action: .pageSymbols1, width: 1.25),
        ]
        if let globe = globeKey(context) {
            keys.append(globe)
        }
        keys.append(KeyDefinition(out: "@"))
        keys.append(KeyDefinition(out: "#"))
        keys.append(spaceKey(context))
        keys.append(returnKey())
        return keys
    }
}
