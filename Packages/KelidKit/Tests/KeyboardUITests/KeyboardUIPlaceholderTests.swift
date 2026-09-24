@testable import KeyboardUI
import Testing

@Suite("KeyboardUIPlaceholder")
@MainActor
struct KeyboardUIPlaceholderTests {
    /// KeyboardUI declares `.defaultIsolation(MainActor.self)` (Package.swift),
    /// so every type in it — including this placeholder — is @MainActor by
    /// default. The test suite must match.
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(KeyboardUIPlaceholder().isReady)
    }
}
