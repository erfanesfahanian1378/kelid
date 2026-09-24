@testable import KelidCore
import Testing

@Suite("KelidCorePlaceholder")
struct KelidCorePlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(KelidCorePlaceholder().isReady)
    }
}
