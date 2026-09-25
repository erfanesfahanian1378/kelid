import KelidCore
import KelidSettings
import SwiftUI

/// Companion app.
///
/// Phase 0's placeholder shell (setup steps, "Open Settings", "Try it")
/// gains, in Phase 1: a heartbeat-based keyboard status card (§6.10, task
/// 1.7) and a temporary debug toggle proving settings sync actually works
/// end-to-end (task 1.9) — a real settings screen replaces it in Phase 10.
@main
struct KelidApp: App {
    private static let log = Log.logger(.app)

    init() {
        Log.configure(bundleID: Bundle.main.bundleIdentifier)
        Self.writeAppGroupProbe()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }

    /// Writes `app.probe` to the shared App Group `UserDefaults` so the
    /// keyboard extension's diagnostics line can show whether it can read
    /// the App Group (only true with Full Access on — §2.1 C2).
    private static func writeAppGroupProbe() {
        guard let groupID = AppGroup.identifier else {
            log.error("KelidAppGroupID missing from Info.plist")
            return
        }
        guard let defaults = UserDefaults(suiteName: groupID) else {
            log.error("could not open App Group UserDefaults suite \(groupID, privacy: .public)")
            return
        }
        defaults.set(Date(), forKey: "app.probe")
    }
}

private struct RootTabView: View {
    @State private var settingsStore = SettingsStore()

    var body: some View {
        TabView {
            HomeView(settingsStore: settingsStore)
                .tabItem { Label("Home", systemImage: "house") }
        }
    }
}

/// §6.10 "Status detection": what the Home tab shows for the keyboard's
/// heartbeat (§6.11.5's `kb.heartbeat` / `kb.hasFullAccess`, written by
/// `KeyboardServices.writeHeartbeat()` on every keyboard appearance).
private enum KeyboardStatus {
    case active
    case fullAccessOff
    case notDetected

    var label: String {
        switch self {
        case .active: "Keyboard active, Full Access ✓"
        case .fullAccessOff: "Enabled, Full Access off?"
        case .notDetected: "Not detected"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "checkmark.circle.fill"
        case .fullAccessOff: "exclamationmark.triangle.fill"
        case .notDetected: "questionmark.circle"
        }
    }

    static func current() -> KeyboardStatus {
        guard let groupID = AppGroup.identifier,
              let defaults = UserDefaults(suiteName: groupID),
              let heartbeat = defaults.object(forKey: "kb.heartbeat") as? Date
        else {
            return .notDetected
        }
        let withinSevenDays = Date().timeIntervalSince(heartbeat) < 7 * 24 * 3600
        guard withinSevenDays else { return .notDetected }
        return defaults.bool(forKey: "kb.hasFullAccess") ? .active : .fullAccessOff
    }
}

private struct HomeView: View {
    let settingsStore: SettingsStore

    @State private var tryItText = ""
    @State private var keyboardStatus: KeyboardStatus = .notDetected

    private let setupSteps = [
        "Settings → General → Keyboard → Keyboards → Add New Keyboard → Kelid",
        "Tap Kelid in the keyboards list, then turn on Allow Full Access",
        "Switch to Kelid in any text field using the 🌐 key",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard status") {
                    Label(keyboardStatus.label, systemImage: keyboardStatus.systemImage)
                }
                Section("Setup") {
                    ForEach(Array(setupSteps.enumerated()), id: \.offset) { index, step in
                        Label(step, systemImage: "\(index + 1).circle")
                    }
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section("Try it") {
                    TextEditor(text: $tryItText)
                        .frame(minHeight: 120)
                }
                Section {
                    Toggle("Key popups (debug: proves live settings sync)", isOn: keyPopupsBinding)
                } footer: {
                    Text(
                        "Temporary control for Phase 1 — a real Settings tab replaces this in Phase 10. "
                            + "Flip it while the keyboard is shown in Try It above; its diagnostics line should update within a second."
                    )
                }
            }
            .navigationTitle("Kelid")
            .task {
                while !Task.isCancelled {
                    keyboardStatus = KeyboardStatus.current()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private var keyPopupsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.general.keyPopups },
            set: { newValue in settingsStore.update { $0.general.keyPopups = newValue } }
        )
    }
}
