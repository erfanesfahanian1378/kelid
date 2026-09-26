#if canImport(UIKit)
    import InputEngine
    import Observation

    /// §6.4.9's edit panel state — enabled/disabled flags `KeyboardController`
    /// recomputes whenever the document's selection/Full-Access state might
    /// have changed.
    @MainActor
    @Observable
    public final class EditPanelModel {
        public var hasSelection: Bool
        public let hasFullAccess: Bool
        public var canUndo: Bool

        var onMoveCursor: ((MoveDirection) -> Void)?
        var onMoveCursorWord: ((MoveDirection) -> Void)?
        var onMoveCursorLine: ((MoveDirection) -> Void)?
        var onCopy: (() -> Void)?
        var onCut: (() -> Void)?
        var onPaste: (() -> Void)?
        var onDeleteWord: (() -> Void)?
        var onUndo: (() -> Void)?
        var onDone: (() -> Void)?

        public init(hasSelection: Bool, hasFullAccess: Bool, canUndo: Bool) {
            self.hasSelection = hasSelection
            self.hasFullAccess = hasFullAccess
            self.canUndo = canUndo
        }
    }
#endif
