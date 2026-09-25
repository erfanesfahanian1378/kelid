#if canImport(UIKit)
    import UIKit

    /// Task 4.5: the empty area below the last key row (§6.3.1's
    /// `bottomPadding` + `bottomLift`) — drawn with the keyboard background
    /// and a subtle grab-handle line, purely visual (`isUserInteractionEnabled
    /// = false`; resize mode's own entry points are the toolbar icon and the
    /// Quick Settings button, task 4.3, not this view).
    final class BottomLiftView: UIView {
        private let handle = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            handle.layer.cornerRadius = 2
            addSubview(handle)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let width: CGFloat = 36
            let height: CGFloat = 4
            handle.frame = CGRect(x: bounds.midX - width / 2, y: 6, width: width, height: height)
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            handle.backgroundColor = style.labelColor.withAlphaComponent(0.25)
        }
    }
#endif
