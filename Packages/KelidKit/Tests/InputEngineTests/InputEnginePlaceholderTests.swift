@testable import InputEngine
import Testing

@Suite("InputEnginePlaceholder")
struct InputEnginePlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(InputEnginePlaceholder().isReady)
    }
}
