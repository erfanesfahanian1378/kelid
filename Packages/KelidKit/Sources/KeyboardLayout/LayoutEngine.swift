import CoreGraphics

/// One placed, tappable key (never a spacer — those exist only to shape the
/// row and produce no `ComputedKey`).
public struct ComputedKey: Sendable, Equatable {
    public let definition: KeyDefinition
    public let rowIndex: Int
    public let indexInRow: Int
    /// The key's visual rect (with gaps to its neighbors).
    public let frame: CGRect
    /// Expanded hit-test rect (§6.3.5): reaches halfway into each
    /// neighboring gap, all the way to the view edge for the first/last key
    /// in a row, and spans the full row height (gaps included) vertically —
    /// no dead zones.
    public let hitFrame: CGRect
}

public struct ComputedRow: Sendable, Equatable {
    public let keys: [ComputedKey]
    public let frame: CGRect
}

public struct ComputedLayout: Sendable, Equatable {
    public let rows: [ComputedRow]
    /// The key area (§6.3.6): equal to `bounds` unless one-handed mode is
    /// on, in which case it's the narrower `oneHandedWidthRatio` slice
    /// aligned to the chosen side.
    public let contentRect: CGRect
    public let bounds: CGRect

    /// Nearest-in-row fallback (task 2.6): a point inside some row's
    /// vertical span always resolves to a key — the one whose hit frame
    /// contains the point, or (in a spacer/gap) the key whose center is
    /// horizontally closest. Returns `nil` only if `point` isn't within any
    /// row's vertical span at all.
    public func key(at point: CGPoint) -> ComputedKey? {
        guard let row = rows.first(where: { $0.frame.minY <= point.y && point.y < $0.frame.maxY }) else {
            return nil
        }
        if let hit = row.keys.first(where: { $0.hitFrame.contains(point) }) {
            return hit
        }
        return row.keys.min { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }
    }
}

