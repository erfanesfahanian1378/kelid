@testable import EmojiData
import Foundation
import Testing

/// Mirrors §6.9's `emoji.json` schema just enough to sanity-check the file
/// the Phase 6 data pipeline (`Tools/data-pipeline/pipeline/emoji.py`)
/// produces. The real `Decodable` model, search index, recents and skin
/// tones are Phase 12's job (§0.3 row 12) — this is a data-format
/// smoke test, not that API.
private struct EmojiEntry: Decodable {
    let e: String
    let g: Int
    let v: Double
    let st: Bool
    let fa: [String]
    let en: [String]
}

@Suite("EmojiDataPlaceholder")
struct EmojiDataPlaceholderTests {
    @Test("placeholder reports ready")
    func placeholderIsReady() {
        #expect(EmojiDataPlaceholder().isReady)
    }

    @Test("bundled emoji.json decodes to §6.9's schema, is non-empty, and stays under the 600 KB target")
    func emojiJSONLoads() throws {
        let url = try #require(Bundle.module.url(forResource: "emoji", withExtension: "json"))
        let data = try Data(contentsOf: url)
        #expect(data.count <= 600 * 1024)
        let decoded = try JSONDecoder().decode([EmojiEntry].self, from: data)
        #expect(!decoded.isEmpty)
        #expect(decoded.allSatisfy { !$0.e.isEmpty && $0.g >= 0 && $0.v >= 0 })
        // At least one keyword in at least one language for every entry —
        // §6.9's search relies on this; a silently-unsearchable emoji would
        // be a real (if minor) regression from the data pipeline.
        #expect(decoded.allSatisfy { !$0.fa.isEmpty || !$0.en.isEmpty })
    }
}
