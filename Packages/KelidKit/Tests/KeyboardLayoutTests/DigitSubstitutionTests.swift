import KelidSettings
@testable import KeyboardLayout
import Testing

@Suite("DigitSubstitution and NumberRowBuilder")
struct DigitSubstitutionTests {
    @Test("persian mode leaves a Persian-digit page untouched")
    func persianModeIsNoOp() {
        let page = PageDefinition(rows: [[KeyDefinition(out: "۱"), KeyDefinition(out: "۲")]])
        let result = DigitSubstitution.apply(to: page, mode: .persian)
        #expect(result == page)
    }

    @Test("latin mode swaps Persian digits to Latin and adds the Persian digit as an alternate")
    func latinModeSwaps() {
        let page = PageDefinition(rows: [[KeyDefinition(out: "۱"), KeyDefinition(out: "ض")]])
        let result = DigitSubstitution.apply(to: page, mode: .latin)
        #expect(result.rows[0][0].out == "1")
        #expect(result.rows[0][0].alternates == ["۱"])
        // Non-digit keys are untouched.
        #expect(result.rows[0][1].out == "ض")
        #expect(result.rows[0][1].alternates == nil)
    }

    @Test("NumberRowBuilder produces 10 digits in the right script and order")
    func numberRowBuilderProducesTenDigits() {
        let persian = NumberRowBuilder.row(mode: .persian)
        #expect(persian.map(\.out) == ["۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹", "۰"])
        let latin = NumberRowBuilder.row(mode: .latin)
        #expect(latin.map(\.out) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
    }

    @Test("prepending adds exactly one row when showNumberRow is on, none when off")
    func prependingAddsExactlyOneRow() {
        let page = PageDefinition(rows: [["a", "b"], ["c"]])
        let withNumberRow = NumberRowBuilder.prepending(page, mode: .latin, showNumberRow: true)
        #expect(withNumberRow.rows.count == 3)
        #expect(withNumberRow.rows[0].map(\.out) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])

        let withoutNumberRow = NumberRowBuilder.prepending(page, mode: .latin, showNumberRow: false)
        #expect(withoutNumberRow == page)
    }
}
