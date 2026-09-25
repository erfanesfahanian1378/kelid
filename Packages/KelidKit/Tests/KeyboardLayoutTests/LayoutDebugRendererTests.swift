import CoreGraphics
import KelidSettings
@testable import KeyboardLayout
import Testing

@Suite("LayoutDebugRenderer")
struct LayoutDebugRendererTests {
    @Test("renders one line per row, labels separated by spaces")
    func rendersRowsAndLabels() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 108)
        let page = PageDefinition(rows: [["a", "b"], ["c"]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: KeyboardMetrics(sizeProfile: .portraitDefault), direction: .ltr)
        #expect(LayoutDebugRenderer.render(layout) == "a b\nc")
    }

    @Test("a wider-than-1-unit key shows its width in parentheses")
    func widthAnnotationForWideKeys() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 54)
        let page = PageDefinition(rows: [["a", KeyDefinition(label: "⌫", action: .backspace, width: 1.5)]])
        let layout = LayoutEngine.compute(page: page, in: bounds, metrics: KeyboardMetrics(sizeProfile: .portraitDefault), direction: .ltr)
        #expect(LayoutDebugRenderer.render(layout) == "a ⌫(1.5)")
    }

    @Test("fa.standard renders with the exact §6.2.2 row order at 390pt")
    func faStandardRendersInSpecOrder() throws {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 224)
        let file = LayoutRepository().layout(id: "fa.standard")
        let layout = try LayoutEngine.compute(
            page: #require(file[.letters]),
            in: bounds,
            metrics: KeyboardMetrics(sizeProfile: .portraitDefault),
            direction: .rtl
        )
        let rendered = LayoutDebugRenderer.render(layout)
        #expect(rendered == """
        ض ص ث ق ف غ ع ه خ ح ج چ
        ش س ی ب ل ا ت ن م ک گ
        ظ ط ژ ز ر ذ د پ و ⌫(1.5)
        """)
    }
}
