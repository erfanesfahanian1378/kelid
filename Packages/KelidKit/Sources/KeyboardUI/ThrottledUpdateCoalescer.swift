#if canImport(UIKit)
    import QuartzCore

    /// Coalesces frequent updates (e.g. live resize-drag values) to at most
    /// `targetFPS` times per second via `CADisplayLink`, applying only the
    /// *latest* scheduled closure on each tick (task 4.3's own pitfall:
    /// "changing the height constraint on every touch-move floods the host
    /// with layout passes"). Scheduling faster than `targetFPS` is free —
    /// only the last call before each tick actually runs.
    @MainActor
    final class ThrottledUpdateCoalescer {
        private var displayLink: CADisplayLink?
        private var pending: (() -> Void)?
        private let targetFPS: Int

        init(targetFPS: Int = 30) {
            self.targetFPS = targetFPS
        }

        func schedule(_ apply: @escaping () -> Void) {
            pending = apply
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFramesPerSecond = targetFPS
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        /// Stops the display link and drops anything still pending — call
        /// when the drag/session ends so it isn't ticking for nothing.
        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            pending = nil
        }

        @objc private func tick() {
            guard let pending else { return }
            self.pending = nil
            pending()
        }
    }
#endif
