#if canImport(UIKit)
    import InputEngine
    import KeyboardLayout
    import UIKit

    @MainActor
    protocol KeyGridViewDelegate: AnyObject {
        func keyGridView(_ view: KeyGridView, didCommit key: KeyDefinition)
        func keyGridView(_ view: KeyGridView, didCommitAlternate alternate: String, for key: KeyDefinition)
        func keyGridView(_ view: KeyGridView, didPerformImmediateAction key: KeyDefinition)
        /// Fires on `.pressEnded`/`.cancelled`, after the visual press state has
        /// already been cleared — lets the controller stop things it started on
        /// touch-down (e.g. the backspace hold-repeat timer). `nil` if the key's
        /// definition is no longer resolvable (layout changed mid-touch).
        func keyGridView(_ view: KeyGridView, didEndPress key: KeyDefinition?)
        func keyGridView(_ view: KeyGridView, didStepTrackpad characters: Int)
        func keyGridView(_ view: KeyGridView, didChangeBackspaceSwipeWordDelta delta: Int)
        func keyGridView(_ view: KeyGridView, didShowAlternates alternates: [String], for key: KeyDefinition)
        func keyGridView(_ view: KeyGridView, didChangeAlternateSelection index: Int?)
        func keyGridViewDidHideAlternates(_ view: KeyGridView)
        /// §6.3.6's one-handed side panel (task 4.4) — only fires while the
        /// panel is actually showing (one-handed mode already on).
        func keyGridViewDidTapSwitchOneHandedSide(_ view: KeyGridView)
        func keyGridViewDidTapExitOneHanded(_ view: KeyGridView)
        func keyGridView(_ view: KeyGridView, didStepCursorFromSidePanel direction: MoveDirection)
    }

    /// Builds/positions/reuses `KeyView`s from a `ComputedLayout` (task 3.1),
    /// and bridges real multi-touch (`isMultipleTouchEnabled = true`) into
    /// `KeyTouchTracker` (task 3.2) — never touches `TextDocument` itself; that
    /// happens in `KeyboardController`, reached via `delegate`.
    final class KeyGridView: UIView {
        weak var delegate: KeyGridViewDelegate?

        private var keyViews: [String: KeyView] = [:]
        private var currentLayout: ComputedLayout?
        private var currentLayoutFile: KeyboardLayoutFile?
        private var currentStyle: KeyStyle = .light
        private var currentFontSize: CGFloat = 20
        private var currentDirection: Direction = .ltr
        private var currentLanguageIsRTLText = false

        /// `GeneralSettings.keyPopups` (task 3.3) — `KeyboardController` keeps
        /// this in sync; alternates (task 3.4) always show regardless, since
        /// they're how a long-press *works*, not a decoration.
        var keyPopupsEnabled = true

        let touchTracker: KeyTouchTracker
        private let bottomLiftView = BottomLiftView(frame: .zero)
        private let keyCallout = KeyCalloutView(frame: .zero)
        private let alternatesCallout = AlternatesCalloutView(frame: .zero)
        private let sidePanel = SidePanelView(frame: .zero)

        override init(frame: CGRect) {
            touchTracker = KeyTouchTracker(settings: TouchSettings())
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            addSubview(bottomLiftView)
            sidePanel.isHidden = true
            addSubview(sidePanel)
            addSubview(keyCallout)
            addSubview(alternatesCallout)
            sidePanel.delegate = self
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        // MARK: - Layout application (task 3.1)

        func apply(
            layout: ComputedLayout,
            layoutFile: KeyboardLayoutFile,
            style: KeyStyle,
            fontSize: CGFloat,
            direction: Direction,
            isLanguageRTL: Bool
        ) {
            currentLayout = layout
            currentLayoutFile = layoutFile
            currentStyle = style
            currentFontSize = fontSize
            currentDirection = direction
            currentLanguageIsRTLText = isLanguageRTL

            var seenIDs: Set<String> = []
            for row in layout.rows {
                for key in row.keys {
                    let id = positionID(row: key.rowIndex, index: key.indexInRow)
                    seenIDs.insert(id)
                    let view = keyViews[id] ?? {
                        let newView = KeyView(frame: key.frame)
                        keyViews[id] = newView
                        addSubview(newView)
                        return newView
                    }()
                    view.configure(
                        frame: key.frame,
                        displayText: displayText(for: key.definition),
                        fontSize: fontSize,
                        style: style,
                        isSpecial: isSpecialKey(key.definition),
                        isPressed: false,
                        accessibilityLabel: accessibilityLabel(for: key.definition)
                    )
                }
            }
            // Remove KeyViews for positions that no longer exist in this layout
            // (e.g. switching from a 12-key row to an 11-key one).
            for (id, view) in keyViews where !seenIDs.contains(id) {
                view.removeFromSuperview()
                keyViews.removeValue(forKey: id)
            }
            updateSidePanel(layout: layout, style: style)
            updateBottomLift(layout: layout, style: style)
        }

        /// Task 4.5: whatever's left below the last row's bottom edge,
        /// within this view's own bounds (§6.3.1's `bottomPadding` +
        /// `bottomLift` — `LayoutEngine` itself doesn't reserve `topPadding`
        /// as a separate visual inset above the first row, so in practice
        /// this area is slightly taller than `bottomLift` alone; visually
        /// identical either way, and not worth reshaping already-tested row
        /// geometry over 4pt).
        private func updateBottomLift(layout: ComputedLayout, style: KeyStyle) {
            guard let lastRowMaxY = layout.rows.last?.frame.maxY else {
                bottomLiftView.isHidden = true
                return
            }
            let height = layout.bounds.maxY - lastRowMaxY
            guard height > 0 else {
                bottomLiftView.isHidden = true
                return
            }
            bottomLiftView.frame = CGRect(x: layout.bounds.minX, y: lastRowMaxY, width: layout.bounds.width, height: height)
            bottomLiftView.apply(style: style)
            bottomLiftView.isHidden = false
            sendSubviewToBack(bottomLiftView)
        }

        /// §6.3.6: the side panel occupies whatever `LayoutEngine` left
        /// empty between `contentRect` and the full `bounds` — purely
        /// geometric (no separate "is one-handed" flag needed): equal
        /// rects means off, `contentRect` flush with one edge but not the
        /// other means the free side is the edge it *isn't* flush with.
        private func updateSidePanel(layout: ComputedLayout, style: KeyStyle) {
            let bounds = layout.bounds
            let content = layout.contentRect
            let epsilon: CGFloat = 0.5
            let freeOnRight = content.maxX < bounds.maxX - epsilon
            let freeOnLeft = content.minX > bounds.minX + epsilon
            guard freeOnRight || freeOnLeft else {
                sidePanel.isHidden = true
                return
            }
            sidePanel.frame = freeOnRight
                ? CGRect(x: content.maxX, y: bounds.minY, width: bounds.maxX - content.maxX, height: bounds.height)
                : CGRect(x: bounds.minX, y: bounds.minY, width: content.minX - bounds.minX, height: bounds.height)
            sidePanel.apply(style: style)
            sidePanel.isHidden = false
            bringSubviewToFront(sidePanel)
        }

        private func positionID(row: Int, index: Int) -> String {
            "\(row)-\(index)"
        }

        private func displayText(for key: KeyDefinition) -> String {
            key.label ?? key.out ?? ""
        }

        private func isSpecialKey(_ key: KeyDefinition) -> Bool {
            key.action != .char
        }

        private func accessibilityLabel(for key: KeyDefinition) -> String {
            switch key.action {
            case .char: key.out ?? ""
            case .shift: "shift"
            case .backspace: "delete"
            case .space: "space"
            case .return: "return"
            // "نیم‌فاصله" ("half-space") is itself correctly written with a
            // ZWNJ — spelled via `\u{200C}` rather than a literal invisible
            // character embedded in the source, which SwiftLint's
            // `invisible_character` rule (rightly) flags on sight.
            case .zwnj: "نیم\u{200C}فاصله"
            case .pageLetters, .pageSymbols1, .pageSymbols2: key.out ?? "page"
            case .language: "next keyboard language"
            case .globe: "next keyboard"
            case .emoji: "emoji"
            case .dismiss: "dismiss keyboard"
            }
        }

        private func alternates(for key: KeyDefinition) -> [String] {
            if let overrides = key.alternates {
                return overrides
            }
            guard let out = key.out, let file = currentLayoutFile else { return [] }
            return file.alternates[out] ?? []
        }

        private func trackedKey(for computed: ComputedKey) -> TrackedKey {
            let kind: TrackedKeyKind = switch computed.definition.action {
            case .char: .character(alternates: alternates(for: computed.definition))
            case .space: .space
            case .return: .returnKey
            case .backspace: .backspace
            case .shift: .shift
            default: .other
            }
            return TrackedKey(
                id: positionID(row: computed.rowIndex, index: computed.indexInRow),
                kind: kind,
                center: CGPoint(x: computed.frame.midX, y: computed.frame.midY),
                width: computed.frame.width
            )
        }

        // MARK: - Touch handling (task 3.2)

        override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            for touch in touches {
                let point = touch.location(in: self)
                guard let computed = currentLayout?.key(at: point) else { continue }
                let events = touchTracker.touchBegan(
                    touchID: ObjectIdentifier(touch),
                    key: trackedKey(for: computed),
                    at: point,
                    timestamp: touch.timestamp
                )
                handle(events)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            for touch in touches {
                let point = touch.location(in: self)
                let events = touchTracker.touchMoved(
                    touchID: ObjectIdentifier(touch),
                    to: point,
                    timestamp: touch.timestamp,
                    isRTLContext: currentLanguageIsRTLText,
                    direction: currentDirection
                )
                handle(events)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            for touch in touches {
                let point = touch.location(in: self)
                let events = touchTracker.touchEnded(touchID: ObjectIdentifier(touch), at: point, timestamp: touch.timestamp)
                handle(events)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
            for touch in touches {
                let events = touchTracker.touchCancelled(touchID: ObjectIdentifier(touch))
                handle(events)
            }
        }

        private func definition(forKeyID keyID: String) -> KeyDefinition? {
            computedKey(forKeyID: keyID)?.definition
        }

        private func handle(_ events: [KeyTouchEvent]) {
            for event in events {
                switch event {
                case let .pressBegan(keyID):
                    keyViews[keyID]?.setPressed(true)
                    showCalloutIfNeeded(forKeyID: keyID)
                case let .pressEnded(keyID), let .cancelled(keyID):
                    keyViews[keyID]?.setPressed(false)
                    keyCallout.hide()
                    delegate?.keyGridView(self, didEndPress: definition(forKeyID: keyID))
                case let .commit(keyID):
                    keyCallout.hide()
                    if let def = definition(forKeyID: keyID) {
                        delegate?.keyGridView(self, didCommit: def)
                    }
                case let .commitAlternate(keyID, alternate):
                    alternatesCallout.hide()
                    if let def = definition(forKeyID: keyID) {
                        delegate?.keyGridView(self, didCommitAlternate: alternate, for: def)
                    }
                    delegate?.keyGridViewDidHideAlternates(self)
                case let .immediateAction(keyID):
                    if let def = definition(forKeyID: keyID) {
                        delegate?.keyGridView(self, didPerformImmediateAction: def)
                    }
                case let .alternatesShown(keyID, alternates):
                    keyCallout.hide()
                    showAlternates(alternates, forKeyID: keyID)
                    if let def = definition(forKeyID: keyID) {
                        delegate?.keyGridView(self, didShowAlternates: alternates, for: def)
                    }
                case let .alternateSelectionChanged(index):
                    alternatesCallout.setSelection(index, style: currentStyle)
                    delegate?.keyGridView(self, didChangeAlternateSelection: index)
                case let .trackpadStep(characters):
                    delegate?.keyGridView(self, didStepTrackpad: characters)
                case .languageSwipe:
                    break
                case let .backspaceSwipeWordDelta(delta):
                    delegate?.keyGridView(self, didChangeBackspaceSwipeWordDelta: delta)
                }
            }
        }

        /// Task 3.3: only plain character keys get the enlarged popup — special
        /// keys (space, backspace, shift, return, page/language switches...)
        /// never do, matching the built-in keyboard.
        private func showCalloutIfNeeded(forKeyID keyID: String) {
            guard keyPopupsEnabled, let computed = computedKey(forKeyID: keyID), computed.definition.action == .char else { return }
            keyCallout.show(
                text: displayText(for: computed.definition),
                above: computed.frame,
                fontSize: currentFontSize,
                style: currentStyle,
                containerBounds: bounds
            )
        }

        private func showAlternates(_ alternates: [String], forKeyID keyID: String) {
            guard let computed = computedKey(forKeyID: keyID) else { return }
            alternatesCallout.show(
                primary: displayText(for: computed.definition),
                alternates: alternates,
                direction: currentDirection,
                above: computed.frame,
                fontSize: currentFontSize,
                style: currentStyle,
                containerBounds: bounds
            )
        }

        private func computedKey(forKeyID keyID: String) -> ComputedKey? {
            guard let layout = currentLayout else { return nil }
            for row in layout.rows {
                for key in row.keys where positionID(row: key.rowIndex, index: key.indexInRow) == keyID {
                    return key
                }
            }
            return nil
        }
    }

    extension KeyGridView: SidePanelViewDelegate {
        func sidePanelDidTapSwitchSide(_: SidePanelView) {
            delegate?.keyGridViewDidTapSwitchOneHandedSide(self)
        }

        func sidePanelDidTapExit(_: SidePanelView) {
            delegate?.keyGridViewDidTapExitOneHanded(self)
        }

        func sidePanelDidTapClipboard(_: SidePanelView) {
            // Phase 5 — the button is disabled until then, so this never
            // actually fires yet.
        }

        func sidePanelDidStepCursor(_: SidePanelView, direction: MoveDirection) {
            delegate?.keyGridView(self, didStepCursorFromSidePanel: direction)
        }
    }
#endif
