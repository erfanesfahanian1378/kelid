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
        /// of them (`backgroundColor` alone is enough). `effectView` backs
        /// both `.material` and `.glass` — they're both "one
        /// `UIVisualEffectView` at index 0," just with a different
        /// `UIVisualEffect` subclass installed.
        private var gradientLayer: CAGradientLayer?
        private var backgroundImageView: UIImageView?
        private var effectView: UIVisualEffectView?
        private var lastImageURL: URL?
        /// Neither `UIBlurEffect` nor `UIGlassEffect` expose the values they
        /// were created with as readable properties, so the *inputs* are
        /// tracked separately to avoid rebuilding the (moderately expensive)
        /// effect view on every `apply(style:)` call when nothing actually
        /// changed.
        private enum AppliedEffect: Equatable {
            case blur(UIBlurEffect.Style)
            case glass(tint: UIColor?)
        }

        private var lastAppliedEffect: AppliedEffect?

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
            effectView?.frame = bounds
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
                applyEffect(.blur(blurStyle)) { UIVisualEffectView(effect: UIBlurEffect(style: blurStyle)) }
            case let .glass(tint):
                clearGradientAndImage()
                applyEffect(.glass(tint: tint)) { Self.makeGlassEffectView(tint: tint) }
            }
        }

        /// Shared install/skip-if-unchanged logic for `.material`/`.glass` —
        /// both just swap in a differently-configured `UIVisualEffectView`
        /// at index 0, so the actual view-management code is identical; only
        /// which `UIVisualEffect` gets built differs.
        private func applyEffect(_ desired: AppliedEffect, makeView: () -> UIVisualEffectView) {
            if effectView != nil, lastAppliedEffect == desired {
                return
            }
            effectView?.removeFromSuperview()
            let newEffectView = makeView()
            newEffectView.frame = bounds
            insertSubview(newEffectView, at: 0)
            effectView = newEffectView
            lastAppliedEffect = desired
        }

        /// Real Liquid Glass (`UIGlassEffect`) on iOS 26+; `UIGlassEffect`
        /// doesn't exist on earlier OS versions the app still supports
        /// (`project.yml`'s `deploymentTarget` is iOS 17), so this falls
        /// back to the same plain system-material blur `.material` themes
        /// use — a real, if less dynamic, translucent look rather than a
        /// crash or a silently-missing background.
        private static func makeGlassEffectView(tint: UIColor?) -> UIVisualEffectView {
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect()
                glass.tintColor = tint
                return UIVisualEffectView(effect: glass)
            }
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }

        private func clearGradientAndImageAndMaterial() {
            clearGradientAndImage()
            effectView?.removeFromSuperview()
            effectView = nil
            lastAppliedEffect = nil
        }

        private func clearGradientAndMaterial() {
            gradientLayer?.removeFromSuperlayer()
            gradientLayer = nil
            effectView?.removeFromSuperview()
            effectView = nil
            lastAppliedEffect = nil
        }

        private func clearImageAndMaterial() {
            backgroundImageView?.removeFromSuperview()
            backgroundImageView = nil
            lastImageURL = nil
            effectView?.removeFromSuperview()
            effectView = nil
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
