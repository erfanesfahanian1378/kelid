import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

@Suite("SuggestionService")
struct SuggestionServiceTests {
    static func makeService(unigrams: [UnigramEntry], language: LanguageID = .fa) async throws -> SuggestionService {
        let data = try KLMWriter.build(language: language, unigrams: unigrams, maxWords: 200_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-suggestion-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let modelURL = dir.appendingPathComponent("\(language.rawValue).klm")
        try data.write(to: modelURL)

        struct DirectoryLocator: ModelLocator {
            let dir: URL
            func url(for language: LanguageID) -> URL? {
                dir.appendingPathComponent("\(language.rawValue).klm")
            }
        }
        let service = SuggestionService()
        try await service.load(languages: [language], resources: DirectoryLocator(dir: dir))
        return service
    }

    static func context(prefix: String, language: LanguageID = .fa, isSentenceStart: Bool = false) -> SuggestionContext {
        SuggestionContext(prefix: prefix, suffix: "", previousWords: ["<s>"], isSentenceStart: isSentenceStart, language: language)
    }

    @Test("suggest returns completions for a known prefix")
    func suggestReturnsCompletions() async throws {
        let service = try await Self.makeService(unigrams: [
            UnigramEntry(surface: "کتاب", count: 100),
            UnigramEntry(surface: "کتابخانه", count: 50),
        ])
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتا"),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = try #require(result?.items.map(\.text))
        #expect(texts.contains("کتاب"))
        #expect(texts.contains("کتابخانه"))
    }

    @Test("suggest returns nil when the request is superseded by an already-processed newer generation")
    func staleGenerationsAreDropped() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        let newer = await service.suggest(SuggestionRequest(
            generation: 5,
            context: Self.context(prefix: "کتا"),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(newer != nil)
        let stale = await service.suggest(SuggestionRequest(
            generation: 3,
            context: Self.context(prefix: "کتا"),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(stale == nil)
    }

    @Test("suggest returns nil in incognito mode")
    func incognitoReturnsNil() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتا"),
            settings: PredictionEngineSettings(),
            incognito: true
        ))
        #expect(result == nil)
    }

    @Test("suggest returns nil when prediction is disabled")
    func disabledReturnsNil() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        var settings = PredictionEngineSettings()
        settings.enabled = false
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتا"),
            settings: settings,
            incognito: false
        ))
        #expect(result == nil)
    }

    @Test("suggest returns nil when the cursor is mid-word (non-empty suffix)")
    func midWordCursorReturnsNil() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        var context = Self.context(prefix: "کتا")
        context.suffix = "ب"
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: context,
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result == nil)
    }

    @Test("suggest returns nil for an empty prefix (next-word prediction is out of scope for Phase 7)")
    func emptyPrefixReturnsNil() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: ""),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result == nil)
    }

    @Test("suggest respects suggestionCount")
    func suggestRespectsSuggestionCount() async throws {
        let service = try await Self.makeService(unigrams: (0 ..< 10).map { UnigramEntry(surface: "کتاب\($0)", count: UInt64(100 - $0)) })
        var settings = PredictionEngineSettings()
        settings.suggestionCount = 2
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتاب"),
            settings: settings,
            incognito: false
        ))
        #expect(result?.items.count == 2)
    }

    @Test("suggest applies English casing end-to-end")
    func suggestAppliesEnglishCasing() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "hello", count: 100)], language: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "Hel", language: .en),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result?.items.first?.text == "Hello")
    }

    @Test("suggest includes a verbatim candidate when showVerbatimSlot is on")
    func suggestIncludesVerbatim() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتا"),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result?.verbatim?.text == "کتا")
    }

    @Test("suggest omits the verbatim candidate when showVerbatimSlot is off")
    func suggestOmitsVerbatimWhenDisabled() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        var settings = PredictionEngineSettings()
        settings.showVerbatimSlot = false
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتا"),
            settings: settings,
            incognito: false
        ))
        #expect(result?.verbatim == nil)
    }
}
