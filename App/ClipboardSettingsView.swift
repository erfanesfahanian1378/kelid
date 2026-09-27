import KelidSettings
import SwiftUI

/// Task 10.4/10.3: §6.1.7's clipboard settings, including the
/// `ignorePatterns` editor with a live test field.
struct ClipboardSettingsView: View {
    let services: AppServices
    @State private var testText = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: bind(\.enabled))
            }
            if services.settings.settings.clipboard.enabled {
                Section("Capture") {
                    Picker("Capture mode", selection: bind(\.captureMode)) {
                        Text("Automatic").tag(ClipboardCaptureMode.auto)
                        Text("On tap").tag(ClipboardCaptureMode.onTap)
                        Text("Off").tag(ClipboardCaptureMode.off)
                    }
                    Toggle("Capture images", isOn: bind(\.captureImages))
                    Toggle("Smart spacing on insert", isOn: bind(\.smartSpacing))
                }
                Section("Limits") {
                    Stepper(
                        "Max items: \(services.settings.settings.clipboard.maxItems)", value: bind(\.maxItems), in: 20 ... 2000, step: 20
                    )
                    Picker("Keep for", selection: retentionBinding) {
                        Text("1 day").tag(1)
                        Text("1 week").tag(7)
                        Text("1 month").tag(30)
                        Text("3 months").tag(90)
                        Text("Forever").tag(0)
                    }
                }
                Section("Suggestion bar") {
                    Toggle("Show clip chip", isOn: bind(\.showChip))
                    Stepper(
                        "Chip visible for: \(services.settings.settings.clipboard.chipSeconds)s", value: bind(\.chipSeconds),
                        in: 15 ... 600, step: 15
                    )
                    Picker("Tap action", selection: bind(\.tapAction)) {
                        Text("Insert").tag(ClipboardTapAction.insert)
                        Text("Insert and close").tag(ClipboardTapAction.insertAndClose)
                        Text("Copy").tag(ClipboardTapAction.copy)
                    }
                }
                Section("Privacy") {
                    Toggle("Skip sensitive fields", isOn: bind(\.skipSensitive))
                    Toggle("Mask password-like text", isOn: bind(\.maskPasswordLike))
                    Picker("One-time codes", selection: bind(\.otpHandling)) {
                        Text("Skip").tag(OTPHandling.skip)
                        Text("Expire quickly").tag(OTPHandling.expire)
                        Text("Keep").tag(OTPHandling.keep)
                    }
                    Toggle("Lock with Face ID", isOn: bind(\.lockWithFaceID))
                }
                ignorePatternsSection
            }
        }
        .navigationTitle("Clipboard Settings")
    }

    private var ignorePatternsSection: some View {
        Section {
            ForEach(Array(services.settings.settings.clipboard.ignorePatterns.indices), id: \.self) { index in
                TextField("Pattern", text: patternBinding(at: index))
                    .font(.system(.body, design: .monospaced))
            }
            .onDelete { indices in
                services.settings.update { $0.clipboard.ignorePatterns.remove(atOffsets: indices) }
            }
            Button("Add pattern…") {
                services.settings.update { $0.clipboard.ignorePatterns.append("") }
            }
            TextField("Test text against your patterns", text: $testText)
            if !testText.isEmpty {
                Label(testResultLabel, systemImage: matchesAnyPattern ? "eye.slash" : "eye")
                    .foregroundStyle(matchesAnyPattern ? .orange : .secondary)
            }
        } header: {
            Text("Ignore patterns")
        } footer: {
            Text("Regular expressions. Clips matching any pattern are never stored. Try one against the test field above.")
        }
    }

    private func patternBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                let patterns = services.settings.settings.clipboard.ignorePatterns
                return index < patterns.count ? patterns[index] : ""
            },
            set: { newValue in
                services.settings.update { settings in
                    guard index < settings.clipboard.ignorePatterns.count else { return }
                    settings.clipboard.ignorePatterns[index] = newValue
                }
            }
        )
    }

    private var testResultLabel: String {
        matchesAnyPattern ? "Would be ignored (matches a pattern)" : "Would be stored (matches no pattern)"
    }

    private var matchesAnyPattern: Bool {
        services.settings.settings.clipboard.ignorePatterns.contains { pattern in
            guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(testText.startIndex ..< testText.endIndex, in: testText)
            return regex.firstMatch(in: testText, range: range) != nil
        }
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { services.settings.settings.clipboard.retentionDays ?? 0 },
            set: { newValue in services.settings.update { $0.clipboard.retentionDays = newValue == 0 ? nil : newValue } }
        )
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KelidSettings.ClipboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings.clipboard[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0.clipboard[keyPath: keyPath] = newValue } }
        )
    }
}
