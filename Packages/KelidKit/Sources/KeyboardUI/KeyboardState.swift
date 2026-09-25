#if canImport(UIKit)
    import InputEngine
    import KelidCore
    import KelidSettings
    import KeyboardLayout
    import Observation

    /// §4.5: the single source of UI state. SwiftUI views observe it;
    /// `KeyGridView` (UIKit) is updated *imperatively* by `KeyboardController`
    /// instead, to keep typing fast (rule: don't let SwiftUI re-render the key
    /// grid per keystroke).
    @MainActor
    @Observable
    public final class KeyboardState {
        public enum Mode: Equatable {
            case typing
            case clipboard
            case emoji
            case edit
            case quickSettings
            case resize
        }

        public var mode: Mode = .typing
        public var language: LanguageID = .fa
        public var page: KeyboardPage = .letters
        public var shift: ShiftState = .off
        public var clipChip: String?
        public var fullAccess: Bool = false
        public var incognito: Bool = false
        public var traits: FieldTraits = .default
        public var toast: String?

        public init() {}
    }
#endif
