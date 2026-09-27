#if canImport(UIKit)
    import KelidSettings
    import ThemeKit

    /// Quick Settings (task 4.6) — split out of `KeyboardController.swift`
    /// itself purely to keep that type's body under SwiftLint's
    /// `type_body_length`; behaviorally this is still part of
    /// `KeyboardController`, just declared in a second file.
    public extension KeyboardController {
        func toggleQuickSettings() {
            if state.mode == .quickSettings {
                dismissQuickSettings()
            } else {
                state.mode = .quickSettings
                let currentSnapshot = QuickSettingsSnapshot(settings: settings, orientation: currentOrientation, language: state.language)
                let resetDefaults = QuickSettingsSnapshot.deviceDefaults(
                    orientation: currentOrientation, deviceDefaultRowHeight: deviceDefaultRowHeight
                )
                let incognito = state.incognito
                let language = state.language
                let availableThemes = builtInThemeCatalog.allThemes() + themeStore.listCustomThemes()
                // Task 9.10: the personal-word count is an async round trip
                // to `SuggestionService` — the panel opens once it's ready
                // rather than presenting with a stale/placeholder count.
                Task { [weak self, suggestionService] in
                    let count = await suggestionService.personalWordCount(for: language)
                    self?.onPresentQuickSettings?(currentSnapshot, resetDefaults, incognito, count, availableThemes)
                }
            }
        }

        internal func dismissQuickSettings() {
            guard state.mode == .quickSettings else { return }
            state.mode = .typing
            onDismissQuickSettings?()
        }

        /// Applied live as the panel's controls change (matches the resize
        /// overlay's own "nothing waits for an explicit save" feel) —
        /// there's no separate persisted-vs-preview distinction here like
        /// resize mode's drag preview, since these are discrete
        /// toggles/pickers/sliders a user expects to take effect immediately.
        func applyQuickSettingsChange(_ snapshot: QuickSettingsSnapshot) {
            let orientation = currentOrientation
            onRequestSettingsChange? { settings in
                snapshot.apply(to: &settings, orientation: orientation)
            }
        }

        func requestResizeFromQuickSettings() {
            dismissQuickSettings()
            startResizeMode()
        }
    }
#endif
