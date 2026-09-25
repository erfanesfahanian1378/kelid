/// Small helper used by every settings group's `clamped()` (PLAN.md §6.1.1:
/// `clamped()` enforces every range in the settings catalog, run after
/// decoding and before saving).
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
