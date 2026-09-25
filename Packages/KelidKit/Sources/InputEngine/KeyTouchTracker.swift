import CoreGraphics
import Foundation
import KeyboardLayout

/// What kind of key is being tracked — determines whether it commits on
/// touch-up (character/space/return/other) or acts immediately on
/// touch-down (backspace, shift), and whether it supports long-press
/// alternates and/or the space trackpad (§6.4.12).
public enum TrackedKeyKind: Sendable, Equatable {
    case character(alternates: [String])
    case space
    case returnKey
    case backspace
    case shift
    /// Any other action key (globe, page switch, language, zwnj, emoji…)
    /// that just commits on touch-up with no special handling.
    case other
}

public struct TrackedKey: Sendable, Equatable {
    public let id: String
    public let kind: TrackedKeyKind
    public let center: CGPoint
    public let width: CGFloat

    public init(id: String, kind: TrackedKeyKind, center: CGPoint, width: CGFloat) {
        self.id = id
        self.kind = kind
        self.center = center
        self.width = width
    }
}

/// What `KeyTouchTracker` produces for the UIKit bridge / `KeyboardController`
/// to act on. Never touches `TextDocument` itself — that's `InputProcessor`'s
/// job, driven by `.commit`/`.commitAlternate`/`.immediateAction`.
public enum KeyTouchEvent: Sendable, Equatable {
    case pressBegan(keyID: String)
    case pressEnded(keyID: String)
    case commit(keyID: String)
    case commitAlternate(keyID: String, alternate: String)
    /// Backspace or shift acted the moment the touch went down.
    case immediateAction(keyID: String)
    case alternatesShown(keyID: String, alternates: [String])
    /// `nil` selection means "the primary character" (no alternate chosen).
    case alternateSelectionChanged(index: Int?)
    /// Signed logical-character delta for the space trackpad — already
    /// direction-resolved (RTL-aware) by the tracker.
    case trackpadStep(characters: Int)
    case languageSwipe
    /// Positive: delete one more word. Negative: restore one previously
    /// swipe-deleted word.
    case backspaceSwipeWordDelta(Int)
    case cancelled(keyID: String)
}

public struct TouchSettings: Sendable, Equatable {
    public var longPressDelayMs: Int
    public var cursorSpeed: Double
    public var rtlVisualCursor: Bool
    public var backspaceSwipeDeletesWords: Bool

    public init(
        longPressDelayMs: Int = 350,
        cursorSpeed: Double = 1.0,
        rtlVisualCursor: Bool = true,
        backspaceSwipeDeletesWords: Bool = true
    ) {
        self.longPressDelayMs = longPressDelayMs
        self.cursorSpeed = cursorSpeed
        self.rtlVisualCursor = rtlVisualCursor
        self.backspaceSwipeDeletesWords = backspaceSwipeDeletesWords
    }
}

/// Pure logic (§6.4.12), fed `(touchID, point, timestamp, phase)` so it's
/// unit-testable without UIKit. Manages *all* concurrently-active touches
/// together (not one instance per touch) because rollover requires
/// cross-touch visibility: a new touch-down must commit any other touch
/// still pressed on a committable key.
@MainActor
public final class KeyTouchTracker {
    private enum State {
        case pressed(key: TrackedKey, downAt: TimeInterval, downPoint: CGPoint)
        case trackpad(key: TrackedKey, isRTLContext: Bool, entryPoint: CGPoint, accumulatedDelta: Double)
        case alternates(key: TrackedKey, direction: Direction, selectedIndex: Int?)
        case backspaceHeld(key: TrackedKey, downPoint: CGPoint, wordsDeleted: Int)
    }

    private let settings: TouchSettings
    private var states: [AnyHashable: State] = [:]

    /// Distance (pt) before space-bar movement is treated as trackpad
    /// dragging rather than a tap (§6.4.4).
    private static let trackpadEntryThreshold: Double = 8
    /// pt per character step at `cursorSpeed == 1.0` (§6.4.4).
    private static let trackpadBaseStepDistance: Double = 8
    /// pt per additional word deleted while swiping from backspace (§6.4.6).
    private static let backspaceSwipeStepDistance: Double = 24

    /// Fed explicit timestamps per touch event (task 3.2/§6.4.12), rather
    /// than reading `Clock.now()` itself — every timing decision (long-press
    /// delay, trackpad step math) is a function of the timestamps and
    /// points the caller passes in, which is what keeps this testable with
    /// synthetic event sequences.
    public init(settings: TouchSettings) {
        self.settings = settings
    }

    // MARK: - Touch phases

    @discardableResult
    public func touchBegan(
        touchID: AnyHashable,
        key: TrackedKey,
        at point: CGPoint,
        timestamp: TimeInterval
    ) -> [KeyTouchEvent] {
        var events: [KeyTouchEvent] = []

        // Rollover: a new touch-down commits any other touch still pressed
        // on a committable key (§6.4.12).
        for (otherID, state) in states where otherID != touchID {
            if case let .pressed(otherKey, _, _) = state, isCommittable(otherKey.kind) {
                events.append(.commit(keyID: otherKey.id))
                events.append(.pressEnded(keyID: otherKey.id))
                states.removeValue(forKey: otherID)
            }
        }

        switch key.kind {
        case .shift:
            events.append(.immediateAction(keyID: key.id))
        case .backspace:
            events.append(.immediateAction(keyID: key.id))
            states[touchID] = .backspaceHeld(key: key, downPoint: point, wordsDeleted: 0)
        default:
            states[touchID] = .pressed(key: key, downAt: timestamp, downPoint: point)
        }
        events.append(.pressBegan(keyID: key.id))
        return events
    }

