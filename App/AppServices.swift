import ClipboardKit
import Foundation
import KelidCore
import KelidSettings
import KelidStorage
import ThemeKit

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
    let containerPaths: ContainerPaths
    let themeStore: ThemeStore
    let builtInThemeCatalog = BuiltInThemeCatalog()

    init() {
        settings = SettingsStore()
        let paths = ContainerPaths.resolve(fullAccess: true)
        containerPaths = paths
        themeStore = ThemeStore(paths: paths)
        let manager = DatabaseManager(fileURL: paths.databaseURL)
        database = manager
        clipRepository = ClipRepository(database: manager)
        snippetRepository = SnippetRepository(database: manager)
        // §6.8.4: registered once per process — the app is its own process,
        // separate from the keyboard extension, so each registers its own copy.
        FontRegistrar.registerVazirmatn()
    }

    /// Every theme the picker/gallery can offer: built-ins plus whatever's
    /// in the App Group's `Themes/` directory.
    func availableThemes() -> [Theme] {
        builtInThemeCatalog.allThemes() + themeStore.listCustomThemes()
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
