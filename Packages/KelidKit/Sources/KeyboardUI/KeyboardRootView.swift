#if canImport(UIKit)
    import UIKit

    /// The keyboard extension's whole view: toolbar strip + key grid (task 3.8).
    /// Plain frame layout, not Auto Layout/stack views — `KeyboardController`
    /// recomputes both rects on every `layoutSubviews`, driven by the same
    /// `KeyboardMetrics` the key layout itself uses, so the two stay in sync by
    /// construction rather than by separately-maintained constraints.
    public final class KeyboardRootView: UIView {
        let toolbarStrip = ToolbarStripView(frame: .zero)
        let keyGridView = KeyGridView(frame: .zero)

        /// Set by `KeyboardController` from `HeightCoordinator`'s own
        /// `toolbarHeight`/`toolbarVisible` inputs, so this view's internal
        /// split matches the height the host applied via its own constraint.
        var toolbarHeight: CGFloat = 44
        var toolbarVisible = true

        override public init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(toolbarStrip)
            addSubview(keyGridView)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            let stripHeight = toolbarVisible ? toolbarHeight : 0
            toolbarStrip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
            toolbarStrip.isHidden = !toolbarVisible
            keyGridView.frame = CGRect(x: 0, y: stripHeight, width: bounds.width, height: max(0, bounds.height - stripHeight))
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            toolbarStrip.apply(style: style)
        }
    }
#endif
