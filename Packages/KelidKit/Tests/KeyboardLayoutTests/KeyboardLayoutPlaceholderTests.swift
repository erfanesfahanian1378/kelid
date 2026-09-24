import Foundation
@testable import KeyboardLayout
import Testing

@Suite("KeyboardLayoutPlaceholder")
struct KeyboardLayoutPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(KeyboardLayoutPlaceholder().isReady)
    }

    @Test("bundled Layouts resource folder is reachable")
    func layoutsResourceExists() {
        // Proves the `resources: [.process("Layouts")]` declaration in
        // Package.swift actually produces a resource bundle the module can
        // find at runtime, ahead of Phase 2 adding real layout JSON there.
        #expect(Bundle.module.url(forResource: "Layouts", withExtension: nil) != nil)
    }
}
