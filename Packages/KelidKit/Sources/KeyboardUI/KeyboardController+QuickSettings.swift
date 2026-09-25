#if canImport(UIKit)
    import KelidSettings

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
                onPresentQuickSettings?(
                    QuickSettingsSnapshot(settings: settings, orientation: currentOrientation),
                    QuickSettingsSnapshot.deviceDefaults(orientation: currentOrientation, deviceDefaultRowHeight: deviceDefaultRowHeight)
                )
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
