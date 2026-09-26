/// §6.6.6's Persian confusion groups — substitution costs for typo-tolerant
/// fuzzy search (Phase 8, task 8.4) between letters that are easy to
/// mistype or mishear because they sound alike or look alike, but that
/// `matchKey` doesn't already fold together (unlike, say, ي/ی, which
/// `matchKey` treats as fully identical).
public enum PersianConfusionGroups {
    /// `(a, b) -> substitution cost`, populated from every distinct pair
    /// within each §6.6.6 group. A letter can appear in more than one group
    /// with a different cost each time (e.g. "ا" costs 0.2 against "آ" but
    /// 0.6 against "ع") — pairs are keyed individually, so that's never a
    /// conflict.
    private static let costs: [Pair: Double] = {
        let groups: [(members: [Character], cost: Double)] = [
            (["ا", "آ"], 0.2),
            (["ی", "ئ"], 0.3),
            (["و", "ؤ"], 0.3),
            (["ت", "ط"], 0.4),
            (["س", "ص", "ث"], 0.4),
            (["ز", "ذ", "ض", "ظ"], 0.4),
            (["ه", "ح"], 0.5),
            (["ق", "غ"], 0.4),
            (["ا", "ع"], 0.6),
        ]
        var table: [Pair: Double] = [:]
        for group in groups {
            for a in group.members {
                for b in group.members where a != b {
                    table[Pair(a, b)] = group.cost
                }
            }
        }
        return table
    }()

    private struct Pair: Hashable {
        let a: Character
        let b: Character
        init(_ a: Character, _ b: Character) {
            self.a = a
            self.b = b
        }
    }

    /// `nil` if `a`/`b` aren't in the same confusion group — callers fall
    /// back to their own default substitution cost (proximity-based or 1.0)
    /// in that case.
    public static func substitutionCost(_ a: Character, _ b: Character) -> Double? {
        guard a != b else { return 0 }
        return costs[Pair(a, b)]
    }
}
