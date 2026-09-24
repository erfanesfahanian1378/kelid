@testable import KelidStorage
import Testing

@Suite("KelidStoragePlaceholder")
struct KelidStoragePlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(KelidStoragePlaceholder().isReady)
    }
}
