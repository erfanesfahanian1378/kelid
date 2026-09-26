#if canImport(UIKit)
    import UIKit

    /// The strip above the key grid (task 3.8, §6.3.1's `toolbarHeight`).
    /// Suggestions (Phase 7) populate it further later; for now it shows
    /// `KeyboardState.clipChip`/`.toast` (tappable when a chip is present,
    /// §6.5.7) plus the resize (task 4.3), Quick Settings (task 4.6) and
    /// clipboard/edit (task 5.10) entry-point buttons.
    final class ToolbarStripView: UIView {
        private let label = UILabel()
        private let clipboardButton = UIButton(type: .system)
        private let editButton = UIButton(type: .system)
        private let resizeButton = UIButton(type: .system)
        private let settingsButton = UIButton(type: .system)

        var onTapResize: (() -> Void)?
        var onTapSettings: (() -> Void)?
        var onTapClipboard: (() -> Void)?
        var onTapEdit: (() -> Void)?
        /// The label itself (the clip chip / toast area) — tapping it is
        /// only meaningful while a clip chip is showing; the controller's
        /// `tapClipChip()` already no-ops otherwise.
        var onTapLabel: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13)
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleLabelTap)))
            addSubview(label)

            clipboardButton.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
            clipboardButton.accessibilityLabel = "clipboard"
            clipboardButton.addAction(UIAction { [weak self] _ in self?.onTapClipboard?() }, for: .touchUpInside)
            addSubview(clipboardButton)

            editButton.setImage(UIImage(systemName: "character.cursor.ibeam"), for: .normal)
            editButton.accessibilityLabel = "edit"
            editButton.addAction(UIAction { [weak self] _ in self?.onTapEdit?() }, for: .touchUpInside)
            addSubview(editButton)

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
            let buttonWidth: CGFloat = 32
            let buttons = [clipboardButton, editButton, resizeButton, settingsButton]
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: bounds.maxX - buttonWidth * CGFloat(index + 1), y: 0, width: buttonWidth, height: bounds.height)
            }
            let labelMaxX = buttons.last?.frame.minX ?? bounds.maxX
            label.frame = CGRect(x: 8, y: 0, width: max(0, labelMaxX - 8), height: bounds.height)
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            label.textColor = style.labelColor
            for button in [clipboardButton, editButton, resizeButton, settingsButton] {
                button.tintColor = style.labelColor
            }
        }

        func setText(_ text: String?) {
            label.text = text
        }

        /// Task 5.12: "the clipboard icon shows a small lock" without Full
        /// Access.
        func setClipboardLocked(_ isLocked: Bool) {
            clipboardButton.setImage(UIImage(systemName: isLocked ? "lock.doc" : "doc.on.clipboard"), for: .normal)
        }

        @objc private func handleLabelTap() {
            onTapLabel?()
        }
    }
#endif
