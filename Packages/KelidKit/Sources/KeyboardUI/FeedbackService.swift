#if canImport(UIKit)
    import AudioToolbox
    import UIKit

    /// Haptics and sounds on key press (task 3.14). Both are only meaningful
    /// with Full Access (§2.1 C2 — a keyboard extension without Full Access
    /// can't play system sounds or drive the Taptic Engine); `KeyboardController`
    /// is responsible for checking Full Access and the relevant setting before
    /// calling into this type at all.
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
    }
#endif
