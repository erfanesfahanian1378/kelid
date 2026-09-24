@testable import KelidSettings
import Testing

@Suite("KelidSettingsPlaceholder")
struct KelidSettingsPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(KelidSettingsPlaceholder().isReady)
    }
}
