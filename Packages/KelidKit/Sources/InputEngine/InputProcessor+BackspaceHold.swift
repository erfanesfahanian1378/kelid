import Foundation

/// Backspace hold-repeat timing (§6.4.6, driven by `Clock`) — split out of
/// `InputProcessor.swift` itself purely to keep that type's body under
/// SwiftLint's `type_body_length` threshold; behaviorally this is still
/// part of `InputProcessor`, just declared in a second file.
public extension InputProcessor {
    /// Call once when the backspace key is pressed down (before the
    /// touch-down tap-delete, which `KeyTouchTracker`/the controller sends
    /// separately as `.backspace`).
    func beginBackspaceHold() {
        backspaceHoldStartedAt = clock.now()
        lastBackspaceHoldFireAt = nil
    }

    func endBackspaceHold() {
        backspaceHoldStartedAt = nil
        lastBackspaceHoldFireAt = nil
    }

    /// Call periodically (e.g. every 16ms) while backspace is held. Decides
    /// — from elapsed hold duration, via `clock` — whether it's time to
    /// fire another delete yet, and whether that delete is a single
    /// character or (after 2s) a whole word. Returns whether it fired.
    @discardableResult
    func tickBackspaceHold(in doc: TextDocument) -> Bool {
        guard let backspaceHoldStartedAt else { return false }
        let now = clock.now()
        let elapsedSinceStart = now.timeIntervalSince(backspaceHoldStartedAt)
        let elapsedSinceLastFire = lastBackspaceHoldFireAt.map { now.timeIntervalSince($0) } ?? elapsedSinceStart
        let isWordMode = elapsedSinceStart >= Self.backspaceWordModeThreshold

        let requiredInterval: TimeInterval = if lastBackspaceHoldFireAt == nil {
            Self.backspaceFirstRepeatDelay
        } else if isWordMode {
            Self.backspaceWordModeInterval
        } else {
            settings.backspaceRepeat.repeatInterval
        }

        guard elapsedSinceLastFire >= requiredInterval else { return false }
        lastBackspaceHoldFireAt = now
        if isWordMode {
            _ = deleteWordBackward(in: doc)
        } else {
            _ = performBackspace(in: doc)
        }
        return true
    }
}
