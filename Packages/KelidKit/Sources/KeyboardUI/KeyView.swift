#if canImport(UIKit)
    import KeyboardLayout
    import UIKit

    /// One key's visual representation (task 3.1). `KeyGridView` pools and
    /// reuses these (diffed by a position-based id — see `KeyGridView`) instead
    /// of recreating them on every layout pass, since layouts recompute on
    /// every size/settings change but the same logical key usually stays put.
    final class KeyView: UIView {
        private let label = UILabel()
        private(set) var isSpecial = false
        private var style: KeyStyle = .light

        override init(frame: CGRect) {
            super.init(frame: frame)
            // KeyGridView does its own hit-testing via ComputedLayout — key
            // views themselves never participate in the responder chain.
            isUserInteractionEnabled = false
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            addSubview(label)
            isAccessibilityElement = true
            accessibilityTraits = .keyboardKey
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        }

        func configure(
            frame: CGRect,
            displayText: String,
            fontSize: CGFloat,
            style: KeyStyle,
            isSpecial: Bool,
            isPressed: Bool,
            accessibilityLabel: String
        ) {
            self.frame = frame
            self.style = style
            self.isSpecial = isSpecial

            layer.cornerRadius = style.cornerRadius
            layer.shadowOpacity = style.shadowOpacity
            layer.shadowRadius = style.shadowRadius
            layer.shadowOffset = CGSize(width: 0, height: style.shadowOffsetY)
            layer.shadowColor = UIColor.black.cgColor

            label.text = displayText
            label.font = .systemFont(ofSize: fontSize, weight: isSpecial ? style.specialLabelFontWeight : style.labelFontWeight)
            label.textColor = isSpecial ? style.specialLabelColor : style.labelColor

            applyFill(isPressed: isPressed)
            self.accessibilityLabel = accessibilityLabel
        }

        /// Pressed-state changes the fill without animation (task 3.1 — real
        /// animation options arrive in Phase 11).
        func setPressed(_ isPressed: Bool) {
            applyFill(isPressed: isPressed)
        }

        private func applyFill(isPressed: Bool) {
            if isPressed {
                backgroundColor = isSpecial ? style.pressedSpecialKeyFill : style.pressedKeyFill
            } else {
                backgroundColor = isSpecial ? style.specialKeyFill : style.keyFill
            }
        }
    }
#endif
