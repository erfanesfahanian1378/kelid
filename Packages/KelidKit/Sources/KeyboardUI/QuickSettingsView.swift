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
        /// Task 9.7: reflects `KeyboardState.incognito` — bound directly to
        /// the controller's own toggle rather than round-tripping through
        /// `snapshot`/`onChange`, since incognito is session state mirrored
        /// into (not read from) `settings.learning.incognito` (see
        /// `QuickSettingsSnapshot`'s own doc comment on why it's excluded).
        @State private var incognito: Bool
        let onToggleIncognito: () -> Void
        /// Task 9.8's "Clear my learned words for this language" — a
        /// destructive action, not a settings field, so it's a callback too.
        let onClearLearnedWords: () -> Void
        @State private var showingClearConfirmation = false
        /// Task 9.10's "still learning" hint threshold — `nil` until
        /// `KeyboardController` has actually asked `SuggestionService` for
        /// the count (an async round trip this view can't make itself).
        let personalWordCount: Int?

        public init(
            snapshot: QuickSettingsSnapshot,
            resetSizeDefaults: QuickSettingsSnapshot,
            incognito: Bool,
            personalWordCount: Int?,
            onChange: @escaping (QuickSettingsSnapshot) -> Void,
            onResizeVisually: @escaping () -> Void,
            onToggleIncognito: @escaping () -> Void,
            onClearLearnedWords: @escaping () -> Void,
            onDone: @escaping () -> Void
        ) {
            _snapshot = State(initialValue: snapshot)
            self.resetSizeDefaults = resetSizeDefaults
            _incognito = State(initialValue: incognito)
            self.personalWordCount = personalWordCount
            self.onChange = onChange
            self.onResizeVisually = onResizeVisually
            self.onToggleIncognito = onToggleIncognito
            self.onClearLearnedWords = onClearLearnedWords
            self.onDone = onDone
        }

        public var body: some View {
            NavigationStack {
                Form {
                    sizeSection
                    typingSection
                    languageSection
                    predictionSection
                    learningSection
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
        /// Task 7.11 — controls the *current typing language's*
        /// `PredictionSettings` (`snapshot.predictionLanguage`, set by
        /// `KeyboardController` to `state.language` when it builds this
        /// snapshot); `toolbarMode` is the one field here that isn't
        /// per-language.
        private var predictionSection: some View {
            Section("Suggestions (\(snapshot.predictionLanguage == .fa ? "Persian" : "English"))") {
                Toggle("Enabled", isOn: $snapshot.predictionEnabled)
                if snapshot.predictionEnabled {
                    Stepper(
                        "Suggestions shown: \(snapshot.predictionSuggestionCount)",
                        value: $snapshot.predictionSuggestionCount,
                        in: 3 ... 5
                    )
                    Toggle("Show what you typed", isOn: $snapshot.predictionShowVerbatimSlot)
                    if snapshot.predictionLanguage == .fa {
                        Toggle("Prefer نیم\u{200C}فاصله spellings", isOn: $snapshot.predictionPreferZWNJForms)
                    }
                    // Task 9.8: source picker + personal-weight slider
                    // (hybrid only), per §6.7.7's own 4 modes.
                    Picker("Predictions from", selection: $snapshot.predictionSource) {
                        Text("Off").tag(PredictionSource.off)
                        Text("Personal only").tag(PredictionSource.personalOnly)
                        Text("Language only").tag(PredictionSource.languageOnly)
                        Text("Both (hybrid)").tag(PredictionSource.hybrid)
                    }
                    if snapshot.predictionSource == .hybrid {
                        LabeledContent("Personal weight: \(Int((snapshot.predictionPersonalWeight * 100).rounded()))%") {
                            Slider(value: $snapshot.predictionPersonalWeight, in: 0 ... 1)
                        }
                    }
                    // Task 9.10: only meaningful once personal words can
                    // actually show up in the result (not `.languageOnly`).
                    if snapshot.predictionSource != .languageOnly, snapshot.predictionSource != .off,
                       let personalWordCount, personalWordCount < 200
                    {
                        Text("Still learning your words (\(personalWordCount)/200) — suggestions will improve as you type.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Toolbar shows", selection: $snapshot.toolbarMode) {
                    Text("Suggestions, then icons").tag(ToolbarMode.auto)
                    Text("Suggestions only").tag(ToolbarMode.suggestionsOnly)
                    Text("Icons only").tag(ToolbarMode.iconsOnly)
                    Text("Hidden").tag(ToolbarMode.hidden)
                }
            }
        }

        /// Task 9.8: learning on/off, incognito, and the destructive
        /// "clear learned words" action — grouped separately from
        /// `predictionSection` since these apply regardless of source mode
        /// (even `.languageOnly` still *records* commits unless learning
        /// itself is off, per §6.7.7's own "learning continues" note for
        /// `.off` source — the two are independent switches).
        private var learningSection: some View {
            Section("Learning (\(snapshot.predictionLanguage == .fa ? "Persian" : "English"))") {
                Toggle("Learn from typing", isOn: $snapshot.learningEnabled)
                Toggle("Incognito", isOn: incognitoBinding)
                Button("Clear my learned words", role: .destructive) {
                    showingClearConfirmation = true
                }
                .confirmationDialog(
                    "Clear all learned words for \(snapshot.predictionLanguage == .fa ? "Persian" : "English")?",
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear", role: .destructive, action: onClearLearnedWords)
                    Button("Cancel", role: .cancel) {}
                }
            }
        }

        /// `incognito` isn't part of `snapshot`/`onChange` (see the doc
        /// comment on the `incognito` property) — toggling it calls
        /// `onToggleIncognito()` directly, then mirrors the new value into
        /// this view's own `@State` so the switch itself animates correctly.
        private var incognitoBinding: Binding<Bool> {
            Binding(
                get: { incognito },
                set: { _ in
                    incognito.toggle()
                    onToggleIncognito()
                }
            )
        }

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
