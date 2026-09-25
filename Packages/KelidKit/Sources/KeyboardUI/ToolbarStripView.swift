#if canImport(UIKit)
    import UIKit

    /// The strip above the key grid (task 3.8, §6.3.1's `toolbarHeight`).
    /// Suggestions (Phase 7) and the clip chip (Phase 5) populate it later;
    /// for now it shows `KeyboardState.toast` plus the resize (task 4.3)
    /// and Quick Settings (task 4.6) entry-point buttons — still real
    /// content (§6.4's toast effects need *something* visible), just not
    /// the full design.
    final class ToolbarStripView: UIView {
        private let label = UILabel()
        private let resizeButton = UIButton(type: .system)
        private let settingsButton = UIButton(type: .system)

        var onTapResize: (() -> Void)?
        var onTapSettings: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13)
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            addSubview(label)

            resizeButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            resizeButton.accessibilityLabel = "resize keyboard"
            resizeButton.addAction(UIAction { [weak self] _ in self?.onTapResize?() }, for: .touchUpInside)
            addSubview(resizeButton)

            settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
            settingsButton.accessibilityLabel = "keyboard settings"
            settingsButton.addAction(UIAction { [weak self] _ in self?.onTapSettings?() }, for: .touchUpInside)
            addSubview(settingsButton)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let buttonWidth: CGFloat = 36
            settingsButton.frame = CGRect(x: bounds.maxX - buttonWidth, y: 0, width: buttonWidth, height: bounds.height)
            resizeButton.frame = CGRect(x: bounds.maxX - buttonWidth * 2, y: 0, width: buttonWidth, height: bounds.height)
            label.frame = CGRect(x: 12, y: 0, width: max(0, resizeButton.frame.minX - 12), height: bounds.height)
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            label.textColor = style.labelColor
            resizeButton.tintColor = style.labelColor
            settingsButton.tintColor = style.labelColor
        }

        func setText(_ text: String?) {
            label.text = text
        }
    }
#endif
