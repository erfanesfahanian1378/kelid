#if canImport(UIKit)
    import UIKit

    /// The enlarged bubble shown above a key while it's pressed (task 3.3,
    /// `GeneralSettings.keyPopups`). Purely visual — `KeyGridView` owns the
    /// single shared instance and repositions/retexts it per touch; it never
    /// participates in hit-testing or touches itself.
    final class KeyCalloutView: UIView {
        private let label = UILabel()
        /// How far the bubble extends above the key's own top edge.
        static let riseHeight: CGFloat = 40

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.4
            addSubview(label)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: 1)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds
        }

        /// `keyFrame` is the key's own frame in the same coordinate space as
        /// `self.superview`; the bubble is centered above it, widened slightly,
        /// and clamped so it never draws past the container's edges.
        func show(text: String, above keyFrame: CGRect, fontSize: CGFloat, style: KeyStyle, containerBounds: CGRect) {
            label.text = text
            label.font = .systemFont(ofSize: fontSize * 1.5, weight: .regular)
            label.textColor = style.calloutText
            backgroundColor = style.calloutFill
            layer.cornerRadius = style.cornerRadius

            let width = max(keyFrame.width, keyFrame.width * 1.1)
            let height = keyFrame.height + Self.riseHeight
            var x = keyFrame.midX - width / 2
            x = min(max(x, containerBounds.minX), containerBounds.maxX - width)
            let y = keyFrame.minY - Self.riseHeight
            frame = CGRect(x: x, y: y, width: width, height: height)
            isHidden = false
            superview?.bringSubviewToFront(self)
        }

        func hide() {
            isHidden = true
        }
    }
#endif
