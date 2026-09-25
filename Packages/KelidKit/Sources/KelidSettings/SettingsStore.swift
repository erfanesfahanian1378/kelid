import CoreGraphics
import Foundation
import KelidCore
import Observation

/// Loads, saves and syncs `KeyboardSettings` (task 1.2). The single store
/// type used by both the app and the keyboard.
///
/// - `load()`: reads the shared (App Group) blob and the local mirror; the
///   one with the newer `updatedAt` wins (D-05). Works without Full Access
///   because the local mirror is always readable.
/// - `update(_:)`: applies a mutation, stamps `updatedAt`, clamps, writes
///   the local mirror always and the shared blob best-effort (§2.1 C2: App
///   Group writes from a keyboard without Full Access fail silently — never
///   relied on), then posts `.settings.changed` (§4.7).
/// - Observes `.settings.changed` itself and reloads, so a settings change
///   made by the app while the keyboard is shown in the Try-it field is
///   picked up automatically (§6.10 "Live settings").
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: KeyboardSettings

    private let appGroupIdentifier: String?
    private let localDefaults: UserDefaults
    private let clock: Clock
    private let darwinNotifier: DarwinNotifier
    /// `deinit` on a `@MainActor` class is nonisolated by default, so it
    /// cannot touch a MainActor-isolated stored property. `@ObservationIgnored`
    /// opts this out of `@Observable`'s tracking (it's plumbing, not UI
    /// state) so `nonisolated(unsafe)` is legal here; `cancel()` itself is
    /// thread-safe (internally lock-protected), and the only mutation is the
    /// single assignment in `init`.
    @ObservationIgnored
    private nonisolated(unsafe) var observationToken: DarwinObservationToken?

    private static let storageKey = "settings.v1"

    public init(
        appGroupIdentifier: String? = AppGroup.identifier,
        localDefaults: UserDefaults = .standard,
        clock: Clock = SystemClock(),
        darwinNotifier: DarwinNotifier = .shared
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.localDefaults = localDefaults
        self.clock = clock
        self.darwinNotifier = darwinNotifier
        settings = KeyboardSettings()
        load()
        observationToken = darwinNotifier.observe(.settingsChanged, appGroupIdentifier: appGroupIdentifier) { [weak self] in
            // `DarwinNotifier` guarantees delivery on the main thread, but
            // that guarantee isn't visible to the type system since the
            // handler type itself is plain `@Sendable`, not `@MainActor`.
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    deinit {
        observationToken?.cancel()
    }

    private var sharedDefaults: UserDefaults? {
        appGroupIdentifier.flatMap { UserDefaults(suiteName: $0) }
    }

    /// Shared blob vs. local mirror, newer `updatedAt` wins.
    public func load() {
        let shared = Self.decode(sharedDefaults?.data(forKey: Self.storageKey))
        let local = Self.decode(localDefaults.data(forKey: Self.storageKey))
        switch (shared, local) {
        case let (shared?, local?):
            settings = shared.updatedAt >= local.updatedAt ? shared : local
        case let (shared?, nil):
            settings = shared
        case let (nil, local?):
            settings = local
        case (nil, nil):
            settings = KeyboardSettings()
        }
    }

    /// Re-reads from storage. Called automatically on `.settings.changed`.
    public func reload() {
        load()
    }

    /// Applies `transform` to a mutable copy of the current settings, then
    /// stamps, clamps, saves and broadcasts it.
    public func update(_ transform: (inout KeyboardSettings) -> Void) {
        var updated = settings
        transform(&updated)
        updated.updatedAt = clock.now()
        updated = updated.clamped()
        settings = updated
        save(updated)
        darwinNotifier.post(.settingsChanged, appGroupIdentifier: appGroupIdentifier)
    }

    private func save(_ settings: KeyboardSettings) {
        guard let data = Self.encode(settings) else { return }
        localDefaults.set(data, forKey: Self.storageKey)
        // Best-effort: without Full Access this may silently do nothing
        // (§2.1 C2) — the local mirror above is what keeps the keyboard
        // working regardless.
        sharedDefaults?.set(data, forKey: Self.storageKey)
    }

    private static func decode(_ data: Data?) -> KeyboardSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(KeyboardSettings.self, from: data)
    }

    private static func encode(_ settings: KeyboardSettings) -> Data? {
        try? JSONEncoder().encode(settings)
    }

    /// §6.1.3: resolves the `SizeProfile` for the given orientation.
    public func sizeProfile(for orientation: SizeOrientation) -> SizeProfile {
        switch orientation {
        case .portrait: settings.size.portrait
        case .landscape: settings.size.landscape
        }
    }

    /// §6.1.5: resolves the `PredictionSettings` for the given language.
    public func resolvedPrediction(for language: LanguageID) -> PredictionSettings {
        settings.prediction[language]
    }

    /// Task 4.2: applies §6.3.2's device-class portrait `rowHeight` default
    /// exactly once per install. `portraitScreenHeight` is the device's
    /// actual screen height in the portrait orientation — only the caller
    /// (app/keyboard target, both UIKit-aware) can read that; this module
    /// stays UIKit-free (rule 5.1.15). A no-op after the first successful
    /// call (`AdvancedSettings.deviceSizeDefaultsApplied`), so it's safe to
    /// call from both the app's launch and the keyboard's `viewDidLoad`
    /// without either one clobbering a resize the user made later — and
    /// safe to call before either process knows the other has already run,
    /// since whichever settings blob (local/shared) turns out newer wins
    /// via the usual `load()` merge.
    public func applyDeviceSizeDefaultsIfNeeded(portraitScreenHeight: CGFloat) {
        guard !settings.advanced.deviceSizeDefaultsApplied else { return }
        update { current in
            current.size.portrait.rowHeight = DeviceSizeClass.portraitRowHeightDefault(screenHeight: portraitScreenHeight)
            current.advanced.deviceSizeDefaultsApplied = true
        }
    }
}
