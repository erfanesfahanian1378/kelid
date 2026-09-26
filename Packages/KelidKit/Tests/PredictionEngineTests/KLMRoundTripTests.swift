import Foundation
import KelidCore
@testable import PersianText
@testable import PredictionEngine
import Testing

/// Task 7.2/7.3's required test: "Writer → reader round trip on a 60-word
/// fixture (ZWNJ variants, آ/ا variants, English)."
@Suite("KLM writer/reader round trip")
struct KLMRoundTripTests {
    /// 60 words: Persian ZWNJ-variant pairs, آ/ا-variant pairs, and English —
    /// counts chosen so frequency order (and therefore word id order) is
    /// unambiguous.
    static func fixtureUnigrams() -> [UnigramEntry] {
        var entries: [UnigramEntry] = []
        let persianBase = [
            "من", "تو", "او", "ما", "شما", "کتاب", "خانه", "مدرسه", "دوست", "خوب",
            "بد", "بزرگ", "کوچک", "آب", "آتش", "نان", "شب", "روز", "سال", "ماه",
        ]
        for (i, word) in persianBase.enumerated() {
            entries.append(UnigramEntry(surface: word, count: UInt64(10000 - i * 50)))
        }
        // ZWNJ-variant pairs sharing a match key ("میخواهم" and "می‌خواهم").
        entries.append(UnigramEntry(surface: "می\u{200C}خواهم", count: 5000))
        entries.append(UnigramEntry(surface: "میخواهم", count: 3000))
        entries.append(UnigramEntry(surface: "می\u{200C}خوام", count: 4000))
        entries.append(UnigramEntry(surface: "میخوام", count: 1500))
        entries.append(UnigramEntry(surface: "کتاب\u{200C}ها", count: 800))
        entries.append(UnigramEntry(surface: "کتابها", count: 400))
        // آ/ا-variant pair sharing a match key ("اب").
        entries.append(UnigramEntry(surface: "آب", count: 6000))
        entries.append(UnigramEntry(surface: "اب", count: 10))
        // English words.
        let english = [
            "hello", "world", "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
            "cat", "sun", "moon", "star", "tree", "house", "car", "book", "phone", "table",
            "chair", "water", "fire", "earth", "wind", "love", "hate", "good", "bad", "happy",
        ]
        for (i, word) in english.enumerated() {
            entries.append(UnigramEntry(surface: word, count: UInt64(2000 - i * 10)))
        }
        return entries
    }

    static func writeFixtureFile() throws -> URL {
        let data = try KLMWriter.build(language: .fa, unigrams: fixtureUnigrams(), maxWords: 200_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-klm-roundtrip-\(UUID().uuidString).klm")
        try data.write(to: url)
        return url
    }

    @Test("round trip preserves every word's surface, and the most frequent word is id 0")
    func roundTripPreservesSurfaces() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try KLMFile(path: url.path)

        #expect(file.wordCount == Self.fixtureUnigrams().count)
        #expect(file.language == .fa)
        #expect(file.surface(0) == "من") // highest count (10,000)

        let allSurfaces = Set((0 ..< UInt32(file.wordCount)).map(file.surface))
        let expectedSurfaces = Set(Self.fixtureUnigrams().map(\.surface))
        #expect(allSurfaces == expectedSurfaces)
    }

    @Test("word scores are monotonically non-increasing by id (ids are sorted by descending frequency)")
    func scoresAreSortedByFrequency() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try KLMFile(path: url.path)

        var previous: UInt8 = 255
        for id in 0 ..< UInt32(file.wordCount) {
            let score = file.score(id)
            #expect(score <= previous)
            previous = score
        }
    }

    @Test("containsZWNJ flag is set exactly for surfaces with an internal ZWNJ")
    func zwnjFlagIsCorrect() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try KLMFile(path: url.path)

        for id in 0 ..< UInt32(file.wordCount) {
            let hasZWNJ = PersianNormalization.containsZWNJ(file.surface(id))
            #expect(file.containsZWNJ(id) == hasZWNJ)
        }
    }

    @Test("wordID(forSurface:) resolves ZWNJ and non-ZWNJ variants to their own exact surface")
    func wordIDResolvesExactSurface() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = try Lexicon(file: KLMFile(path: url.path))

        let zwnjID = try #require(lexicon.wordID(forSurface: "می\u{200C}خواهم"))
        #expect(lexicon.surface(zwnjID) == "می\u{200C}خواهم")

        let joinedID = try #require(lexicon.wordID(forSurface: "میخواهم"))
        #expect(lexicon.surface(joinedID) == "میخواهم")
        #expect(zwnjID != joinedID)
    }

    @Test("wordID(forSurface:) resolves آ/ا variants sharing one match key")
    func wordIDResolvesHamzaVariant() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = try Lexicon(file: KLMFile(path: url.path))

        let aabID = try #require(lexicon.wordID(forSurface: "آب"))
        #expect(lexicon.surface(aabID) == "آب")
        let abID = try #require(lexicon.wordID(forSurface: "اب"))
        #expect(lexicon.surface(abID) == "اب")
    }

    @Test("completions for a Persian prefix return the ZWNJ and joined forms, best-first")
    func completionsReturnBestFirst() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = try Lexicon(file: KLMFile(path: url.path))

        // matchKey("می") == "می" — a prefix of both میخواهم-family words.
        let results = lexicon.completions(prefixKey: "می", limit: 20)
        let surfaces = results.map(\.surface)
        #expect(surfaces.contains("می\u{200C}خواهم"))
        #expect(surfaces.contains("میخواهم"))
        #expect(surfaces.contains("می\u{200C}خوام"))
        #expect(surfaces.contains("میخوام"))
        // Best-first: scores must be non-increasing across the result list.
        for i in 1 ..< results.count {
            #expect(results[i - 1].score >= results[i].score)
        }
        // The highest-count match ("می‌خواهم", 5000) should rank first.
        #expect(surfaces.first == "می\u{200C}خواهم")
    }

    @Test("completions for an English prefix work identically")
    func completionsWorkForEnglish() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = try Lexicon(file: KLMFile(path: url.path))

        let results = lexicon.completions(prefixKey: "he", limit: 20)
        #expect(results.map(\.surface).contains("hello"))
    }

    @Test("completions respects the limit")
    func completionsRespectsLimit() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = try Lexicon(file: KLMFile(path: url.path))

        let results = lexicon.completions(prefixKey: "", limit: 5)
        #expect(results.count <= 5)
    }

    @Test("completions for a nonexistent prefix returns empty")
    func completionsForUnknownPrefixIsEmpty() throws {
        let url = try Self.writeFixtureFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let lexicon = try Lexicon(file: KLMFile(path: url.path))

        #expect(lexicon.completions(prefixKey: "zzzzz", limit: 20).isEmpty)
    }

    @Test("opening a corrupt file (bad magic) throws")
    func rejectsInvalidMagic() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-klm-bad-\(UUID().uuidString).klm")
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[0] = 0x00 // wrong magic
        try Data(bytes).write(to: url)
        #expect(throws: KLMFile.OpenError.self) {
            _ = try KLMFile(path: url.path)
        }
    }
}
