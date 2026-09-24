@testable import ClipboardKit
import Testing

@Suite("ClipboardKitPlaceholder")
struct ClipboardKitPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(ClipboardKitPlaceholder().isReady)
    }
}
