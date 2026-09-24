@testable import EmojiData
import Foundation
import Testing

@Suite("EmojiDataPlaceholder")
struct EmojiDataPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(EmojiDataPlaceholder().isReady)
    }

    @Test("bundled emoji.json loads and is an empty array for now")
    func emojiJSONLoads() throws {
        let url = try #require(Bundle.module.url(forResource: "emoji", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String].self, from: data)
        #expect(decoded.isEmpty)
    }
}
