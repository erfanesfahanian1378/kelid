import KelidCore
import KelidSettings
import KeyboardUI
import SwiftUI

/// Task 10.3: every key in §6.1, grouped the same way §6.1 itself groups
/// them — each section links to its own screen rather than one giant Form,
/// since several groups (prediction, learning) are large and/or
/// per-language.
struct SettingsView: View {
    let services: AppServices

    var body: some View {
        List {
            Section {
                NavigationLink("General") { GeneralSettingsView(services: services) }
                NavigationLink("Size & Layout") { SizeLayoutView(settingsStore: services.settings) }
                NavigationLink("Toolbar") { ToolbarSettingsView(services: services) }
            }
            Section {
                NavigationLink("Prediction") { PredictionSettingsListView(services: services) }
                NavigationLink("Learning") { LearningSettingsView(services: services) }
            }
            Section {
                NavigationLink("Appearance") { AppearanceSettingsView(services: services) }
                NavigationLink("Emoji") { EmojiSettingsView(services: services) }
                NavigationLink("Snippets") { SnippetsSettingsView(services: services) }
            }
            Section {
                NavigationLink("Shortcuts & Back Tap") { BackTapGuideView() }
                NavigationLink("Advanced") { AdvancedSettingsView(services: services) }
                NavigationLink("About") { AboutView() }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    let services: AppServices

    var body: some View {
        Form {
            Section("Languages") {
                Toggle("Persian", isOn: languageBinding(.fa))
                Toggle("English", isOn: languageBinding(.en))
                Picker("Switch languages with", selection: bind(\.general.languageSwitch)) {
                    Text("Language key").tag(LanguageSwitchMode.key)
                    Text("Swipe space").tag(LanguageSwitchMode.spaceSwipe)
                    Text("Both").tag(LanguageSwitchMode.both)
                }
                Toggle("Remember last language", isOn: bind(\.general.rememberLastLanguage))
            }
            Section("Layout") {
                Picker("Persian layout", selection: bind(\.general.persianLayout)) {
                    Text("Standard").tag(PersianLayoutID.standard)
                    Text("Compact").tag(PersianLayoutID.compact)
                    Text("Standard (4-row)").tag(PersianLayoutID.standard4Row)
                }
                Toggle("Number row", isOn: bind(\.general.showNumberRow))
                Toggle("Bottom-row emoji key", isOn: bind(\.general.bottomRowEmojiKey))
            }
            Section("Digits") {
                Picker("Persian digits", selection: bind(\.general.persianDigits)) {
                    Text("۱۲۳ Persian").tag(PersianDigitsMode.persian)
                    Text("123 Latin").tag(PersianDigitsMode.latin)
                }
                Picker("Number pad digits", selection: bind(\.general.numpadDigits)) {
                    Text("123 Latin").tag(NumpadDigitsMode.latin)
                    Text("۱۲۳ Persian").tag(NumpadDigitsMode.persian)
                }
            }
            Section("Typing feel") {
                Toggle("Key popups", isOn: bind(\.general.keyPopups))
                Toggle("Key hints", isOn: bind(\.general.keyHints))
                Toggle("Double-space for period", isOn: bind(\.general.doubleSpacePeriod))
                Toggle("Auto-capitalize", isOn: bind(\.general.autoCapitalize))
                Toggle("Smart punctuation spacing", isOn: bind(\.general.smartPunctuationSpacing))
                Toggle("RTL visual cursor", isOn: bind(\.general.rtlVisualCursor))
                Stepper(
                    "Long-press delay: \(services.settings.settings.general.longPressDelayMs)ms",
                    value: bind(\.general.longPressDelayMs), in: 200 ... 800, step: 25
                )
                LabeledContent("Cursor speed: \(String(format: "%.1f×", services.settings.settings.general.cursorSpeed))") {
                    Slider(value: bind(\.general.cursorSpeed), in: 0.5 ... 2.0)
                }
            }
            Section("Space and backspace") {
                Picker("Space trackpad", selection: bind(\.general.spaceTrackpad)) {
                    Text("Off").tag(SpaceTrackpadMode.off)
                    Text("Drag").tag(SpaceTrackpadMode.drag)
                    Text("Long press").tag(SpaceTrackpadMode.longPress)
                }
                Toggle("Backspace swipe deletes words", isOn: bind(\.general.backspaceSwipeDeletesWords))
                Picker("Backspace repeat speed", selection: bind(\.general.backspaceRepeat)) {
                    Text("Slow").tag(BackspaceRepeatSpeed.slow)
                    Text("Normal").tag(BackspaceRepeatSpeed.normal)
                    Text("Fast").tag(BackspaceRepeatSpeed.fast)
                }
            }
        }
        .navigationTitle("General")
    }

    private func languageBinding(_ language: LanguageID) -> Binding<Bool> {
        Binding(
            get: { services.settings.settings.general.enabledLanguages.contains(language) },
            set: { isOn in
                services.settings.update { settings in
                    if isOn {
                        guard !settings.general.enabledLanguages.contains(language) else { return }
                        settings.general.enabledLanguages.append(language)
                    } else {
                        guard settings.general.enabledLanguages.count > 1 else { return }
                        settings.general.enabledLanguages.removeAll { $0 == language }
                    }
                }
            }
        )
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

// MARK: - Toolbar

private struct ToolbarSettingsView: View {
    let services: AppServices

    var body: some View {
        Form {
            Picker("Toolbar shows", selection: bind(\.toolbar.mode)) {
                Text("Suggestions, then icons").tag(ToolbarMode.auto)
                Text("Suggestions only").tag(ToolbarMode.suggestionsOnly)
                Text("Icons only").tag(ToolbarMode.iconsOnly)
                Text("Hidden").tag(ToolbarMode.hidden)
            }
        }
        .navigationTitle("Toolbar")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    let services: AppServices

    var body: some View {
        Form {
            Section {
                KeyboardPreviewView(profile: services.settings.sizeProfile(for: .portrait), language: .fa)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            }
            Section("Theme") {
                Picker("Mode", selection: bind(\.appearance.themeMode)) {
                    Text("Fixed").tag(ThemeMode.fixed)
                    Text("Follow system").tag(ThemeMode.followSystem)
                    Text("Follow app").tag(ThemeMode.followApp)
                }
            }
            Section("Fonts") {
                Picker("Persian font", selection: bind(\.appearance.persianFont)) {
                    Text("System").tag(PersianFontChoice.system)
                    Text("Vazirmatn").tag(PersianFontChoice.vazirmatn)
                }
                Picker("Latin font", selection: bind(\.appearance.latinFont)) {
                    Text("System").tag(LatinFontChoice.system)
                    Text("Rounded").tag(LatinFontChoice.rounded)
                    Text("Monospaced").tag(LatinFontChoice.monospaced)
                }
            }
            Section("Feedback") {
                Picker("Key-press animation", selection: bind(\.appearance.keyPressAnimation)) {
                    Text("None").tag(KeyPressAnimation.none)
                    Text("Pop").tag(KeyPressAnimation.pop)
                    Text("Fade").tag(KeyPressAnimation.fade)
                }
                Picker("Sound", selection: bind(\.appearance.sound)) {
                    Text("Off").tag(SoundChoice.off)
                    Text("System").tag(SoundChoice.system)
                    Text("Soft").tag(SoundChoice.soft)
                    Text("Typewriter").tag(SoundChoice.typewriter)
                }
                Picker("Haptics", selection: bind(\.appearance.haptics)) {
                    Text("Off").tag(HapticsChoice.off)
                    Text("Light").tag(HapticsChoice.light)
                    Text("Medium").tag(HapticsChoice.medium)
                    Text("Rigid").tag(HapticsChoice.rigid)
                }
                Toggle("Reduce haptics in Low Power Mode", isOn: bind(\.appearance.reduceHapticsInLowPower))
            }
        }
        .navigationTitle("Appearance")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

// MARK: - Emoji

private struct EmojiSettingsView: View {
    let services: AppServices

    var body: some View {
        Form {
            Picker("Default skin tone", selection: bind(\.emoji.defaultSkinTone)) {
                Text("None").tag(SkinTone.none)
                Text("Light").tag(SkinTone.light)
                Text("Medium-light").tag(SkinTone.mediumLight)
                Text("Medium").tag(SkinTone.medium)
                Text("Medium-dark").tag(SkinTone.mediumDark)
                Text("Dark").tag(SkinTone.dark)
            }
            Stepper(
                "Recents limit: \(services.settings.settings.emoji.recentsLimit)",
                value: bind(\.emoji.recentsLimit), in: 16 ... 64, step: 8
            )
        }
        .navigationTitle("Emoji")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

// MARK: - Snippets (settings only — folder/snippet CRUD lives in the Clipboard tab)

private struct SnippetsSettingsView: View {
    let services: AppServices

    var body: some View {
        Form {
            Toggle("Expand shortcuts as you type", isOn: bind(\.snippets.expansionEnabled))
        }
        .navigationTitle("Snippets")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<KeyboardSettings, T>) -> Binding<T> {
        Binding(
            get: { services.settings.settings[keyPath: keyPath] },
            set: { newValue in services.settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
