@testable import PersianText
import Testing

@Suite("PersianTextPlaceholder")
struct PersianTextPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(PersianTextPlaceholder().isReady)
    }
}
