#if canImport(UIKit)
    import UIKit

    /// Backspace hold-repeat timing (task 3.2/3.14, §6.4.6/§6.4.12) — split
    /// out of `KeyboardController.swift` itself purely to keep that type's
    /// body under SwiftLint's `type_body_length`; behaviorally this is
    /// still part of `KeyboardController`, just declared in a second file.
    ///
    /// Selector-based, not the closure-based `Timer` API: a `block:` closure
    /// crossing into `@Sendable`/actor-isolation territory is exactly the
    /// kind of friction `KeyboardController: NSObject` doesn't need to
    /// invite — `#selector` dispatch on the run loop that scheduled it (the
    /// main thread, here) is unambiguous under this module's default
    /// `MainActor` isolation.
    ///
    /// Note `handleBackspaceRepeatTick` below: `tickBackspaceHold` doesn't
    /// recompute `context` or auto-capitalization on every fired delete
    /// (only `handle(_:in:)` does) — a real but minor gap: `state.shift` can
    /// lag by one character's worth of staleness while the hold is active,
    /// self-correcting the moment any other action calls `handle(_:in:)`.
    /// Fixing it properly means `tickBackspaceHold` returning
    /// `[InputEffect]` instead of `Bool`, which several
    /// `InputProcessorTests` assert on directly — left as a follow-up (see
    /// PROGRESS.md decision log) rather than reshaping tested API mid-phase.
    extension KeyboardController {
        func startBackspaceRepeatTimer() {
            backspaceRepeatTimer?.invalidate()
            backspaceRepeatTimer = Timer.scheduledTimer(
                timeInterval: 1.0 / 60.0, target: self, selector: #selector(handleBackspaceRepeatTick), userInfo: nil, repeats: true
            )
        }

        func stopBackspaceRepeatTimer() {
            backspaceRepeatTimer?.invalidate()
            backspaceRepeatTimer = nil
            inputProcessor.endBackspaceHold()
        }

        @objc fileprivate func handleBackspaceRepeatTick() {
            guard inputProcessor.tickBackspaceHold(in: documentProvider()) else { return }
            guard hasFullAccess, let style = hapticStyle() else { return }
            feedbackService.prepareHaptic(style: style)
            feedbackService.fireHaptic()
        }
    }
#endif
