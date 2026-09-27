#if canImport(UIKit)
    import KelidSettings
    import KeyboardLayout
    import UIKit

    /// One key's visual representation (task 3.1). `KeyGridView` pools and
    /// reuses these (diffed by a position-based id — see `KeyGridView`) instead
    /// of recreating them on every layout pass, since layouts recompute on
    /// every size/settings change but the same logical key usually stays put.
    final class KeyView: UIView {
        private let label = UILabel()
        private(set) var isSpecial = false
        private var isAccent = false
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
            isAccent: Bool = false,
            isPressed: Bool,
            accessibilityLabel: String
        ) {
            self.frame = frame
            self.style = style
            self.isSpecial = isSpecial
            self.isAccent = isAccent

            layer.cornerRadius = style.cornerRadius
            layer.shadowOpacity = style.shadowOpacity
            layer.shadowRadius = style.shadowRadius
            layer.shadowOffset = CGSize(width: 0, height: style.shadowOffsetY)
            layer.shadowColor = UIColor.black.cgColor
            layer.borderWidth = style.borderWidth
            layer.borderColor = style.borderColor.cgColor

            label.text = displayText
            label.font = labelFont(fontSize: fontSize, isSpecial: isSpecial, style: style)
            label.textColor = isAccent ? style.accentLabelColor : (isSpecial ? style.specialLabelColor : style.labelColor)

            applyFill(isPressed: isPressed)
            self.accessibilityLabel = accessibilityLabel
        }

        /// §6.8.4: the user's chosen Persian/Latin font family (`nil` means
        /// "use the system font"), at `fontSize * theme.fonts.scale`, with
        /// the theme's own weight for whichever role (`normal`/`special`)
        /// applies. Text is mixed-script in general (a Persian key label can
        /// include Latin digits, etc.), so this always picks by whether the
        /// *label itself* looks Persian rather than by the keyboard's
        /// current input language — simplified here to: prefer the Persian
        /// font whenever one is configured and the text contains any
        /// Persian-range character, else the Latin choice.
        private func labelFont(fontSize: CGFloat, isSpecial: Bool, style: KeyStyle) -> UIFont {
            let weight = isSpecial ? style.specialLabelFontWeight : style.labelFontWeight
            let scaledSize = fontSize * style.fontScale
            let looksPersian = label.text?.unicodeScalars.contains { (0x0600 ... 0x06FF).contains($0.value) } ?? false
            if looksPersian, let persianFontName = style.persianFontName, let font = UIFont(name: persianFontName, size: scaledSize) {
                return font
            }
            switch style.latinFontChoice {
            case .system:
                return .systemFont(ofSize: scaledSize, weight: weight)
            case .rounded:
                let descriptor = UIFont.systemFont(ofSize: scaledSize, weight: weight).fontDescriptor
                    .withDesign(.rounded) ?? UIFont.systemFont(ofSize: scaledSize, weight: weight).fontDescriptor
                return UIFont(descriptor: descriptor, size: scaledSize)
            case .monospaced:
                return .monospacedSystemFont(ofSize: scaledSize, weight: weight)
            }
        }

        /// Pressed-state fill change, plus task 11.7's key-press animation
        /// (`.none`/`.pop`/`.fade`) on press-down only — release is always a
        /// plain, immediate fill change, matching how the built-in iOS
        /// keyboard's own key animation works (the "pop" is a press
        /// acknowledgment, not a two-way transition).
        func setPressed(_ isPressed: Bool, animation: KeyPressAnimation = .none) {
            applyFill(isPressed: isPressed)
            guard isPressed, animation != .none, !UIAccessibility.isReduceMotionEnabled else { return }
            switch animation {
            case .none:
                break
            case .pop:
                transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                UIView.animate(withDuration: 0.08) { self.transform = .identity }
            case .fade:
                alpha = 0.55
                UIView.animate(withDuration: 0.12) { self.alpha = 1 }
            }
        }

        private func applyFill(isPressed: Bool) {
            let normalFill = isAccent ? style.accentKeyFill : (isSpecial ? style.specialKeyFill : style.keyFill)
            let pressedFill = isAccent ? style.pressedAccentKeyFill : (isSpecial ? style.pressedSpecialKeyFill : style.pressedKeyFill)
            backgroundColor = isPressed ? pressedFill : normalFill
        }
    }
#endif
