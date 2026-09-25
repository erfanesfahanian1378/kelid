#if canImport(UIKit)
    import InputEngine
    import UIKit

    protocol SidePanelViewDelegate: AnyObject {
        func sidePanelDidTapSwitchSide(_ view: SidePanelView)
        func sidePanelDidTapExit(_ view: SidePanelView)
        func sidePanelDidTapClipboard(_ view: SidePanelView)
        func sidePanelDidStepCursor(_ view: SidePanelView, direction: MoveDirection)
    }

    /// §6.3.6's one-handed mode side panel: switch-side, exit, clipboard
    /// (disabled until Phase 5), and hold-to-repeat cursor buttons —
    /// occupies the "free side" `KeyGridView` leaves empty once
    /// `LayoutEngine` narrows `contentRect`. `KeyGridView` owns the single
    /// shared instance and positions/shows it purely from geometry
    /// (`contentRect` vs `bounds`); it never affects hit-testing or touches
    /// of the key grid itself.
    final class SidePanelView: UIView {
        weak var delegate: SidePanelViewDelegate?

        private let switchSideButton = UIButton(type: .system)
        private let exitButton = UIButton(type: .system)
        private let clipboardButton = UIButton(type: .system)
        private let cursorLeftButton = UIButton(type: .system)
        private let cursorRightButton = UIButton(type: .system)
        private var cursorRepeatTimer: Timer?
        private var cursorRepeatDirection: MoveDirection?

        private static let cursorFirstRepeatDelay: TimeInterval = 0.5
        private static let cursorRepeatInterval: TimeInterval = 0.1

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureButtons()
            let stack = UIStackView(arrangedSubviews: [
                switchSideButton, exitButton, clipboardButton, cursorLeftButton, cursorRightButton,
            ])
            stack.axis = .vertical
            stack.distribution = .fillEqually
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func apply(style: KeyStyle) {
            backgroundColor = .clear
            for button in [switchSideButton, exitButton, cursorLeftButton, cursorRightButton] {
                button.tintColor = style.labelColor
            }
            clipboardButton.tintColor = style.specialLabelColor.withAlphaComponent(0.35)
        }

        private func configureButtons() {
            switchSideButton.setTitle("⇆", for: .normal)
            switchSideButton.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                delegate?.sidePanelDidTapSwitchSide(self)
            }, for: .touchUpInside)

            exitButton.setTitle("⤢", for: .normal)
            exitButton.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                delegate?.sidePanelDidTapExit(self)
            }, for: .touchUpInside)

            // Phase 5 wires this up for real; disabled (not removed) so the
            // panel's final layout doesn't need to change later.
            clipboardButton.setTitle("📋", for: .normal)
            clipboardButton.isEnabled = false

            cursorLeftButton.setTitle("◀", for: .normal)
            cursorRightButton.setTitle("▶", for: .normal)
            cursorLeftButton.addTarget(self, action: #selector(cursorLeftDown), for: .touchDown)
            cursorRightButton.addTarget(self, action: #selector(cursorRightDown), for: .touchDown)
            for button in [cursorLeftButton, cursorRightButton] {
                button.addTarget(self, action: #selector(cursorUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
            }

            for button in [switchSideButton, exitButton, clipboardButton, cursorLeftButton, cursorRightButton] {
                button.titleLabel?.font = .systemFont(ofSize: 18)
            }
            switchSideButton.accessibilityLabel = "switch side"
            exitButton.accessibilityLabel = "exit one-handed mode"
            clipboardButton.accessibilityLabel = "clipboard"
            cursorLeftButton.accessibilityLabel = "move cursor left"
            cursorRightButton.accessibilityLabel = "move cursor right"
        }

        @objc private func cursorLeftDown() {
            beginCursorRepeat(.backward)
        }

        @objc private func cursorRightDown() {
            beginCursorRepeat(.forward)
        }

        /// Fires once immediately (the tap itself), then once more after
        /// `cursorFirstRepeatDelay`, then repeats every `cursorRepeatInterval`
        /// until release — same two-stage shape as backspace hold-repeat
        /// (§6.4.6), just simpler (no word-mode escalation).
        private func beginCursorRepeat(_ direction: MoveDirection) {
            cursorRepeatDirection = direction
            delegate?.sidePanelDidStepCursor(self, direction: direction)
            cursorRepeatTimer?.invalidate()
            cursorRepeatTimer = Timer.scheduledTimer(
                timeInterval: Self.cursorFirstRepeatDelay, target: self, selector: #selector(startRepeating), userInfo: nil, repeats: false
            )
        }

        @objc private func startRepeating() {
            guard let direction = cursorRepeatDirection else { return }
            delegate?.sidePanelDidStepCursor(self, direction: direction)
            cursorRepeatTimer = Timer.scheduledTimer(
                timeInterval: Self.cursorRepeatInterval, target: self, selector: #selector(fireCursorRepeat), userInfo: nil, repeats: true
            )
        }

        @objc private func fireCursorRepeat() {
            guard let direction = cursorRepeatDirection else { return }
            delegate?.sidePanelDidStepCursor(self, direction: direction)
        }

        @objc private func cursorUp() {
            cursorRepeatTimer?.invalidate()
            cursorRepeatTimer = nil
            cursorRepeatDirection = nil
        }
    }
#endif
