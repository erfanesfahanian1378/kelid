/// Shared by every settings group's `clamped()` (PLAN.md §6.1.1) and by
/// anything else needing to enforce a range (e.g. `KeyboardMetrics`'
/// `baseFontSize`, §6.3.1). Lives in `KelidCore` since it's needed by
/// multiple modules that don't depend on each other.
public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
