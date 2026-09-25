#if canImport(UIKit)
    import KelidCore
    import KelidSettings
    import KeyboardLayout
    import SwiftUI
    import UIKit

    /// Recomputes the real `LayoutEngine`/`KeyGridView` pipeline whenever its
    /// own bounds change — the standard self-sizing pattern, since
    /// `UIViewRepresentable.updateUIView` runs *before* SwiftUI has actually
    /// assigned the view its final size.
    public final class KeyboardPreviewHostView: UIView {
        let keyGridView = KeyGridView(frame: .zero)
        var page = PageDefinition(rows: [])
        var layoutFile: KeyboardLayoutFile?
        var metrics = KeyboardMetrics(sizeProfile: .portraitDefault)
        var direction: Direction = .rtl
        var isLanguageRTL = true

        override public init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            keyGridView.keyPopupsEnabled = false
            addSubview(keyGridView)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            keyGridView.frame = bounds
            refresh()
        }

        func refresh() {
            guard let layoutFile, keyGridView.bounds.width > 0 else { return }
            let computed = LayoutEngine.compute(page: page, in: keyGridView.bounds, metrics: metrics, direction: direction)
            keyGridView.apply(
                layout: computed,
                layoutFile: layoutFile,
                style: .resolve(traitAppearance: traitCollection.userInterfaceStyle == .dark ? .dark : .light, fieldAppearance: nil),
                fontSize: metrics.baseFontSize,
                direction: direction,
                isLanguageRTL: isLanguageRTL
            )
        }
    }

    /// Task 4.7's live `KeyboardPreview`: the *real* rendering pipeline
    /// (bundled JSON layout → `LayoutEngine` → `KeyGridView`), not a
    /// separate mock drawing — so the app's Size & Layout preview can never
    /// drift from what the keyboard extension itself actually renders.
    /// Simplified to the letters page with a minimal bottom row (space +
    /// return only): enough to preview sizing/spacing/one-handed layout,
    /// without pulling in field-trait/digit-substitution/number-row
    /// composition that only matters for real typing.
    public struct KeyboardPreviewView: UIViewRepresentable {
        public var profile: SizeProfile
        public var language: LanguageID

        public init(profile: SizeProfile, language: LanguageID = .fa) {
            self.profile = profile
            self.language = language
        }

        public func makeUIView(context _: Context) -> KeyboardPreviewHostView {
            KeyboardPreviewHostView(frame: .zero)
        }

        public func updateUIView(_ view: KeyboardPreviewHostView, context _: Context) {
            let layoutFile = LayoutRepository.shared.layout(id: language == .fa ? "fa.standard" : "en.qwerty")
            var rows = layoutFile[.letters]?.rows ?? []
            rows.append([
                KeyDefinition(out: language == .fa ? "۱۲۳" : "123", action: .pageSymbols1, width: 1.25),
                KeyDefinition(label: language == .fa ? "فارسی" : "English", action: .space, flex: true),
                KeyDefinition(label: "⏎", action: .return, width: 1.75),
            ])
            view.page = PageDefinition(rows: rows)
            view.layoutFile = layoutFile
            view.metrics = KeyboardMetrics(sizeProfile: profile)
            view.direction = language == .fa ? .rtl : .ltr
            view.isLanguageRTL = language == .fa
            view.setNeedsLayout()
            view.refresh()
        }
    }
#endif
