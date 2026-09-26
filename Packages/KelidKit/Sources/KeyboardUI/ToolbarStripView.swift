#if canImport(UIKit)
    import PredictionEngine
    import UIKit

    /// The strip above the key grid (task 3.8, §6.3.1's `toolbarHeight`).
    /// Shows either the suggestion bar (task 7.8, when there are
    /// suggestions to show) or the clip-chip/toast label plus the
    /// resize/settings/clipboard/edit icon buttons — never both at once,
    /// same "one strip, two faces" idea as the plan's own toolbar-mode
    /// table (§6.1.4).
    final class ToolbarStripView: UIView {
        private let label = UILabel()
        private let clipboardButton = UIButton(type: .system)
        private let editButton = UIButton(type: .system)
        private let resizeButton = UIButton(type: .system)
        private let settingsButton = UIButton(type: .system)

        private let suggestionStack = UIStackView()
        private var suggestionButtons: [UIButton] = []
        /// Index into the currently-displayed slot array (leading-to-trailing,
        /// already RTL-ordered) — not the raw `SuggestionResult` index.
        var onTapSuggestionSlot: ((Int) -> Void)?
        /// Task 7.8: "long-press shows a placeholder menu" — real
        /// block/forget actions arrive with Phase 9's learning; for now this
        /// just proves the gesture path exists.
        var onLongPressSuggestionSlot: ((Int) -> Void)?

        /// Test-only seam (`@testable import` only relaxes `internal`, not
        /// `private`, across files) — the suggestion buttons in their
        /// current *visual* left-to-right order, for asserting RTL
        /// mirroring without a full rendered-view snapshot.
        var suggestionStackArrangedButtons: [UIButton] {
            suggestionStack.arrangedSubviews.compactMap { $0 as? UIButton }
        }

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

            suggestionStack.axis = .horizontal
            suggestionStack.distribution = .fillEqually
            suggestionStack.isHidden = true
            addSubview(suggestionStack)
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
            suggestionStack.frame = bounds
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            label.textColor = style.labelColor
            for button in [clipboardButton, editButton, resizeButton, settingsButton] {
                button.tintColor = style.labelColor
            }
            for button in suggestionButtons {
                button.setTitleColor(style.labelColor, for: .normal)
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

        /// Task 7.8: renders `result`'s verbatim/best/second slots (already
        /// collapsed per §6.7.5's "best == verbatim" rule by
        /// `Self.slots(for:)`), or switches back to the normal label+icons
        /// row when `result` is `nil`/empty. `isRTL` decides visual
        /// leading-to-trailing order explicitly — driven by the keyboard's
        /// *current typing language*, not the system/app locale, same
        /// reasoning `LayoutEngine`'s own `direction` parameter already
        /// uses elsewhere.
        func applySuggestions(_ result: SuggestionResult?, isRTL: Bool) {
            let slots = result.map(Self.slots(for:)) ?? []
            guard !slots.isEmpty else {
                suggestionStack.isHidden = true
                label.isHidden = false
                setIconButtons(hidden: false)
                return
            }
            label.isHidden = true
            setIconButtons(hidden: true)
            suggestionStack.isHidden = false

            suggestionStack.arrangedSubviews.forEach { suggestionStack.removeArrangedSubview($0); $0.removeFromSuperview() }
            suggestionButtons = slots.map { slot in
                let button = UIButton(type: .system)
                button.setTitle(slot.text, for: .normal)
                button.titleLabel?.font = slot.isBold ? .boldSystemFont(ofSize: 15) : .systemFont(ofSize: 15)
                button.titleLabel?.adjustsFontSizeToFitWidth = true
                return button
            }
            let orderedButtons = isRTL ? suggestionButtons.reversed() : suggestionButtons
            for (visualIndex, button) in orderedButtons.enumerated() {
                // The tap/long-press callbacks report the *slot* index
                // (leading-to-trailing, pre-mirroring), not the button's
                // position in the (possibly reversed) stack view.
                let slotIndex = isRTL ? suggestionButtons.count - 1 - visualIndex : visualIndex
                button.addAction(UIAction { [weak self] _ in self?.onTapSuggestionSlot?(slotIndex) }, for: .touchUpInside)
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSuggestionLongPress(_:)))
                button.tag = slotIndex
                button.addGestureRecognizer(longPress)
                suggestionStack.addArrangedSubview(button)
            }
        }

        /// §6.7.5's slot assembly: leading = verbatim, center = best,
        /// trailing = second-best — collapsed to `[verbatim(bold), 2nd,
        /// 3rd]` when the top-ranked item's text already equals the typed
        /// text (so the same word never appears twice).
        static func slots(for result: SuggestionResult) -> [(text: String, isBold: Bool)] {
            guard let verbatim = result.verbatim else {
                return result.items.prefix(3).map { ($0.text, false) }
            }
            var items = result.items
            if let first = items.first, first.text == verbatim.text {
                items.removeFirst()
                return [(verbatim.text, true)] + items.prefix(2).map { ($0.text, false) }
            }
            return [(verbatim.text, false)] + items.prefix(2).map { ($0.text, false) }
        }

        private func setIconButtons(hidden: Bool) {
            for button in [clipboardButton, editButton, resizeButton, settingsButton] {
                button.isHidden = hidden
            }
        }

        @objc private func handleLabelTap() {
            onTapLabel?()
        }

        @objc private func handleSuggestionLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let button = recognizer.view as? UIButton else { return }
            onLongPressSuggestionSlot?(button.tag)
        }
    }
#endif
