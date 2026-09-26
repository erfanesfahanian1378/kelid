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
    /// accessed for the first time.
    var hasFullAccess = false

    private var _database: DatabaseManager?
    /// Whether `_database` was itself resolved against the shared App Group
    /// container (`true`) or this process's own local container (`false`) —
    /// tracked separately from `hasFullAccess` so `database` below can tell
    /// a genuine local→shared *transition* apart from "still local" or
    /// "still shared," per task 9.9/§6.11.2.
    private var _databaseIsShared = false

    /// Picks the shared-vs-local container based on `hasFullAccess` at the
    /// time of first access, same as before Phase 9 — but now also
    /// *upgrades* an already-cached local `DatabaseManager` to a shared one
    /// the moment `hasFullAccess` turns `true`, instead of permanently
    /// sticking with whichever container happened to be resolved first.
    /// Never downgrades back to local once shared (Full Access being
    /// revoked mid-session doesn't un-merge anything — §6.11.2 only
    /// describes the local→shared direction). `mergeLocalUserModelIfNeeded()`
    /// must run (and finish) *before* this upgrade path is hit for real user
    /// data to actually reach the shared DB rather than silently starting a
    /// fresh, empty one.
    var database: DatabaseManager {
        if let _database, _databaseIsShared || !hasFullAccess {
            return _database
        }
        let paths = ContainerPaths.resolve(fullAccess: hasFullAccess)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        _database = manager
        _databaseIsShared = hasFullAccess
        return manager
    }

    private init() {
        settings = SettingsStore()
    }

    /// Task 9.9 (§6.11.2): "On the first launch with Full Access, merge [the
    /// local personal-model DB] into the shared DB (sum counts, max
    /// `lastUsed`, union blocklists) and delete the local copy." Driven by
    /// the local DB file's mere *existence* rather than a separate persisted
    /// flag: once merged, the file (and its WAL/SHM sidecars) are deleted,
    /// so any later call — this session or a future one — naturally finds
    /// nothing to merge and no-ops, which is exactly "once" without needing
    /// to track that fact anywhere else. Must be called (and awaited)
    /// *before* `database` is accessed with `hasFullAccess == true` for the
    /// first time, or the merge would target an already-fresh shared DB
    /// instead of receiving these words. Returns a short description for
    /// the debug overlay, or `nil` when there was nothing to merge.
    /// Task 9.9: "the merge result is logged in the debug overlay" —
    /// `KeyboardViewController.refreshDebugOverlay()` reads this. `nil`
    /// until a merge has actually happened this process.
    private(set) var lastUserModelMergeResult: String?

    /// Task 9.6's "cached for 1 hour" — process-level (not per
    /// `KeyboardViewController` instance), since §2.1 C13 says instances get
    /// recreated far more often than that.
    var lastSupplementaryLexiconFetchAt: Date?

    func mergeLocalUserModelIfNeeded() async -> String? {
        guard hasFullAccess, !_databaseIsShared || _database == nil else { return nil }
        let localPaths = ContainerPaths.resolve(fullAccess: false)
        guard FileManager.default.fileExists(atPath: localPaths.databaseURL.path) else { return nil }
        do {
            let localDatabase = DatabaseManager(fileURL: localPaths.databaseURL)
            try await localDatabase.open()
            let sharedDatabase = database // resolves (and caches) the shared manager, per the upgrade logic above
            try await sharedDatabase.open()
            let sharedRepository = UserModelRepository(database: sharedDatabase)
            let localRepository = UserModelRepository(database: localDatabase)
            var mergedWordCounts: [String] = []
            for language in LanguageID.allCases {
                try await sharedRepository.merge(from: localRepository, language: language)
                let count = try await sharedRepository.loadWords(language: language, limit: Int.max).count
                mergedWordCounts.append("\(language.rawValue):\(count)")
            }
            try Self.deleteDatabaseFile(at: localPaths.databaseURL)
            let result = "merged local model (\(mergedWordCounts.joined(separator: ", ")))"
            log.notice("\(result, privacy: .public)")
            lastUserModelMergeResult = result
            return result
        } catch {
            log.error("local user-model merge failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// Removes the main SQLite file plus its WAL/SHM sidecars, if present —
    /// deleting only the main file would leave orphaned, briefly-confusing
    /// `-wal`/`-shm` files behind (harmless to SQLite itself, since it always
    /// recreates them, but pointless clutter given the whole point here is
    /// deleting this database for good).
    private static func deleteDatabaseFile(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.removeItem(at: url)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
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
