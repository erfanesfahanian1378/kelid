/// Which page of a layout file is showing (PLAN.md §6.2.1's `pages` keys,
/// §6.2.4-§6.2.5). `KeyboardSettings.General.showNumberRow` adds a row on
/// top of `letters`; it isn't a separate page.
public enum KeyboardPage: String, Codable, Sendable, Equatable, CaseIterable {
    case letters
    case symbols1
    case symbols2
    case numpad
}
