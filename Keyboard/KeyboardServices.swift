import Foundation
import KelidCore
import KelidSettings
import KelidStorage

/// Process-level services shared by the whole keyboard extension lifetime
/// (§2.1 C13: `KeyboardViewController` instances are recreated per
/// presentation, but heavy services — the settings store, the database,
/// later the language models — must be process-level singletons, loaded
/// lazily so cold start stays fast).
@MainActor
final class KeyboardServices {
    static let shared = KeyboardServices()

    let settings: SettingsStore
    private let log = Log.logger(.keyboardExtension)

    /// Set by `KeyboardViewController` on every `viewWillAppear`, from
    /// `UIInputViewController.hasFullAccess`, *before* `database` is
    /// accessed for the first time — the lazily-created `DatabaseManager`
    /// picks the shared-vs-local container based on whatever this is at
    /// that moment. (Merging the local personal-model DB into the shared
    /// one the first time Full Access is granted, per §6.11.2, lands with
    /// real user-model data in Phase 9 — nothing to merge yet.)
    var hasFullAccess = false

    private var _database: DatabaseManager?
    var database: DatabaseManager {
        if let _database {
            return _database
        }
        let paths = ContainerPaths.resolve(fullAccess: hasFullAccess)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        _database = manager
        return manager
    }

    private init() {
        settings = SettingsStore()
    }

    // MARK: - Heartbeat and probes (task 1.7, §6.11.5)

    /// Writes `kb.heartbeat` / `kb.hasFullAccess` / `kb.version` to the App
    /// Group `UserDefaults` so the app's Home tab can tell the keyboard is
    /// active (§6.10). Best-effort: without Full Access this may silently
    /// do nothing (§2.1 C2) — never relied on for correctness.
    func writeHeartbeat(now: Date = Date()) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(now, forKey: "kb.heartbeat")
        defaults.set(hasFullAccess, forKey: "kb.hasFullAccess")
        defaults.set(Self.bundleVersion, forKey: "kb.version")
        let fullAccessForLog = hasFullAccess
        log.debug("heartbeat written (fullAccess=\(fullAccessForLog, privacy: .public))")
    }

    /// Reads `app.probe` (written by the app on every launch, §6.11.5) to
    /// tell whether the App Group is actually readable right now.
    var isAppGroupReadable: Bool {
        sharedDefaults?.object(forKey: "app.probe") != nil
    }

    private var sharedDefaults: UserDefaults? {
        AppGroup.identifier.flatMap { UserDefaults(suiteName: $0) }
    }

    private static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
