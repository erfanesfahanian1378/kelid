import KelidCore
import KelidSettings
import SwiftUI

/// Companion app entry point (task 10.1). `AppServices` replaces the
/// Phase 0/1 placeholder's bare `SettingsStore` — it now also owns the
/// database and the clip/snippet repositories every tab needs.
@main
struct KelidApp: App {
    @State private var services = AppServices()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.configure(bundleID: Bundle.main.bundleIdentifier)
        Self.writeAppGroupProbe()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(services: services)
                .task { await services.start() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            services.handleScenePhaseChange(isActive: newPhase == .active)
        }
    }

    /// Writes `app.probe` to the shared App Group `UserDefaults` so the
    /// keyboard extension's diagnostics line can show whether it can read
    /// the App Group (only true with Full Access on — §2.1 C2).
    private static func writeAppGroupProbe() {
        guard let groupID = AppGroup.identifier else {
            Log.logger(.app).error("KelidAppGroupID missing from Info.plist")
            return
        }
        guard let defaults = UserDefaults(suiteName: groupID) else {
            Log.logger(.app).error("could not open App Group UserDefaults suite \(groupID, privacy: .public)")
            return
        }
        defaults.set(Date(), forKey: "app.probe")
    }
}
