import KelidSettings
import SwiftUI

/// Task 10.3: §6.1.6's learning settings.
struct LearningSettingsView: View {
    let services: AppServices

    var body: some View {
        Form {
            Section {
                Toggle("Learn from typing", isOn: bind(\.learning.enabled))
                Toggle("Incognito", isOn: bind(\.learning.incognito))
            }
            Section("How it learns") {
                Toggle("Learn 2- and 3-word phrases", isOn: bind(\.learning.learnPhrases))
                Stepper(
                    "New-word threshold: \(services.settings.settings.learning.newWordThreshold)",
                    value: bind(\.learning.newWordThreshold), in: 1 ... 5
                )
                Stepper(
                    "Forget after: \(services.settings.settings.learning.halfLifeDays) days (half-life)",
                    value: bind(\.learning.halfLifeDays), in: 7 ... 365, step: 7
                )
                Stepper(
                    "Max learned words: \(services.settings.settings.learning.maxUserWords)",
                    value: bind(\.learning.maxUserWords), in: 5000 ... 200_000, step: 5000
                )
            }
            Section("Sources") {
                Toggle("Use text replacements", isOn: bind(\.learning.useTextReplacements))
                Toggle("Use contact names", isOn: bind(\.learning.useContactNames))
            }
        }
        .navigationTitle("Learning")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
