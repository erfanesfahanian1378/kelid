import KelidCore

/// Derived after every action and on `textDidChange` (task 3.5, §6.4.2).
public struct TypingContext: Sendable, Equatable {
    /// Word characters (§6.6.3) directly before the cursor.
    public var prefix: String
    /// Word characters directly after the cursor. Non-empty means
    /// suggestions are disabled for v1 (mid-word cursor position).
    public var suffix: String
    /// Up to 2 words back in the same sentence (stops at `. ! ? ؟ … \n`);
    /// `["<s>"]` at a sentence start.
    public var previousWords: [String]
    public var isSentenceStart: Bool
    public var language: LanguageID
    public var traits: FieldTraits

    public init(
        prefix: String = "",
        suffix: String = "",
        previousWords: [String] = ["<s>"],
        isSentenceStart: Bool = true,
        language: LanguageID = .fa,
        traits: FieldTraits = .default
    ) {
        self.prefix = prefix
        self.suffix = suffix
        self.previousWords = previousWords
        self.isSentenceStart = isSentenceStart
        self.language = language
        self.traits = traits
    }

    public static let empty = TypingContext()
}
