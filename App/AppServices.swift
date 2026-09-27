import ClipboardKit
import Foundation
import KelidCore
import KelidSettings
import KelidStorage

/// Process-level services shared by the whole app (task 10.1) — the
/// app-side counterpart of `Keyboard/KeyboardServices.swift`. Unlike the
/// keyboard, the app always has access to the shared App Group container
/// (there's no "Full Access" concept for the app itself), so there's no
/// local-fallback path to consider here.
@MainActor
@Observable
final class AppServices {
    let settings: SettingsStore
    let database: DatabaseManager
    let clipRepository: ClipRepository
    let snippetRepository: SnippetRepository

    init() {
        settings = SettingsStore()
        let paths = ContainerPaths.resolve(fullAccess: true)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        database = manager
        clipRepository = ClipRepository(database: manager)
        snippetRepository = SnippetRepository(database: manager)
    }

    /// Call once from `KelidApp.init`/`.task` — opens (and migrates) the
    /// database and resumes it, same lifecycle contract every other process
    /// follows (§6.11.2).
    func start() async {
        do {
            try await database.open()
        } catch {
            Log.logger(.app).error("database open failed: \(error, privacy: .public)")
        }
        await database.resume()
    }

    /// Scene-phase hooks (§6.11.2: "App does the same on scene phase
    /// .background / .active").
    func handleScenePhaseChange(isActive: Bool) {
        Task {
            if isActive {
                await database.resume()
            } else {
                await database.suspend()
            }
        }
    }
}
