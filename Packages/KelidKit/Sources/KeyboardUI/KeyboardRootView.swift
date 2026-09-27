#if canImport(UIKit)
    import UIKit

    /// The keyboard extension's whole view: toolbar strip + key grid (task 3.8).
    /// Plain frame layout, not Auto Layout/stack views — `KeyboardController`
    /// recomputes both rects on every `layoutSubviews`, driven by the same
    /// `KeyboardMetrics` the key layout itself uses, so the two stay in sync by
    /// construction rather than by separately-maintained constraints.
    public final class KeyboardRootView: UIView {
        let toolbarStrip = ToolbarStripView(frame: .zero)
        let keyGridView = KeyGridView(frame: .zero)

        /// Set by `KeyboardController` from `HeightCoordinator`'s own
        /// `toolbarHeight`/`toolbarVisible` inputs, so this view's internal
        /// split matches the height the host applied via its own constraint.
        var toolbarHeight: CGFloat = 44
        var toolbarVisible = true

        /// Task 11.3's backgrounds — at most one of these three is
        /// non-`nil`/visible at a time, matching whichever `KeyboardBackground`
        /// case `apply(style:)` last saw; the plain `.color` case uses none
        /// of them (`backgroundColor` alone is enough).
        private var gradientLayer: CAGradientLayer?
        private var backgroundImageView: UIImageView?
        private var blurView: UIVisualEffectView?
        private var lastImageURL: URL?
        /// `UIBlurEffect` doesn't expose the style it was created with as a
        /// readable property, so this is tracked separately to avoid
        /// rebuilding the (moderately expensive) blur view on every
        /// `apply(style:)` call when the material hasn't actually changed.
        private var lastBlurStyle: UIBlurEffect.Style?

        override public init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(toolbarStrip)
            addSubview(keyGridView)
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            let stripHeight = toolbarVisible ? toolbarHeight : 0
            toolbarStrip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: stripHeight)
            toolbarStrip.isHidden = !toolbarVisible
            keyGridView.frame = CGRect(x: 0, y: stripHeight, width: bounds.width, height: max(0, bounds.height - stripHeight))
            gradientLayer?.frame = bounds
            backgroundImageView?.frame = bounds
            blurView?.frame = bounds
        }

        func apply(style: KeyStyle) {
            backgroundColor = style.keyboardBackground
            applyBackground(style.background)
            toolbarStrip.apply(style: style)
        }

        private func applyBackground(_ background: KeyboardBackground) {
            switch background {
            case let .color(color):
                clearGradientAndImageAndMaterial()
                backgroundColor = color
            case let .gradient(colors, angleDegrees):
                clearImageAndMaterial()
                let layer = gradientLayer ?? {
                    let newLayer = CAGradientLayer()
                    self.layer.insertSublayer(newLayer, at: 0)
                    gradientLayer = newLayer
                    return newLayer
                }()
                layer.frame = bounds
                layer.colors = colors.map(\.cgColor)
                let radians = angleDegrees * .pi / 180
                // CAGradientLayer's start/end points are in the unit square
                // (0,0)–(1,1); this maps a compass-style angle (0° = left to
                // right, matching §6.8.1's own `angle` field) onto that.
                let dx = cos(radians) * 0.5
                let dy = sin(radians) * 0.5
                layer.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
                layer.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
            case let .image(url):
                clearGradientAndMaterial()
                if lastImageURL != url {
                    lastImageURL = url
                    backgroundImageView?.image = UIImage(contentsOfFile: url.path)
                }
                if backgroundImageView == nil {
                    let imageView = UIImageView(frame: bounds)
                    imageView.contentMode = .scaleAspectFill
                    imageView.clipsToBounds = true
                    imageView.image = UIImage(contentsOfFile: url.path)
                    insertSubview(imageView, at: 0)
                    backgroundImageView = imageView
                }
            case let .material(blurStyle):
                clearGradientAndImage()
                if blurView != nil, lastBlurStyle == blurStyle {
                    return
                }
                blurView?.removeFromSuperview()
                let newBlurView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
                newBlurView.frame = bounds
                insertSubview(newBlurView, at: 0)
                blurView = newBlurView
                lastBlurStyle = blurStyle
            }
        }

        private func clearGradientAndImageAndMaterial() {
            clearGradientAndImage()
            blurView?.removeFromSuperview()
            blurView = nil
            lastBlurStyle = nil
        }

        private func clearGradientAndMaterial() {
            gradientLayer?.removeFromSuperlayer()
            gradientLayer = nil
            blurView?.removeFromSuperview()
            blurView = nil
            lastBlurStyle = nil
        }

        private func clearImageAndMaterial() {
            backgroundImageView?.removeFromSuperview()
            backgroundImageView = nil
            lastImageURL = nil
            blurView?.removeFromSuperview()
            blurView = nil
        }

        private func clearGradientAndImage() {
            gradientLayer?.removeFromSuperlayer()
            gradientLayer = nil
            backgroundImageView?.removeFromSuperview()
            backgroundImageView = nil
            lastImageURL = nil
        }
    }
#endif
