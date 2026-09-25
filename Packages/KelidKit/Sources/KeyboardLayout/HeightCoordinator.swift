import CoreGraphics
import KelidSettings

/// §6.3.1's height formula (task 3.13): row count × `rowHeight` + toolbar +
/// paddings. Pure calculation — applying it via a height constraint
/// (§6.3.4) is the keyboard target's job (`KeyboardViewController`), since
/// that part needs `NSLayoutConstraint`.
public enum HeightCoordinator {
    public static let topPadding: CGFloat = 4
    public static let bottomPadding: CGFloat = 4

    /// §6.1.3's own `rowHeight` floors — `clampedMetrics` won't reduce
    /// `rowHeight` below these even if the screen-fraction budget (§6.3.3)
    /// isn't met yet at that point; going lower than the settings' own
    /// allowed range would produce a keyboard already unreadable long
    /// before this clamp's job (fitting the screen) is the real problem.
    private static func minRowHeight(for orientation: SizeOrientation) -> CGFloat {
        switch orientation {
        case .portrait: 38
        case .landscape: 30
        }
    }

    public static func totalHeight(rowCount: Int, metrics: KeyboardMetrics, toolbarVisible: Bool) -> CGFloat {
        let toolbarHeight = toolbarVisible ? metrics.toolbarHeight : 0
        return toolbarHeight + topPadding + CGFloat(rowCount) * metrics.rowHeight + bottomPadding + metrics.bottomLift
    }

    /// §6.3.3: total height must stay within 60% (portrait) / 70%
    /// (landscape) of the actual device's screen height — something the
    /// static per-field ranges in §6.1.3 can't know about, since a
    /// generous `rowHeight`+`bottomLift` combination that's fine on a
    /// large phone can overflow a small one once multiplied by row count.
    /// Display-time only: reduces `bottomLift` first, then `rowHeight`
    /// (never below its own floor above), without persisting the
    /// reduction back to settings — the user's stored preference is
    /// unchanged, only what's shown right now is adjusted.
    public static func clampedMetrics(
        _ metrics: KeyboardMetrics,
        rowCount: Int,
        toolbarVisible: Bool,
        screenHeight: CGFloat,
        orientation: SizeOrientation
    ) -> KeyboardMetrics {
        var result = metrics
        let maxFraction: CGFloat = orientation == .portrait ? 0.60 : 0.70
        let maxHeight = screenHeight * maxFraction
        guard maxHeight > 0 else { return result }

        var excess = totalHeight(rowCount: rowCount, metrics: result, toolbarVisible: toolbarVisible) - maxHeight
        guard excess > 0 else { return result }

        let liftReduction = min(result.bottomLift, excess)
        result.bottomLift -= liftReduction
        excess -= liftReduction
        guard excess > 0, rowCount > 0 else { return result }

        let floor = minRowHeight(for: orientation)
        let rowHeightReduction = min(excess / CGFloat(rowCount), max(0, result.rowHeight - floor))
        result.rowHeight -= rowHeightReduction
        return result
    }
}
