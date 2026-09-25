/// A key's behavior (PLAN.md §6.2.1). Raw values match the JSON layout
/// files exactly, including the `page:*` colon-namespaced ones.
public enum KeyAction: String, Codable, Sendable, Equatable {
    /// Inserts `KeyDefinition.out` — the default when `action` is omitted.
    case char
    case shift
    case backspace
    case space
    case `return`
    case zwnj
    case pageLetters = "page:letters"
    case pageSymbols1 = "page:symbols1"
    case pageSymbols2 = "page:symbols2"
    case language
    case globe
    case emoji
    case dismiss
}