    @discardableResult
    public func touchMoved(
        touchID: AnyHashable,
        to point: CGPoint,
        timestamp: TimeInterval,
        isRTLContext: Bool = false,
        direction: Direction = .ltr
    ) -> [KeyTouchEvent] {
        guard let state = states[touchID] else { return [] }

        switch state {
        case let .pressed(key, downAt, downPoint):
            if key.kind == .space {
                let dx = point.x - downPoint.x
                let dy = point.y - downPoint.y
                if abs(dx) > Self.trackpadEntryThreshold, abs(dx) > abs(dy) {
                    states[touchID] = .trackpad(key: key, isRTLContext: isRTLContext, entryPoint: point, accumulatedDelta: 0)
                    return []
                }
            }
            if case let .character(alternates) = key.kind, !alternates.isEmpty,
               timestamp - downAt >= Double(settings.longPressDelayMs) / 1000
            {
                states[touchID] = .alternates(key: key, direction: direction, selectedIndex: nil)
                return [.alternatesShown(keyID: key.id, alternates: alternates)]
            }
            return []

        case let .trackpad(key, isRTLContext, entryPoint, accumulatedDelta):
            let totalDelta = point.x - entryPoint.x
            let stepDistance = Self.trackpadBaseStepDistance / max(settings.cursorSpeed, 0.01)
            let previousSteps = Int((accumulatedDelta / stepDistance).rounded(.towardZero))
            let currentSteps = Int((totalDelta / stepDistance).rounded(.towardZero))
            let deltaSteps = currentSteps - previousSteps
            states[touchID] = .trackpad(key: key, isRTLContext: isRTLContext, entryPoint: entryPoint, accumulatedDelta: totalDelta)
            guard deltaSteps != 0 else { return [] }
            // Visual left/right; invert to logical forward/backward when the
            // surrounding text is RTL and rtlVisualCursor is on (§6.4.4).
            let invert = settings.rtlVisualCursor && isRTLContext
            return [.trackpadStep(characters: invert ? -deltaSteps : deltaSteps)]

        case let .alternates(key, direction, previousIndex):
            guard case let .character(alternates) = key.kind else { return [] }
            let newIndex = alternateIndex(for: point.x, key: key, alternates: alternates, direction: direction)
            guard newIndex != previousIndex else { return [] }
            states[touchID] = .alternates(key: key, direction: direction, selectedIndex: newIndex)
            return [.alternateSelectionChanged(index: newIndex)]

        case let .backspaceHeld(key, downPoint, wordsDeleted):
            // Swipe-left word deletion (§6.4.6): every 24pt of *leftward*
            // movement from the down point deletes one more word; moving
            // back right restores.
            guard settings.backspaceSwipeDeletesWords else { return [] }
            let dx = point.x - downPoint.x // negative = moved left
            let targetWordsDeleted = max(0, Int((-dx / Self.backspaceSwipeStepDistance).rounded(.towardZero)))
            guard targetWordsDeleted != wordsDeleted else { return [] }
            states[touchID] = .backspaceHeld(key: key, downPoint: downPoint, wordsDeleted: targetWordsDeleted)
            return [.backspaceSwipeWordDelta(targetWordsDeleted - wordsDeleted)]
        }
    }

    @discardableResult
    public func touchEnded(touchID: AnyHashable, at _: CGPoint, timestamp _: TimeInterval) -> [KeyTouchEvent] {
        defer { states.removeValue(forKey: touchID) }
        guard let state = states[touchID] else { return [] }

        switch state {
        case let .pressed(key, _, _):
            var events: [KeyTouchEvent] = []
            if isCommittable(key.kind) {
                events.append(.commit(keyID: key.id))
            }
            events.append(.pressEnded(keyID: key.id))
            return events

        case let .trackpad(key, _, _, _):
            return [.pressEnded(keyID: key.id)]

        case let .alternates(key, _, selectedIndex):
            guard case let .character(alternates) = key.kind else { return [.pressEnded(keyID: key.id)] }
            var events: [KeyTouchEvent] = []
            if let selectedIndex, alternates.indices.contains(selectedIndex) {
                events.append(.commitAlternate(keyID: key.id, alternate: alternates[selectedIndex]))
            } else {
                events.append(.commit(keyID: key.id))
            }
            events.append(.pressEnded(keyID: key.id))
            return events

        case let .backspaceHeld(key, _, _):
            return [.pressEnded(keyID: key.id)]
        }
    }

    @discardableResult
    public func touchCancelled(touchID: AnyHashable) -> [KeyTouchEvent] {
        defer { states.removeValue(forKey: touchID) }
        guard let state = states[touchID] else { return [] }
        let keyID: String = switch state {
        case let .pressed(key, _, _): key.id
        case let .trackpad(key, _, _, _): key.id
        case let .alternates(key, _, _): key.id
        case let .backspaceHeld(key, _, _): key.id
        }
        return [.cancelled(keyID: keyID)]
    }

    // MARK: - Helpers

    private func isCommittable(_ kind: TrackedKeyKind) -> Bool {
        switch kind {
        case .character, .space, .returnKey, .other: true
        case .backspace, .shift: false
        }
    }

    /// §6.2.1/task 3.4: alternates are laid out starting at the key's own
    /// position, extending in the reading direction; `nil` means the touch
    /// is still over the primary key (no alternate chosen).
    private func alternateIndex(for touchX: Double, key: TrackedKey, alternates: [String], direction: Direction) -> Int? {
        guard !alternates.isEmpty, key.width > 0 else { return nil }
        let rawOffset = touchX - key.center.x
        let signedOffset = direction == .rtl ? -rawOffset : rawOffset
        guard signedOffset >= key.width / 2 else { return nil }
        let index = Int(((signedOffset - key.width / 2) / key.width).rounded(.towardZero))
        return min(max(index, 0), alternates.count - 1)
    }
}
