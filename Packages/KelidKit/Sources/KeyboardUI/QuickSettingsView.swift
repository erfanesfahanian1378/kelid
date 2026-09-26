#if canImport(UIKit)
    import KelidCore
    import KelidSettings
    import SwiftUI

    /// Task 4.6's in-keyboard Quick Settings panel — a first version:
    /// everything that's meaningfully useful to reach without leaving the
    /// keyboard, plus a footer pointing at the full app. `KeyboardController`
    /// hands this a snapshot + a change callback; it never touches
    /// `SettingsStore` directly (only the host does, same pattern as the
    /// resize overlay).
    public struct QuickSettingsView: View {
        @State private var snapshot: QuickSettingsSnapshot
        /// §6.3.7: "'Reset size' is always reachable... in case a user makes
        /// the keyboard unusable" — the safe values `resetSize()` restores,
        /// computed by `KeyboardController` (device-class row height, no
        /// lift, one-handed off) the same way a fresh install would start.
        let resetSizeDefaults: QuickSettingsSnapshot
        let onChange: (QuickSettingsSnapshot) -> Void
        let onResizeVisually: () -> Void
        let onDone: () -> Void

        public init(
            snapshot: QuickSettingsSnapshot,
            resetSizeDefaults: QuickSettingsSnapshot,
            onChange: @escaping (QuickSettingsSnapshot) -> Void,
            onResizeVisually: @escaping () -> Void,
            onDone: @escaping () -> Void
        ) {
            _snapshot = State(initialValue: snapshot)
            self.resetSizeDefaults = resetSizeDefaults
            self.onChange = onChange
            self.onResizeVisually = onResizeVisually
            self.onDone = onDone
        }

        public var body: some View {
            NavigationStack {
                Form {
                    sizeSection
                    typingSection
                    languageSection
                    clipboardSection
                    Section {
                        Text("More settings in the Kelid app")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Quick Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
            }
            .onChange(of: snapshot) { _, newValue in onChange(newValue) }
        }

        private var sizeSection: some View {
            Section("Size") {
                LabeledContent("Row height: \(Int(snapshot.rowHeight.rounded()))pt") {
                    Slider(value: $snapshot.rowHeight, in: 30 ... 80)
                }
                LabeledContent("Lift: \(Int(snapshot.bottomLift.rounded()))") {
                    Slider(value: $snapshot.bottomLift, in: 0 ... 80)
                }
                Picker("One-handed", selection: $snapshot.oneHanded) {
                    Text("Off").tag(OneHandedMode.off)
                    Text("Left").tag(OneHandedMode.left)
                    Text("Right").tag(OneHandedMode.right)
                }
                if snapshot.oneHanded != .off {
                    LabeledContent("Width: \(Int((snapshot.oneHandedWidthRatio * 100).rounded()))%") {
                        Slider(value: $snapshot.oneHandedWidthRatio, in: 0.60 ... 0.95)
                    }
                }
                LabeledContent("Key gaps") {
                    Slider(value: $snapshot.keyGapH, in: 0 ... 14)
                }
                LabeledContent("Font scale: \(String(format: "%.1f×", snapshot.fontScale))") {
                    Slider(value: $snapshot.fontScale, in: 0.8 ... 1.4)
                }
                Toggle("Number row", isOn: $snapshot.showNumberRow)
                Button("Resize visually", action: onResizeVisually)
                Button("Reset size", role: .destructive, action: resetSize)
            }
        }

        /// Scoped to size fields only — this is the "keyboard became
        /// unusable" safety net (§6.3.7), not a general settings reset.
        private func resetSize() {
            snapshot.rowHeight = resetSizeDefaults.rowHeight
            snapshot.bottomLift = resetSizeDefaults.bottomLift
            snapshot.oneHanded = resetSizeDefaults.oneHanded
            snapshot.oneHandedWidthRatio = resetSizeDefaults.oneHandedWidthRatio
            snapshot.keyGapH = resetSizeDefaults.keyGapH
            snapshot.keyGapV = resetSizeDefaults.keyGapV
            snapshot.fontScale = resetSizeDefaults.fontScale
        }

        private var typingSection: some View {
            Section("Typing") {
                Toggle("Key popups", isOn: $snapshot.keyPopups)
                Picker("Sound", selection: $snapshot.sound) {
                    Text("Off").tag(SoundChoice.off)
                    Text("System").tag(SoundChoice.system)
                    Text("Soft").tag(SoundChoice.soft)
                    Text("Typewriter").tag(SoundChoice.typewriter)
                }
                Picker("Haptics", selection: $snapshot.haptics) {
                    Text("Off").tag(HapticsChoice.off)
                    Text("Light").tag(HapticsChoice.light)
                    Text("Medium").tag(HapticsChoice.medium)
                    Text("Rigid").tag(HapticsChoice.rigid)
                }
                Picker("Space trackpad", selection: $snapshot.spaceTrackpad) {
                    Text("Off").tag(SpaceTrackpadMode.off)
                    Text("Drag").tag(SpaceTrackpadMode.drag)
                    Text("Long press").tag(SpaceTrackpadMode.longPress)
                }
            }
        }

        private var languageSection: some View {
            Section("Language") {
                Toggle("Persian", isOn: languageBinding(.fa))
                Toggle("English", isOn: languageBinding(.en))
                Picker("Digits", selection: $snapshot.persianDigits) {
                    Text("۱۲۳ Persian").tag(PersianDigitsMode.persian)
                    Text("123 Latin").tag(PersianDigitsMode.latin)
                }
            }
        }

        /// Task 5.11.
        private var clipboardSection: some View {
            Section("Clipboard") {
                Toggle("Enabled", isOn: $snapshot.clipboardEnabled)
                if snapshot.clipboardEnabled {
                    Picker("Capture", selection: $snapshot.clipboardCaptureMode) {
                        Text("Automatic").tag(ClipboardCaptureMode.auto)
                        Text("On tap").tag(ClipboardCaptureMode.onTap)
                        Text("Off").tag(ClipboardCaptureMode.off)
                    }
                    Stepper("Max items: \(snapshot.clipboardMaxItems)", value: $snapshot.clipboardMaxItems, in: 20 ... 2000, step: 20)
                    Picker("Keep for", selection: retentionBinding) {
                        Text("1 day").tag(1)
                        Text("1 week").tag(7)
                        Text("1 month").tag(30)
                        Text("3 months").tag(90)
                        Text("Forever").tag(0)
                    }
                    Toggle("Show clip chip", isOn: $snapshot.clipboardShowChip)
                    Toggle("Skip sensitive items", isOn: $snapshot.clipboardSkipSensitive)
                    Toggle("Capture images", isOn: $snapshot.clipboardCaptureImages)
                }
            }
        }

        /// `retentionDays == nil` means "forever" — mapped to `0` for the
        /// picker's tag space, since `Picker` needs a non-optional `Hashable`
        /// selection.
        private var retentionBinding: Binding<Int> {
            Binding(
                get: { snapshot.clipboardRetentionDays ?? 0 },
                set: { snapshot.clipboardRetentionDays = $0 == 0 ? nil : $0 }
            )
        }

        /// At least one language must stay enabled — matches
        /// `GeneralSettings.clamped()`'s own rule, enforced here too so the
        /// UI never lets you turn the last one off in the first place.
        private func languageBinding(_ language: LanguageID) -> Binding<Bool> {
            Binding(
                get: { snapshot.enabledLanguages.contains(language) },
                set: { isOn in
                    if isOn {
                        guard !snapshot.enabledLanguages.contains(language) else { return }
                        snapshot.enabledLanguages.append(language)
                    } else {
                        guard snapshot.enabledLanguages.count > 1 else { return }
                        snapshot.enabledLanguages.removeAll { $0 == language }
                    }
                }
            )
        }
    }
#endif
