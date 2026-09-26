@testable import PersianText
import Testing

@Suite("PersianConfusionGroups (§6.6.6)")
struct PersianConfusionGroupsTests {
    @Test("identical characters cost 0")
    func identicalCostsZero() {
        #expect(PersianConfusionGroups.substitutionCost("ا", "ا") == 0)
    }

    @Test("documented pair costs match §6.6.6's table exactly")
    func documentedPairsMatchTable() {
        #expect(PersianConfusionGroups.substitutionCost("ا", "آ") == 0.2)
        #expect(PersianConfusionGroups.substitutionCost("آ", "ا") == 0.2) // symmetric
        #expect(PersianConfusionGroups.substitutionCost("ی", "ئ") == 0.3)
        #expect(PersianConfusionGroups.substitutionCost("و", "ؤ") == 0.3)
        #expect(PersianConfusionGroups.substitutionCost("ت", "ط") == 0.4)
        #expect(PersianConfusionGroups.substitutionCost("ه", "ح") == 0.5)
        #expect(PersianConfusionGroups.substitutionCost("ق", "غ") == 0.4)
        #expect(PersianConfusionGroups.substitutionCost("ا", "ع") == 0.6)
    }

    @Test("a 3-way group costs the same between every pair of its members")
    func threeWayGroupCostsUniform() {
        #expect(PersianConfusionGroups.substitutionCost("س", "ص") == 0.4)
        #expect(PersianConfusionGroups.substitutionCost("س", "ث") == 0.4)
        #expect(PersianConfusionGroups.substitutionCost("ص", "ث") == 0.4)
    }

    @Test("a 4-way group costs the same between every pair of its members")
    func fourWayGroupCostsUniform() {
        for a in ["ز", "ذ", "ض", "ظ"] {
            for b in ["ز", "ذ", "ض", "ظ"] where a != b {
                #expect(PersianConfusionGroups.substitutionCost(Character(a), Character(b)) == 0.4)
            }
        }
    }

    @Test("a letter in two different groups has the correct cost for each")
    func letterInTwoGroupsHasDistinctCosts() {
        // "ا" is in both the ا↔آ group (0.2) and the ا↔ع group (0.6).
        #expect(PersianConfusionGroups.substitutionCost("ا", "آ") == 0.2)
        #expect(PersianConfusionGroups.substitutionCost("ا", "ع") == 0.6)
    }

    @Test("unrelated characters return nil")
    func unrelatedCharactersReturnNil() {
        #expect(PersianConfusionGroups.substitutionCost("ب", "پ") == nil)
        #expect(PersianConfusionGroups.substitutionCost("a", "b") == nil)
    }
}
