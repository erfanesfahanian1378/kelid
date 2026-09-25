import Foundation

/// Time only through `Clock` (rule 5.1.5) — never `Date()` directly in
/// engine code — so recency decay (§6.1.6 `halfLifeDays`), retention
/// (§6.1.7 `retentionDays`), OTP expiry and similar logic is deterministic
/// in tests.
///
/// Named to match PLAN.md exactly; within `KelidCore`'s own source this
/// shadows the standard library's unrelated `Clock` protocol (Swift's
/// `Instant`/`Duration` clocks) without ambiguity, since a module's own
/// top-level declarations take priority over the implicitly-imported
/// standard library. Code in *other* modules that also needs the stdlib
/// `Clock` in the same file would need to spell it `Swift.Clock`.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// Deterministic clock for tests: starts at a fixed instant and only moves
/// when told to.
public final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(now: Date = Date(timeIntervalSince1970: 0)) {
        current = now
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    public func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}
