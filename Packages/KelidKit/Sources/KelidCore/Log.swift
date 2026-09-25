import Foundation
import os

/// Namespaced `os.Logger` helpers, one category per KelidKit module.
///
/// All Kelid processes (app, keyboard extension, Share Extension) log under
/// the *same subsystem* so Console.app can filter every Kelid log line at
/// once by filtering on subsystem alone (PLAN.md §5.4). The keyboard
/// extension's bundle ID ends in ".keyboard" (and the Share Extension's in
/// ".share"); `configure(bundleID:)` strips that suffix so both processes
/// resolve to the app's own subsystem, `<prefix>.kelid`.
///
/// Call `Log.configure(bundleID:)` once, early, from every target's entry
/// point (`KelidApp.init`, `KeyboardViewController.viewDidLoad`, the Share
/// Extension's view controller) with `Bundle.main.bundleIdentifier`.
public enum Log {
    /// Used only if `configure(bundleID:)` is never called (e.g. in tests).
    private static let fallbackSubsystem = "com.example.kelid"

    // Mutated only by `configure(bundleID:)`, guarded by `lock`. Marked
    // `nonisolated(unsafe)` because access is manually synchronized below,
    // not because it is safe to read without the lock.
    private nonisolated(unsafe) static var subsystem = fallbackSubsystem
    private static let lock = NSLock()

    private static let strippedSuffixes = [".keyboard", ".share"]

    public static func configure(bundleID: String?) {
        guard var id = bundleID, !id.isEmpty else { return }
        for suffix in strippedSuffixes where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
            break
        }
        lock.lock()
        subsystem = id
        lock.unlock()
    }

    /// One case per KelidKit module (PLAN.md §4.2), plus the two app-level
    /// targets that link KelidCore directly.
    public enum Category: String, Sendable {
        case core
        case settings
        case persianText
        case keyboardLayout
        case inputEngine
        case predictionEngine
        case storage
        case clipboard
        case theme
        case emoji
        case keyboardUI
        case app
        case keyboardExtension
        case shareExtension
    }

    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: currentSubsystem, category: category.rawValue)
    }

    /// Exposed so `Signposts` can share the same subsystem without its own
    /// copy of the configure/lock dance.
    static var currentSubsystem: String {
        lock.lock()
        defer { lock.unlock() }
        return subsystem
    }
}
