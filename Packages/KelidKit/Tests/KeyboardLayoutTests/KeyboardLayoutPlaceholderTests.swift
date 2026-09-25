import Foundation
@testable import KeyboardLayout
import Testing

@Suite("KeyboardLayoutPlaceholder")
struct KeyboardLayoutPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(KeyboardLayoutPlaceholder().isReady)
    }

    @Test("bundled layout JSON files are reachable")
    func layoutsResourceExists() {
        // Proves the `resources: [.process("Layouts")]` declaration in
        // Package.swift actually produces a resource bundle the module can
        // find at runtime. Checks a specific file rather than the
        // "Layouts" directory itself: SPM's `.process()` does not
        // necessarily preserve that directory name in the resource bundle
        // (confirmed once Phase 2 added real JSON content — see
        // LayoutRepository, which looks files up by bundle root, not
        // "Layouts/<id>.json").
        #expect(Bundle.module.url(forResource: "en.qwerty", withExtension: "json") != nil)
    }
}
