#if canImport(UIKit)
    import Foundation
    import KelidSettings
    import KeyboardLayout

    /// Resize mode (task 4.3, §6.3.7) — split out of `KeyboardController.swift`
    /// itself purely to keep that type's body under SwiftLint's
    /// `type_body_length`; behaviorally this is still part of
    /// `KeyboardController`, just declared in a second file.
    extension KeyboardController {
        private func currentSizeProfile() -> SizeProfile {
            switch currentOrientation {
            case .portrait: settings.size.portrait
            case .landscape: settings.size.landscape
            }
        }

        /// §6.3.2: landscape's default is fixed at 40, unlike portrait's
        /// device-class table.
        var deviceDefaultRowHeight: CGFloat {
            currentOrientation == .landscape ? 40 : DeviceSizeClass.portraitRowHeightDefault(screenHeight: screenHeight)
        }

        public func startResizeMode() {
            guard state.mode != .resize, resizeSession == nil else { return }
            preResizeMetrics = currentMetrics
            lastSnapHapticFlag = false
            let session = ResizeSession(
                profile: currentSizeProfile(),
                orientation: currentOrientation,
                deviceDefaultRowHeight: deviceDefaultRowHeight,
                rowCount: composedPage.rows.count
            )
            resizeSession = session
            state.mode = .resize
            observeResizeSession(session)
            onPresentResizeOverlay?(session)
        }

        /// `save == false` covers Reset-and-exit, rotation cancelling
        /// (§6.3.7), and any other abandoned session.
        public func endResizeMode(save: Bool) {
            guard let session = resizeSession else { return }
            resizeCoalescer.stop()
            if save {
                let result = session.resultProfile()
                currentMetrics = KeyboardMetrics(sizeProfile: result)
                let orientation = currentOrientation
                onRequestSettingsChange? { settings in
                    switch orientation {
                    case .portrait: settings.size.portrait = result
                    case .landscape: settings.size.landscape = result
                    }
                }
            } else if let preResizeMetrics {
                currentMetrics = preResizeMetrics
            }
            preResizeMetrics = nil
            resizeSession = nil
            state.mode = .typing
            onDismissResizeOverlay?()
            rebuild()
        }

        /// Live-preview only — never touches `settings`/`SettingsStore`
        /// (task 4.3: nothing persists until **Done**).
        private func previewSizeProfile(_ profile: SizeProfile) {
            currentMetrics = KeyboardMetrics(sizeProfile: profile)
            rebuild()
        }

        /// `@Observable` objects need `withObservationTracking` to be
        /// watched from outside SwiftUI's own view-body tracking — each
        /// callback fires once, so this re-registers itself every time.
        private func observeResizeSession(_ session: ResizeSession) {
            withObservationTracking {
                _ = session.rowHeight
                _ = session.bottomLift
                _ = session.oneHanded
                _ = session.oneHandedWidthRatio
                _ = session.didFireDefaultSnapHaptic
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self, self.resizeSession === session else { return }
                    self.resizeSessionDidChange(session)
                    self.observeResizeSession(session)
                }
            }
        }

        private func resizeSessionDidChange(_ session: ResizeSession) {
            if session.didFireDefaultSnapHaptic != lastSnapHapticFlag {
                lastSnapHapticFlag = session.didFireDefaultSnapHaptic
                if lastSnapHapticFlag, hasFullAccess, let style = hapticStyle() {
                    feedbackService.prepareHaptic(style: style)
                    feedbackService.fireHaptic()
                }
            }
            resizeCoalescer.schedule { [weak self] in
                guard let self, let current = resizeSession, current === session else { return }
                previewSizeProfile(session.resultProfile())
            }
        }
    }
#endif
