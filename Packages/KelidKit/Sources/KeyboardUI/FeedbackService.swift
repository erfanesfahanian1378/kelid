#if canImport(UIKit)
    import AudioToolbox
    import InputEngine
    import KelidSettings
    import UIKit

    /// Haptics and sounds on key press (task 3.14, custom packs task 11.5).
    /// Both are only meaningful with Full Access (§2.1 C2 — a keyboard
    /// extension without Full Access can't play system sounds or drive the
    /// Taptic Engine); `KeyboardController` is responsible for checking Full
    /// Access and the relevant setting before calling into this type at all.
    @MainActor
    final class FeedbackService {
        private var impactGenerator: UIImpactFeedbackGenerator?

        /// Standard iOS system sound IDs, matching what the built-in keyboard
        /// uses. Not yet confirmed correct for Kelid specifically on a physical
        /// device — see PROGRESS.md decision log for task 3.14/3.16.
        enum SoundID: UInt32 {
            case standardKeyPress = 1123
            case delete = 1155
            case modifierKeyPress = 1156
        }

        /// Registered lazily, once per resource name, and cached for the
        /// life of this `FeedbackService` (one per `KeyboardController`,
        /// itself one per keyboard session) — `AudioServicesCreateSystemSoundID`
        /// is real file I/O, not something to redo on every keystroke.
        private var customSoundIDs: [String: SystemSoundID] = [:]

        /// Call on touch-down so the Taptic Engine is warmed up by the time the
        /// key actually commits ("prepared on touch-down").
        func prepareHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impactGenerator = generator
        }

        func fireHaptic() {
            impactGenerator?.impactOccurred()
            impactGenerator = nil
        }

        func playSound(_ sound: SoundID) {
            DispatchQueue.global(qos: .userInteractive).async {
                AudioServicesPlaySystemSound(SystemSoundID(sound.rawValue))
            }
        }

        /// §6.8.5's `soft`/`typewriter` packs: two bundled `.caf` files each
        /// (`keyPress` for ordinary characters, `specialKeyPress` for
        /// everything else — matching `FeedbackKind`'s own two real cases;
        /// `.error` has no sound in either pack). `nil` `kind` (i.e. `.error`)
        /// or a resource that fails to load plays nothing rather than
        /// falling back to the system sound — a broken bundle shouldn't
        /// silently switch packs on the user.
        func playCustomSound(pack: SoundChoice, kind: FeedbackKind) {
            guard let resourceName = Self.resourceName(pack: pack, kind: kind) else { return }
            let soundID = customSoundIDs[resourceName] ?? registerCustomSound(named: resourceName)
            guard let soundID else { return }
            DispatchQueue.global(qos: .userInteractive).async {
                AudioServicesPlaySystemSound(soundID)
            }
        }

        private func registerCustomSound(named resourceName: String) -> SystemSoundID? {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "caf", subdirectory: "Sounds") else {
                return nil
            }
            var soundID: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
            guard status == kAudioServicesNoError else { return nil }
            customSoundIDs[resourceName] = soundID
            return soundID
        }

        private static func resourceName(pack: SoundChoice, kind: FeedbackKind) -> String? {
            let prefix: String
            switch pack {
            case .off, .system: return nil
            case .soft: prefix = "soft"
            case .typewriter: prefix = "typewriter"
            }
            switch kind {
            case .keyPress: return "\(prefix)-keypress"
            case .specialKeyPress: return "\(prefix)-special"
            case .error: return nil
            }
        }
    }
#endif
