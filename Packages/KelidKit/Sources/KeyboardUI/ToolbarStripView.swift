#if canImport(UIKit)
    import PredictionEngine
    import UIKit

    /// One suggestion bar slot, per §6.7.5's assembly (task 7.8/8.6/9.3).
    struct SuggestionSlot: Equatable {
        let text: String
        let isBold: Bool
        let isVerbatim: Bool
    }

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
        /// Task 9.7: the incognito toggle — always present alongside the
        /// other icon buttons (unlike §6.1.4's general `toolbar.items` list,
        /// this toolbar's icon row isn't yet driven by that setting at all;
        /// see the existing fixed 4-button row above).
        private let incognitoButton = UIButton(type: .system)
        private var isIncognitoActive = false

        private let suggestionStack = UIStackView()
        private var suggestionButtons: [UIButton] = []
        /// Index into the currently-displayed slot array (leading-to-trailing,
        /// already RTL-ordered) — not the raw `SuggestionResult` index.
        var onTapSuggestionSlot: ((Int) -> Void)?
        /// Task 7.8: "long-press shows a placeholder menu" — real
        /// block/forget actions arrive with Phase 9's learning; for now this
        /// just proves the gesture path exists.
        var onLongPressSuggestionSlot: ((Int) -> Void)?

        /// Task 8.7 (§6.7.5): "Emoji (if any) get a compact 44 pt slot at
        /// the far trailing edge." Only the single best match is shown —
        /// `emoji.json`'s own suggestion tables are already capped at 3 per
        /// keyword, most-common-first, so `.first` is the best one.
        private let emojiButton = UIButton(type: .system)
        private static let emojiSlotWidth: CGFloat = 44
        private var isEmojiSlotVisible = false
        private var isCurrentLayoutRTL = false
        var onTapEmoji: ((String) -> Void)?

        /// Test-only seam (`@testable import` only relaxes `internal`, not
        /// `private`, across files) — the suggestion buttons in their
        /// current *visual* left-to-right order, for asserting RTL
        /// mirroring without a full rendered-view snapshot.
        var suggestionStackArrangedButtons: [UIButton] {
            suggestionStack.arrangedSubviews.compactMap { $0 as? UIButton }
        }

        /// Test-only seam, same reasoning as `suggestionStackArrangedButtons`.
        var emojiSlotButton: UIButton {
            emojiButton
        }

        var onTapResize: (() -> Void)?
        var onTapSettings: (() -> Void)?
        var onTapClipboard: (() -> Void)?
        var onTapEdit: (() -> Void)?
        var onTapIncognito: (() -> Void)?
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

            incognitoButton.setImage(UIImage(systemName: "eye.slash"), for: .normal)
            incognitoButton.accessibilityLabel = "incognito"
            incognitoButton.addAction(UIAction { [weak self] _ in self?.onTapIncognito?() }, for: .touchUpInside)
            addSubview(incognitoButton)

            suggestionStack.axis = .horizontal
            suggestionStack.distribution = .fillEqually
            suggestionStack.isHidden = true
            addSubview(suggestionStack)

            emojiButton.titleLabel?.font = .systemFont(ofSize: 20)
            emojiButton.isHidden = true
            emojiButton.addAction(UIAction { [weak self] _ in
                guard let self, let emoji = emojiButton.title(for: .normal) else { return }
                onTapEmoji?(emoji)
            }, for: .touchUpInside)
            addSubview(emojiButton)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let buttonWidth: CGFloat = 32
            let buttons = [clipboardButton, editButton, resizeButton, settingsButton, incognitoButton]
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: bounds.maxX - buttonWidth * CGFloat(index + 1), y: 0, width: buttonWidth, height: bounds.height)
            }
            let labelMaxX = buttons.last?.frame.minX ?? bounds.maxX
            label.frame = CGRect(x: 8, y: 0, width: max(0, labelMaxX - 8), height: bounds.height)

            guard isEmojiSlotVisible else {
                suggestionStack.frame = bounds
                emojiButton.frame = .zero
                return
            }
            // "The far trailing edge" — the right edge in LTR, the left edge
            // in RTL (mirroring the whole bar, same as the suggestion slots
            // themselves).
            let emojiX = isCurrentLayoutRTL ? bounds.minX : bounds.maxX - Self.emojiSlotWidth
            emojiButton.frame = CGRect(x: emojiX, y: 0, width: Self.emojiSlotWidth, height: bounds.height)
            let suggestionX = isCurrentLayoutRTL ? Self.emojiSlotWidth : 0
            suggestionStack.frame = CGRect(x: suggestionX, y: 0, width: max(0, bounds.width - Self.emojiSlotWidth), height: bounds.height)
        }

        func apply(style: KeyStyle) {
            backgroundColor = isIncognitoActive ? Self.incognitoTint : style.keyboardBackground
            label.textColor = style.labelColor
            for button in [clipboardButton, editButton, resizeButton, settingsButton] {
                button.tintColor = style.labelColor
            }
            incognitoButton.tintColor = isIncognitoActive ? .white : style.labelColor
            for button in suggestionButtons {
                button.setTitleColor(style.labelColor, for: .normal)
            }
        }

        /// Task 9.7: "a tinted toolbar while active" — a fixed color rather
        /// than derived from `KeyStyle` since incognito is a transient,
        /// theme-independent state signal (same reasoning system apps use a
        /// fixed color for their own "private" indicators), and this
        /// codebase doesn't have per-theme semantic colors yet (Phase 11).
        private static let incognitoTint = UIColor.systemPurple

        /// Task 9.7 — called by `KeyboardController.toggleIncognito()`, which
        /// calls `restyle()` immediately afterward so `apply(style:)` picks
        /// up the new tint right away rather than waiting for some other,
        /// unrelated style change.
        func setIncognito(_ isOn: Bool) {
            isIncognitoActive = isOn
            incognitoButton.accessibilityValue = isOn ? "on" : "off"
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
            isCurrentLayoutRTL = isRTL
            let slots = result.map(Self.slots(for:)) ?? []
            guard !slots.isEmpty else {
                suggestionStack.isHidden = true
                isEmojiSlotVisible = false
                emojiButton.isHidden = true
                label.isHidden = false
                setIconButtons(hidden: false)
                setNeedsLayout()
                return
            }
            label.isHidden = true
            setIconButtons(hidden: true)
            suggestionStack.isHidden = false

            let bestEmoji = result?.emoji.first
            isEmojiSlotVisible = bestEmoji != nil
            emojiButton.isHidden = bestEmoji == nil
            if let bestEmoji {
                emojiButton.setTitle(bestEmoji, for: .normal)
            }
            setNeedsLayout()

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
        /// text (so the same word never appears twice). Task 8.6: the center
        /// slot is also bold when it's the autocorrect candidate (§6.7.5:
        /// "center = best (bold when it's the autocorrect candidate)").
        /// Task 9.3: `isVerbatim` on a slot (never more than one) tells the
        /// controller to tag a tap on it with §6.7.6's "tapped verbatim"
        /// 2.0 learning weight, not the ordinary "accepted suggestion" 1.0
        /// — distinguishing it from a regular candidate slot whose text
        /// happens to equal the typed text (e.g. it's already a known word).
        static func slots(for result: SuggestionResult) -> [SuggestionSlot] {
            guard let verbatim = result.verbatim else {
                return result.items.prefix(3).map { SuggestionSlot(text: $0.text, isBold: false, isVerbatim: false) }
            }
            var items = result.items
            if let first = items.first, first.text == verbatim.text {
                items.removeFirst()
                return [SuggestionSlot(text: verbatim.text, isBold: true, isVerbatim: true)] +
                    items.prefix(2).map { SuggestionSlot(text: $0.text, isBold: false, isVerbatim: false) }
            }
            let bestIsAutocorrect = result.autocorrect.map { $0.text == items.first?.text } ?? false
            return [SuggestionSlot(text: verbatim.text, isBold: false, isVerbatim: true)] + items.prefix(2).enumerated()
                .map { index, item in
                    SuggestionSlot(text: item.text, isBold: index == 0 && bestIsAutocorrect, isVerbatim: false)
                }
        }

        private func setIconButtons(hidden: Bool) {
            for button in [clipboardButton, editButton, resizeButton, settingsButton, incognitoButton] {
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
