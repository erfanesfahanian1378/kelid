import KelidCore
import KelidSettings
import KeyboardLayout
import KeyboardUI
import SwiftUI
import UIKit

/// Task 4.7's Settings → Size & Layout screen: the same controls as the
/// in-keyboard Quick Settings panel (task 4.6), plus a live `KeyboardPreview`
/// that re-renders the *real* key grid as sliders move, and a
/// portrait/landscape picker. Reads/writes the same `SettingsStore` the
/// keyboard extension uses, so a change here reaches the keyboard the
/// normal way (shared App Group blob, or local mirror without Full Access).
struct SizeLayoutView: View {
    let settingsStore: SettingsStore

    @State private var orientation: SizeOrientation = .portrait
    @State private var snapshot: QuickSettingsSnapshot

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        _snapshot = State(initialValue: QuickSettingsSnapshot(settings: settingsStore.settings, orientation: .portrait))
    }

    var body: some View {
        Form {
            Section {
                Picker("Orientation", selection: $orientation) {
                    Text("Portrait").tag(SizeOrientation.portrait)
                    Text("Landscape").tag(SizeOrientation.landscape)
                }
                .pickerStyle(.segmented)
                KeyboardPreviewView(profile: previewProfile, language: .fa)
                    .frame(height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            }

            Section("Size") {
                LabeledContent("Row height: \(Int(snapshot.rowHeight.rounded()))pt") {
                    Slider(value: $snapshot.rowHeight, in: rowHeightRange)
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
                Button("Reset size", role: .destructive, action: resetSize)
            }

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

            Section("Language") {
                Toggle("Persian", isOn: languageBinding(.fa))
                Toggle("English", isOn: languageBinding(.en))
                Picker("Digits", selection: $snapshot.persianDigits) {
                    Text("۱۲۳ Persian").tag(PersianDigitsMode.persian)
                    Text("123 Latin").tag(PersianDigitsMode.latin)
                }
            }
        }
        .navigationTitle("Size & Layout")
        .onChange(of: orientation) { _, newOrientation in
            snapshot = QuickSettingsSnapshot(settings: settingsStore.settings, orientation: newOrientation)
        }
        .onChange(of: snapshot) { _, newValue in
            settingsStore.update { newValue.apply(to: &$0, orientation: orientation) }
        }
    }

    /// Built straight from the live `snapshot`, not from `settingsStore`
    /// (which only updates after `onChange` persists) — this is what makes
    /// the preview track slider drags immediately.
    private var previewProfile: SizeProfile {
        var profile: SizeProfile = orientation == .portrait ? .portraitDefault : .landscapeDefault
        profile.rowHeight = snapshot.rowHeight
        profile.bottomLift = snapshot.bottomLift
        profile.oneHanded = snapshot.oneHanded
        profile.oneHandedWidthRatio = snapshot.oneHandedWidthRatio
        profile.keyGapH = snapshot.keyGapH
        profile.keyGapV = snapshot.keyGapV
        profile.fontScale = snapshot.fontScale
        return profile
    }

    private var previewHeight: CGFloat {
        let rowCount = snapshot.showNumberRow ? 5 : 4
        return HeightCoordinator.totalHeight(
            rowCount: rowCount, metrics: KeyboardMetrics(sizeProfile: previewProfile), toolbarVisible: false
        )
    }

    private var rowHeightRange: ClosedRange<CGFloat> {
        orientation == .portrait ? 38 ... 80 : 30 ... 60
    }

    private func resetSize() {
        var defaults: SizeProfile = orientation == .portrait ? .portraitDefault : .landscapeDefault
        if orientation == .portrait {
            let screenHeight = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            defaults.rowHeight = DeviceSizeClass.portraitRowHeightDefault(screenHeight: screenHeight)
        }
        snapshot.rowHeight = defaults.rowHeight
        snapshot.bottomLift = defaults.bottomLift
        snapshot.oneHanded = defaults.oneHanded
        snapshot.oneHandedWidthRatio = defaults.oneHandedWidthRatio
        snapshot.keyGapH = defaults.keyGapH
        snapshot.keyGapV = defaults.keyGapV
        snapshot.fontScale = defaults.fontScale
    }

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
