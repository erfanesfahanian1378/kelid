import KelidCore
import KelidSettings
import SwiftUI

/// §6.10's "Status detection": what the Home tab shows for the keyboard's
/// heartbeat (§6.11.5's `kb.heartbeat` / `kb.hasFullAccess`, written by
/// `KeyboardServices.writeHeartbeat()` on every keyboard appearance).
enum KeyboardStatus: Equatable {
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

/// Task 10.1/10.2: replaces Phase 0/1's placeholder shell — the temporary
/// "prove settings sync works" debug toggle is gone (a real `SettingsView`
/// now exists), replaced by §6.10's actual spec: status cards, "Set up" →
/// onboarding, a Try-it field, and 3 quick toggles.
///
/// Built from `GlassCard` panels over a soft gradient, not a plain `Form`,
/// so the app matches Apple's own Liquid Glass look by default — real user
/// feedback was that the app looked like a plain, dated list screen with no
/// visual identity of its own, and that shouldn't require picking a
/// *keyboard* theme to fix, since this is the app, not the keyboard.
struct HomeView: View {
    let services: AppServices

    @State private var tryItText = ""
    @State private var keyboardStatus: KeyboardStatus = .notDetected
    @State private var showingOnboarding = false

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Kelid").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)

                    statusCard
                    tryItCard
                    quickTogglesCard
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            while !Task.isCancelled {
                keyboardStatus = KeyboardStatus.current()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(onDone: { showingOnboarding = false })
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard status").font(.headline)
            Label(keyboardStatus.label, systemImage: keyboardStatus.systemImage)
            if keyboardStatus != .active {
                Button("Set up") { showingOnboarding = true }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var tryItCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it").font(.headline)
            TextEditor(text: $tryItText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// §6.10: "Quick toggles: prediction source, incognito, clipboard
    /// capture" — the current typing language's own prediction source
    /// (matching how the keyboard's own Quick Settings panel scopes it).
    private var quickTogglesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick toggles").font(.headline)
            Picker("Predictions (Persian)", selection: predictionSourceBinding(.fa)) {
                Text("Off").tag(PredictionSource.off)
                Text("Personal only").tag(PredictionSource.personalOnly)
                Text("Language only").tag(PredictionSource.languageOnly)
                Text("Both (hybrid)").tag(PredictionSource.hybrid)
            }
            Picker("Predictions (English)", selection: predictionSourceBinding(.en)) {
                Text("Off").tag(PredictionSource.off)
                Text("Personal only").tag(PredictionSource.personalOnly)
                Text("Language only").tag(PredictionSource.languageOnly)
                Text("Both (hybrid)").tag(PredictionSource.hybrid)
            }
            Toggle("Incognito", isOn: incognitoBinding)
            Toggle("Clipboard capture", isOn: clipboardEnabledBinding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func predictionSourceBinding(_ language: LanguageID) -> Binding<PredictionSource> {
        Binding(
            get: { services.settings.settings.prediction[language].source },
            set: { newValue in services.settings.update { $0.prediction.setSettings(for: language) { $0.source = newValue } } }
        )
    }

    private var incognitoBinding: Binding<Bool> {
        Binding(
            get: { services.settings.settings.learning.incognito },
            set: { newValue in services.settings.update { $0.learning.incognito = newValue } }
        )
    }

    private var clipboardEnabledBinding: Binding<Bool> {
        Binding(
            get: { services.settings.settings.clipboard.enabled },
            set: { newValue in services.settings.update { $0.clipboard.enabled = newValue } }
        )
    }
}
