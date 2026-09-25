#if canImport(UIKit)
    import UIKit

    /// The strip above the key grid (task 3.8, §6.3.1's `toolbarHeight`).
    /// Suggestions (Phase 7) and the clip chip (Phase 5) populate it later;
    /// for now it only shows `KeyboardState.toast` — still real content
    /// (§6.4's toast effects need *something* visible), just not the full
    /// design.
    final class ToolbarStripView: UIView {
        private let label = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13)
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            addSubview(label)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds.insetBy(dx: 12, dy: 0)
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            label.textColor = style.labelColor
        }

        func setText(_ text: String?) {
            label.text = text
        }
    }
#endif
