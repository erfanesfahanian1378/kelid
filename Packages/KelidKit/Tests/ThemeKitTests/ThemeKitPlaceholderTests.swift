import Foundation
import Testing
@testable import ThemeKit

@Suite("ThemeKitPlaceholder")
struct ThemeKitPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(ThemeKitPlaceholder().isReady)
    }

    @Test("bundled BuiltInThemes resource folder is reachable")
    func builtInThemesResourceExists() {
        #expect(Bundle.module.url(forResource: "BuiltInThemes", withExtension: nil) != nil)
    }
}
