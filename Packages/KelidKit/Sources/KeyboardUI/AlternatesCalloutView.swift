#if canImport(UIKit)
    import KeyboardLayout
    import UIKit

    /// The horizontal strip of long-press alternates (task 3.4, §6.2.1/§6.4.12).
    /// Lays the primary character out first, then the alternates, in reading
    /// `direction` — matching `KeyTouchTracker.alternateIndex`'s own geometry so
    /// the highlighted cell always agrees with what a lift-off there commits.
    /// `KeyGridView` owns the single shared instance and drives it purely from
    /// `alternatesShown`/`alternateSelectionChanged`/hide events; it never
    /// participates in hit-testing or touches itself.
    final class AlternatesCalloutView: UIView {
        private var cellLabels: [UILabel] = []
        private var primaryText = ""
        private var alternates: [String] = []
        private var direction: Direction = .ltr

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
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

        func show(
            primary: String,
            alternates: [String],
            direction: Direction,
            above keyFrame: CGRect,
            fontSize: CGFloat,
            style: KeyStyle,
            containerBounds: CGRect
        ) {
            primaryText = primary
            self.alternates = alternates
            self.direction = direction
            backgroundColor = style.keyFill
            layer.cornerRadius = style.cornerRadius

            let cellWidth = keyFrame.width
            let cellHeight = keyFrame.height + KeyCalloutView.riseHeight
            let totalCells = alternates.count + 1
            let width = cellWidth * CGFloat(totalCells)

            rebuildLabels(count: totalCells, style: style, fontSize: fontSize)
            // Screen-left-to-right order. LTR: primary is leftmost (at the
            // key's own slot), alternates extend rightward ("forward"). RTL:
            // "forward" is leftward, so alternates extend left of the key and
            // the primary ends up rightmost — matching `KeyTouchTracker
            // .alternateIndex`'s geometry, which measures offset from
            // `key.center` in that same direction.
            let orderedTexts = direction == .rtl ? (alternates.reversed() + [primary]) : ([primary] + alternates)
            for (index, label) in cellLabels.enumerated() {
                label.text = orderedTexts[index]
                label.frame = CGRect(x: CGFloat(index) * cellWidth, y: 0, width: cellWidth, height: cellHeight)
            }

            // The primary key's own slot never moves; alternates extend outward
            // from it in the reading direction (matches `KeyTouchTracker`'s
            // `alternateIndex` geometry, which measures offset from
            // `key.center` along that same direction).
            let x = direction == .rtl ? keyFrame.maxX - width : keyFrame.minX
            let y = keyFrame.minY - KeyCalloutView.riseHeight
            frame = CGRect(x: min(max(x, containerBounds.minX), containerBounds.maxX - width), y: y, width: width, height: cellHeight)
            highlight(index: nil, style: style)
            isHidden = false
            superview?.bringSubviewToFront(self)
        }

        /// `nil` means the primary character (no alternate chosen).
        func setSelection(_ index: Int?, style: KeyStyle) {
            highlight(index: index, style: style)
        }

        func hide() {
            isHidden = true
            cellLabels.forEach { $0.removeFromSuperview() }
            cellLabels.removeAll()
        }

        private func rebuildLabels(count: Int, style: KeyStyle, fontSize: CGFloat) {
            cellLabels.forEach { $0.removeFromSuperview() }
            cellLabels = (0 ..< count).map { _ in
                let label = UILabel()
                label.textAlignment = .center
                label.font = .systemFont(ofSize: fontSize * 1.2, weight: .regular)
                label.textColor = style.labelColor
                label.adjustsFontSizeToFitWidth = true
                addSubview(label)
                return label
            }
        }

        /// `selectedIndex` (from `KeyTouchEvent.alternateSelectionChanged`) is
        /// an index into `alternates`, or `nil` for the primary character —
        /// translated into a position in `cellLabels`, whose order depends on
        /// `direction` (see `show`).
        private func highlight(index: Int?, style: KeyStyle) {
            let selectedPosition: Int = if let index {
                direction == .rtl ? (alternates.count - 1 - index) : index + 1
            } else {
                direction == .rtl ? alternates.count : 0
            }
            for (position, label) in cellLabels.enumerated() {
                label.backgroundColor = position == selectedPosition ? style.pressedKeyFill : .clear
            }
        }
    }
#endif
