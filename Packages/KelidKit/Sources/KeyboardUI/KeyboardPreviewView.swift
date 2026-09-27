#if canImport(UIKit)
    import KelidCore
    import KelidSettings
    import KeyboardLayout
    import SwiftUI
    import ThemeKit
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
        /// Task 11.8's theme editor passes the theme being edited, for a
        /// truly live preview; `nil` (every other caller, e.g. Size & Layout)
        /// falls back to the system trait's light/dark fallback theme, same
        /// behavior this preview always had before real theming existed.
        var theme: Theme?

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
            let resolvedTheme = theme ?? (traitCollection.userInterfaceStyle == .dark ? .fallbackDark : .fallbackLight)
            keyGridView.apply(
                layout: computed,
                layoutFile: layoutFile,
                style: .make(from: resolvedTheme, themeStore: nil),
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
        /// Task 11.8: pass the theme under edit for a truly live preview;
        /// `nil` (every non-theme-editor caller) resolves from the system trait.
        public var theme: Theme?

        public init(profile: SizeProfile, language: LanguageID = .fa, theme: Theme? = nil) {
            self.profile = profile
            self.language = language
            self.theme = theme
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
            view.theme = theme
            view.setNeedsLayout()
            view.refresh()
        }
    }
#endif
