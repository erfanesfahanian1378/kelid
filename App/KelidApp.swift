import KelidCore
import SwiftUI

/// Phase 0 placeholder app.
///
/// A minimal shell: setup steps, an "Open Settings" shortcut, and a "Try it"
/// field to test the keyboard. Onboarding, status checks and every real
/// settings screen (PLAN.md §6.10) arrive from Phase 10 onward.
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
    /// keyboard extension's status line (Keyboard/KeyboardViewController)
    /// can show whether it can read the App Group (only true with Full
    /// Access on — §2.1 C2).
    private static func writeAppGroupProbe() {
        guard let groupID = Bundle.main.object(forInfoDictionaryKey: "KelidAppGroupID") as? String else {
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
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
        }
    }
}

private struct HomeView: View {
    @State private var tryItText = ""

    private let setupSteps = [
        "Settings → General → Keyboard → Keyboards → Add New Keyboard → Kelid",
        "Tap Kelid in the keyboards list, then turn on Allow Full Access",
        "Switch to Kelid in any text field using the 🌐 key",
    ]

    var body: some View {
        NavigationStack {
            Form {
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
            }
            .navigationTitle("Kelid")
        }
    }
}
