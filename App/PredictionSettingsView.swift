import KelidCore
import KelidSettings
import SwiftUI

/// Task 10.3: §6.1.5's full per-language prediction settings — a superset
/// of what the keyboard's own Quick Settings panel exposes (task 7.11),
/// since the app has room for every field, not just the most-reached-for
/// ones.
struct PredictionSettingsListView: View {
    let services: AppServices

    var body: some View {
        List {
            NavigationLink("Persian") { PredictionSettingsView(services: services, language: .fa) }
            NavigationLink("English") { PredictionSettingsView(services: services, language: .en) }
        }
        .navigationTitle("Prediction")
    }
}

private struct PredictionSettingsView: View {
    let services: AppServices
    let language: LanguageID

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: bind(\.enabled))
            }
            if services.settings.settings.prediction[language].enabled {
                Section("Source") {
                    Picker("Predictions from", selection: bind(\.source)) {
                        Text("Off").tag(PredictionSource.off)
                        Text("Personal only").tag(PredictionSource.personalOnly)
                        Text("Language only").tag(PredictionSource.languageOnly)
                        Text("Both (hybrid)").tag(PredictionSource.hybrid)
                    }
                    if services.settings.settings.prediction[language].source == .hybrid {
                        LabeledContent(
                            "Personal weight: \(Int((services.settings.settings.prediction[language].personalWeight * 100).rounded()))%"
                        ) {
                            Slider(value: bind(\.personalWeight), in: 0 ... 1)
                        }
                    }
                }
                Section("Suggestions") {
                    Toggle("Next-word prediction", isOn: bind(\.nextWord))
                    Stepper(
                        "Shown: \(services.settings.settings.prediction[language].suggestionCount)",
                        value: bind(\.suggestionCount), in: 3 ... 5
                    )
                    Toggle("Show what you typed", isOn: bind(\.showVerbatimSlot))
                    if language == .fa {
                        Toggle("Prefer نیم\u{200C}فاصله spellings", isOn: bind(\.preferZWNJForms))
                    }
                    Toggle("Block offensive words", isOn: bind(\.blockOffensive))
                }
                Section("Autocorrect") {
                    Picker("Autocorrect", selection: bind(\.autocorrect)) {
                        Text("Off").tag(AutocorrectMode.off)
                        Text("Suggest only").tag(AutocorrectMode.suggestOnly)
                        Text("Automatic").tag(AutocorrectMode.auto)
                    }
                    if services.settings.settings.prediction[language].autocorrect != .off {
                        LabeledContent(
                            "Strength: \(String(format: "%.1f", services.settings.settings.prediction[language].autocorrectStrength))"
                        ) {
                            Slider(value: bind(\.autocorrectStrength), in: 0 ... 1)
                        }
                    }
                }
                Section("Emoji") {
                    Toggle("Emoji suggestions", isOn: bind(\.emojiSuggestions))
                }
            }
        }
        .navigationTitle(language == .fa ? "Persian" : "English")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<PredictionSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings.prediction[language][keyPath: keyPath] },
            set: { newValue in services.settings.update { $0.prediction.setSettings(for: language) { $0[keyPath: keyPath] = newValue } } }
        )
    }
}
