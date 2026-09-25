import CoreGraphics
import KelidCore
import KelidSettings

/// Resolved geometry inputs for `LayoutEngine.compute` (task 2.7), derived
/// from a `SizeProfile` (§6.3.2's device-class defaults already baked into
/// whichever profile is passed in).
public struct KeyboardMetrics: Sendable, Equatable {
    public var rowHeight: CGFloat
    public var toolbarHeight: CGFloat
    public var bottomLift: CGFloat
    public var sidePadding: CGFloat
    public var keyGapH: CGFloat
    public var keyGapV: CGFloat
    public var fontScale: Double
    public var oneHanded: OneHandedMode
    public var oneHandedWidthRatio: Double

    public init(sizeProfile: SizeProfile) {
        rowHeight = sizeProfile.rowHeight
        toolbarHeight = sizeProfile.toolbarHeight
        bottomLift = sizeProfile.bottomLift
        sidePadding = sizeProfile.sidePadding
        keyGapH = sizeProfile.keyGapH
        keyGapV = sizeProfile.keyGapV
        fontScale = sizeProfile.fontScale
        oneHanded = sizeProfile.oneHanded
        oneHandedWidthRatio = sizeProfile.oneHandedWidthRatio
    }

    /// §6.3.1: `keyVisualHeight = rowHeight − keyGapV`.
    public var keyVisualHeight: CGFloat {
        rowHeight - keyGapV
    }

    /// §6.3.1/task 2.7: `baseFontSize = keyVisualHeight × 0.52 × fontScale`,
    /// clamped 14–30 pt.
    public var baseFontSize: CGFloat {
        (keyVisualHeight * 0.52 * CGFloat(fontScale)).clamped(to: 14 ... 30)
    }
}
