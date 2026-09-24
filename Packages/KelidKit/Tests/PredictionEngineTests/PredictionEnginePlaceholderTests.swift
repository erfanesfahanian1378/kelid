@testable import PredictionEngine
import Testing

@Suite("PredictionEnginePlaceholder")
struct PredictionEnginePlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(PredictionEnginePlaceholder().isReady)
    }
}
