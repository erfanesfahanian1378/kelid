#if canImport(UIKit)
    import CoreGraphics
    import KelidCore
    import KelidSettings
    import Observation

    /// Live state for one resize-mode session (task 4.3, §6.3.7). Created
    /// when resize mode starts (a copy of the current orientation's
    /// `SizeProfile`, plus the device default it started from), mutated by
    /// drag handles/preset taps, and discarded on **Done**/**Reset**/
    /// rotation without ever touching `SettingsStore` until `KeyboardController`
    /// applies the final result — dragging never itself persists anything.
    @MainActor
    @Observable
    public final class ResizeSession {
        /// What editing started from — `Done` is a no-op if nothing changed,
        /// and this is also the readout's implicit "0%" reference point.
        public let initial: SizeProfile
        /// §6.3.7's presets are relative to the *device default*
        /// (`DeviceSizeClass.portraitRowHeightDefault`), not to whatever the
        /// profile happened to be when resize mode opened.
        public let deviceDefaultRowHeight: CGFloat
        public let orientation: SizeOrientation
        /// The current page's row count when resize mode opened (4, or 5
        /// with the number row) — fixed for the session; the top handle's
        /// formula (§6.3.7) needs it, and there's no live layout to ask
        /// from inside the SwiftUI overlay itself.
        public let rowCount: Int

        public private(set) var rowHeight: CGFloat
        public private(set) var bottomLift: CGFloat
        public private(set) var oneHanded: OneHandedMode
        public private(set) var oneHandedWidthRatio: Double

        /// Fires once per gesture the moment the *default* row height is
        /// crossed (§6.3.7's "haptic tick... snap zone ± 3pt") — reset by
        /// each new drag gesture (`beginDrag`), not after every tick, so it
        /// fires at most once per continuous drag.
        public private(set) var didFireDefaultSnapHaptic = false

        private static let snapZone: CGFloat = 3
        private static let rowHeightRange: ClosedRange<CGFloat> = 30 ... 80
        private static let bottomLiftRange: ClosedRange<CGFloat> = 0 ... 80
        private static let widthRatioRange: ClosedRange<Double> = 0.60 ... 0.95

        public init(profile: SizeProfile, orientation: SizeOrientation, deviceDefaultRowHeight: CGFloat, rowCount: Int) {
            initial = profile
            self.orientation = orientation
            self.deviceDefaultRowHeight = deviceDefaultRowHeight
            self.rowCount = max(1, rowCount)
            rowHeight = profile.rowHeight
            bottomLift = profile.bottomLift
            oneHanded = profile.oneHanded
            oneHandedWidthRatio = profile.oneHandedWidthRatio
        }

        /// Call when a drag gesture starts, so the snap haptic can fire
        /// again on the next gesture.
        public func beginDrag() {
            didFireDefaultSnapHaptic = false
        }

        /// §6.3.7's top-handle formula: `rowHeight = (initialKeysHeight −
        /// dy) / rows`. `dy` is the total drag translation since gesture
        /// start (positive = dragged down = shorter keys); `initialKeysHeight`
        /// is `initial.rowHeight × rows`, matching "drag the top handle up
        /// to grow the keyboard."
        public func applyTopDrag(totalTranslationY dy: CGFloat) {
            let initialKeysHeight = initial.rowHeight * CGFloat(rowCount)
            setRowHeight((initialKeysHeight - dy) / CGFloat(rowCount))
        }

        /// Bottom handle → `bottomLift`; dragging down increases lift.
        public func applyBottomDrag(totalTranslationY dy: CGFloat) {
            bottomLift = (initial.bottomLift + dy).clamped(to: Self.bottomLiftRange)
        }

        /// Dragging the left edge inward turns on one-handed **right** (the
        /// content moves away from the edge you dragged) and sets the width
        /// ratio from how far you dragged (§6.3.7: "dragging an edge inward
        /// turns on one-handed mode on the *opposite* side").
        public func applyLeftEdgeDrag(totalTranslationX dx: CGFloat, viewWidth: CGFloat) {
            guard viewWidth > 0, dx > 0 else { return }
            oneHanded = .right
            oneHandedWidthRatio = ratio(forInset: dx, viewWidth: viewWidth)
        }

        public func applyRightEdgeDrag(totalTranslationX dx: CGFloat, viewWidth: CGFloat) {
            guard viewWidth > 0, dx < 0 else { return }
            oneHanded = .left
            oneHandedWidthRatio = ratio(forInset: -dx, viewWidth: viewWidth)
        }

        /// Center drag while already one-handed switches side outright
        /// (§6.3.7's "center drag (one-handed only) → switch side (snaps)")
        /// — a discrete snap, not a continuous drag value.
        public func switchOneHandedSide() {
            switch oneHanded {
            case .left: oneHanded = .right
            case .right: oneHanded = .left
            case .off: break
            }
        }

        public func applyPreset(_ preset: ResizePreset) {
            setRowHeight(deviceDefaultRowHeight * preset.multiplier)
        }

        public func reset() {
            rowHeight = initial.rowHeight
            bottomLift = initial.bottomLift
            oneHanded = initial.oneHanded
            oneHandedWidthRatio = initial.oneHandedWidthRatio
        }

        /// The profile to persist on **Done**.
        public func resultProfile() -> SizeProfile {
            var profile = initial
            profile.rowHeight = rowHeight
            profile.bottomLift = bottomLift
            profile.oneHanded = oneHanded
            profile.oneHandedWidthRatio = oneHandedWidthRatio
            return profile
        }

        public var readoutText: String {
            let widthPercent = oneHanded == .off ? 100 : Int((oneHandedWidthRatio * 100).rounded())
            return "Row \(Int(rowHeight.rounded()))pt · Lift \(Int(bottomLift.rounded())) · Width \(widthPercent)%"
        }

        private func ratio(forInset inset: CGFloat, viewWidth: CGFloat) -> Double {
            let contentWidth = max(240, viewWidth - inset) // §6.3.3: one-handed content width ≥ 240pt
            return Double(contentWidth / viewWidth).clamped(to: Self.widthRatioRange)
        }

        private func setRowHeight(_ value: CGFloat) {
            let clamped = value.clamped(to: Self.rowHeightRange)
            if !didFireDefaultSnapHaptic, abs(clamped - deviceDefaultRowHeight) <= Self.snapZone {
                didFireDefaultSnapHaptic = true
            }
            rowHeight = clamped
        }
    }

    public enum ResizePreset: String, CaseIterable, Sendable {
        case s, m, l, xl

        public var multiplier: CGFloat {
            switch self {
            case .s: 0.88
            case .m: 1.0
            case .l: 1.12
            case .xl: 1.25
            }
        }

        public var label: String {
            rawValue.uppercased()
        }
    }
#endif
