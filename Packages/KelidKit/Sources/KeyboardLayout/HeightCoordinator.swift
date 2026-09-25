import CoreGraphics

/// §6.3.1's height formula (task 3.13): row count × `rowHeight` + toolbar +
/// paddings. Pure calculation — applying it via a height constraint
/// (§6.3.4) is the keyboard target's job (`KeyboardViewController`), since
/// that part needs `NSLayoutConstraint`.
public enum HeightCoordinator {
    public static let topPadding: CGFloat = 4
    public static let bottomPadding: CGFloat = 4

    public static func totalHeight(rowCount: Int, metrics: KeyboardMetrics, toolbarVisible: Bool) -> CGFloat {
        let toolbarHeight = toolbarVisible ? metrics.toolbarHeight : 0
        return toolbarHeight + topPadding + CGFloat(rowCount) * metrics.rowHeight + bottomPadding + metrics.bottomLift
    }
}
