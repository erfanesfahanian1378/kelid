@testable import KeyboardLayout
import Testing

@Suite("NumpadBuilder")
struct NumpadBuilderTests {
    @Test("decimalPad shows a period, then 0, then backspace")
    func decimalPadShowsPeriod() {
        let row = NumpadBuilder.row4(showDecimalPoint: true, showGlobe: false)
        #expect(row.map { $0.out ?? $0.action.rawValue } == [".", "0", "backspace"])
    }

    @Test("numberPad with a globe key shows the globe, then 0, then backspace")
    func numberPadWithGlobe() {
        let row = NumpadBuilder.row4(showDecimalPoint: false, showGlobe: true)
        #expect(row.map { $0.out ?? $0.action.rawValue } == ["globe", "0", "backspace"])
    }

    @Test("plain numberPad has an empty leading spacer, then 0, then backspace")
    func plainNumberPad() {
        let row = NumpadBuilder.row4(showDecimalPoint: false, showGlobe: false)
        #expect(row[0].isSpacer)
        #expect(row.map { $0.out ?? $0.action.rawValue }[1...] == ["0", "backspace"])
    }
}
