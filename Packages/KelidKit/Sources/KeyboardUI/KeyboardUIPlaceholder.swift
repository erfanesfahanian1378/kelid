#if canImport(UIKit)
    import UIKit
#endif

/// Placeholder public type for the `KeyboardUI` module.
///
/// `KeyboardUI` is the one module allowed to import UIKit and SwiftUI
/// (PLAN.md §4.2), but every file in it must still guard those imports with
/// `#if canImport(UIKit)` so `swift test` keeps building on plain macOS,
/// where UIKit does not exist. This placeholder itself touches no UIKit
/// API, so it compiles unconditionally on both platforms; real UIKit-backed
/// types (`KeyGridView`, `KeyboardRootView`, panels…) arrive from Phase 2
/// onward, each behind the same guard.
public struct KeyboardUIPlaceholder: Sendable {
    public init() {}

    public var isReady: Bool {
        true
    }
}
