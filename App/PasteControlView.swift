import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Task 10.4's "Add from clipboard via `UIPasteControl` (no paste prompt)"
/// — `UIPasteControl` is the system-provided paste button that reads the
/// pasteboard without ever triggering iOS's "Allow Paste?" prompt, since
/// the tap itself is the user's explicit consent. It only knows how to
/// paste into a `UIResponder` conforming to `UIPasteConfigurationSupporting`,
/// so this wraps one that just forwards the pasted string back to SwiftUI.
struct PasteControlView: UIViewRepresentable {
    let onPaste: @Sendable (String) -> Void

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        return control
    }

    func updateUIView(_: UIPasteControl, context _: Context) {}

    func makeCoordinator() -> PasteTarget {
        PasteTarget(onPaste: onPaste)
    }

    /// A minimal `UIResponder` that only exists to be `UIPasteControl`'s
    /// `target` — it never joins the real responder chain (it's not added
    /// as a subview/superview of anything), which is fine: `UIPasteControl`
    /// calls `paste(itemProviders:)` on its `target` directly, regardless
    /// of chain membership. `UIResponder` already conforms to
    /// `UIPasteConfigurationSupporting` (with a default implementation of
    /// everything), so this only overrides what needs real behavior.
    final class PasteTarget: UIResponder {
        override var pasteConfiguration: UIPasteConfiguration? {
            get { UIPasteConfiguration(forAccepting: NSString.self) }
            set {}
        }

        private let onPaste: @Sendable (String) -> Void

        init(onPaste: @escaping @Sendable (String) -> Void) {
            self.onPaste = onPaste
            super.init()
        }

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
        }

        override func paste(itemProviders: [NSItemProvider]) {
            for provider in itemProviders where provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { [onPaste] object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async { onPaste(text) }
                }
            }
        }
    }
}
