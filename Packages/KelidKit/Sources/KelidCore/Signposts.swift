import os

/// Thin `os_signpost` helpers for the latency budgets in PLAN.md §6.13
/// (cold start, touch-to-insert, suggestion computation, KLM open...).
/// Instruments' *Points of Interest* template reads these directly; the
/// debug overlay (Phase 3+) also reads the latest interval for its own
/// display.
///
/// Shares `Log`'s subsystem so Console.app/Instruments group everything
/// under one process family. Because `log` is a lazily-initialized static,
/// call `Log.configure(bundleID:)` before the first signpost of a run for
/// the subsystem to be correct — in practice this is already true, since
/// app/keyboard startup configures `Log` before doing anything else.
public enum Signposts {
    private static let log = OSLog(subsystem: Log.currentSubsystem, category: .pointsOfInterest)

    @discardableResult
    public static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    public static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    public static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