/// Computes frames, hit frames and the one-handed content rect for a page
/// (task 2.6). Pure geometry — no rendering, no touches (§8 Phase 2 scope).
public enum LayoutEngine {
    public static func compute(
        page: PageDefinition,
        in bounds: CGRect,
        metrics: KeyboardMetrics,
        direction _: Direction
    ) -> ComputedLayout {
        let contentRect = oneHandedContentRect(bounds: bounds, metrics: metrics)

        // §6.3.1's `keyUnitWidth` formula is per-row, which is correct for
        // ordinary pages (row totals are authored, via spacers/wider
        // special keys, to already align visually — see en.qwerty.json).
        // A row containing a `flex` key (bottom rows only) has no such
        // authored total to divide by, so its *fixed* keys instead share
        // the reference unit width computed from the page's first row, and
        // the flex key absorbs whatever's left — keeping bottom-row keys
        // visually consistent with the letter grid above them. This isn't
        // spelled out by §6.3.1 (written for non-flex rows); see the
        // decision log for Phase 2.
        let referenceUnitWidth = page.rows.first.map { unitWidth(for: $0, contentWidth: contentRect.width, metrics: metrics) }

        var rows: [ComputedRow] = []
        var y = contentRect.minY
        for (rowIndex, rowKeys) in page.rows.enumerated() {
            let rowFrame = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: metrics.rowHeight)
            let keys = computeRow(
                rowKeys, rowIndex: rowIndex, rowFrame: rowFrame, metrics: metrics,
                viewBounds: bounds, referenceUnitWidth: referenceUnitWidth
            )
            rows.append(ComputedRow(keys: keys, frame: rowFrame))
            y += metrics.rowHeight
        }
        return ComputedLayout(rows: rows, contentRect: contentRect, bounds: bounds)
    }

    /// §6.3.6: one-handed mode narrows the key area to `oneHandedWidthRatio`
    /// of the full width, aligned to the chosen side. `.off` uses the full
    /// bounds.
    private static func oneHandedContentRect(bounds: CGRect, metrics: KeyboardMetrics) -> CGRect {
        switch metrics.oneHanded {
        case .off:
            return bounds
        case .left:
            let width = bounds.width * CGFloat(metrics.oneHandedWidthRatio)
            return CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        case .right:
            let width = bounds.width * CGFloat(metrics.oneHandedWidthRatio)
            return CGRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
        }
    }

    private static func totalUnits(_ row: [KeyDefinition]) -> Double {
        row.reduce(0) { $0 + ($1.isSpacer ? ($1.spacer ?? 0) : $1.width) }
    }

    /// §6.3.1: `(contentWidth − 2·sidePadding − (keysInRow − 1)·keyGapH) / Σ(widthUnits in row)`.
    private static func unitWidth(for row: [KeyDefinition], contentWidth: CGFloat, metrics: KeyboardMetrics) -> CGFloat {
        let units = totalUnits(row)
        guard units > 0, !row.isEmpty else { return 0 }
        let usableWidth = contentWidth - 2 * metrics.sidePadding - CGFloat(row.count - 1) * metrics.keyGapH
        return usableWidth / CGFloat(units)
    }

    private static func computeRow(
        _ rowKeys: [KeyDefinition],
        rowIndex: Int,
        rowFrame: CGRect,
        metrics: KeyboardMetrics,
        viewBounds: CGRect,
        referenceUnitWidth: CGFloat?
    ) -> [ComputedKey] {
        guard !rowKeys.isEmpty else { return [] }

        let hasFlex = rowKeys.contains(where: \.flex)
        let unit = hasFlex ? (referenceUnitWidth ?? 0) : unitWidth(for: rowKeys, contentWidth: rowFrame.width, metrics: metrics)

        let usableWidth = rowFrame.width - 2 * metrics.sidePadding - CGFloat(rowKeys.count - 1) * metrics.keyGapH
        let fixedUnits = hasFlex ? rowKeys.filter { !$0.flex }.reduce(0.0) { $0 + ($1.isSpacer ? ($1.spacer ?? 0) : $1.width) } : 0
        let flexCount = hasFlex ? rowKeys.count(where: \.flex) : 0
        let flexWidthEach: CGFloat = if hasFlex, flexCount > 0 {
            max(0, usableWidth - CGFloat(fixedUnits) * unit) / CGFloat(flexCount)
        } else {
            0
        }

        var x = rowFrame.minX + metrics.sidePadding
        var slots: [(key: KeyDefinition, frame: CGRect)] = []
        for key in rowKeys {
            let widthPt: CGFloat = if key.flex {
                flexWidthEach
            } else {
                CGFloat(key.isSpacer ? (key.spacer ?? 0) : key.width) * unit
            }
            let frame = CGRect(
                x: x, y: rowFrame.minY + metrics.keyGapV / 2,
                width: widthPt, height: metrics.rowHeight - metrics.keyGapV
            )
            slots.append((key, frame))
            x += widthPt + metrics.keyGapH
        }

        // "First/last key" for edge-extension (§6.3.5) means the first/last
        // *real* key — a row can start or end with a spacer (en.qwerty's
        // row 2 does, on both ends), which must not itself claim the edge.
        let nonSpacerIndices = slots.indices.filter { !slots[$0].key.isSpacer }
        let firstNonSpacerIndex = nonSpacerIndices.first
        let lastNonSpacerIndex = nonSpacerIndices.last

        var keys: [ComputedKey] = []
        for (index, slot) in slots.enumerated() {
            guard !slot.key.isSpacer else { continue }
            var hitMinX = slot.frame.minX - metrics.keyGapH / 2
            var hitMaxX = slot.frame.maxX + metrics.keyGapH / 2
            if index == firstNonSpacerIndex {
                hitMinX = viewBounds.minX
            }
            if index == lastNonSpacerIndex {
                hitMaxX = viewBounds.maxX
            }
            let hitFrame = CGRect(x: hitMinX, y: rowFrame.minY, width: hitMaxX - hitMinX, height: rowFrame.height)
            keys.append(ComputedKey(definition: slot.key, rowIndex: rowIndex, indexInRow: index, frame: slot.frame, hitFrame: hitFrame))
        }
        return keys
    }
}
