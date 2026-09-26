import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

@Suite("SuggestionService")
struct SuggestionServiceTests {
    static func makeService(
        unigrams: [UnigramEntry],
        bigrams: [BigramEntry] = [],
        trigrams: [TrigramEntry] = [],
        options: KLMBuildOptions = KLMBuildOptions(),
        language: LanguageID = .fa
    ) async throws -> SuggestionService {
        let data = try KLMWriter.build(
            language: language,
            unigrams: unigrams,
            maxWords: 200_000,
            bigrams: bigrams,
            trigrams: trigrams,
            options: options
        )
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

    static func context(
        prefix: String,
        language: LanguageID = .fa,
        isSentenceStart: Bool = false,
        previousWords: [String] = ["<s>"]
    ) -> SuggestionContext {
        SuggestionContext(prefix: prefix, suffix: "", previousWords: previousWords, isSentenceStart: isSentenceStart, language: language)
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

    @Test("suggest returns nil for an empty prefix when the model has no n-gram data at all")
    func emptyPrefixReturnsNilWithoutNGrams() async throws {
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "کتاب", count: 100)])
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: ""),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result == nil)
    }

    @Test("suggest predicts next words for an empty prefix after a sentence start (task 8.2)")
    func suggestPredictsNextWordsAtSentenceStart() async throws {
        var options = KLMBuildOptions()
        options.bigramMinCount = 1
        let service = try await Self.makeService(
            unigrams: [
                UnigramEntry(surface: "<s>", count: 1000),
                UnigramEntry(surface: "من", count: 300),
                UnigramEntry(surface: "او", count: 100),
            ],
            bigrams: [BigramEntry(w1: "<s>", w2: "من", count: 30), BigramEntry(w1: "<s>", w2: "او", count: 10)],
            options: options
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "", previousWords: ["<s>"]),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = try #require(result?.items.map(\.text))
        #expect(texts.first == "من") // higher bigram count -> ranked first
        #expect(result?.verbatim == nil) // nothing typed yet to echo back
    }

    @Test("suggest returns nil for an empty prefix when nextWord is disabled (task 8.11)")
    func suggestReturnsNilForEmptyPrefixWhenNextWordDisabled() async throws {
        var options = KLMBuildOptions()
        options.bigramMinCount = 1
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "<s>", count: 1000), UnigramEntry(surface: "من", count: 300)],
            bigrams: [BigramEntry(w1: "<s>", w2: "من", count: 30)],
            options: options
        )
        var settings = PredictionEngineSettings()
        settings.nextWordEnabled = false
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "", previousWords: ["<s>"]),
            settings: settings,
            incognito: false
        ))
        #expect(result == nil)
    }

    @Test("suggest predicts next words using two-word trigram context when available (task 8.2)")
    func suggestPredictsNextWordsUsingTrigramContext() async throws {
        var options = KLMBuildOptions()
        options.bigramMinCount = 1
        options.trigramMinCount = 1
        options.trigramContextMinBigramCount = 1
        let service = try await Self.makeService(
            unigrams: [
                UnigramEntry(surface: "من", count: 300),
                UnigramEntry(surface: "می\u{200C}خواهم", count: 200),
                UnigramEntry(surface: "بروم", count: 50),
                UnigramEntry(surface: "بخوانم", count: 50),
            ],
            bigrams: [BigramEntry(w1: "من", w2: "می\u{200C}خواهم", count: 50)],
            trigrams: [
                TrigramEntry(w1: "من", w2: "می\u{200C}خواهم", w3: "بروم", count: 30),
                TrigramEntry(w1: "من", w2: "می\u{200C}خواهم", w3: "بخوانم", count: 5),
            ],
            options: options
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "", previousWords: ["من", "می\u{200C}خواهم"]),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result?.items.map(\.text).first == "بروم")
    }

    @Test("suggest merges context-aware next-word candidates into a non-empty prefix's results (task 8.3)")
    func suggestMergesContextAwareCandidatesWithCompletions() async throws {
        var options = KLMBuildOptions()
        options.bigramMinCount = 1
        // "کتابخانه" is a rare word overall, but very likely right after
        // "به" in this fixture — it should still surface from its first
        // letter thanks to the context-aware candidate set, not just its
        // (low) raw unigram frequency.
        let service = try await Self.makeService(
            unigrams: [
                UnigramEntry(surface: "به", count: 500),
                UnigramEntry(surface: "کتابخانه", count: 5),
                UnigramEntry(surface: "کتاب", count: 400),
            ],
            bigrams: [BigramEntry(w1: "به", w2: "کتابخانه", count: 100)],
            options: options
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "کتا", previousWords: ["به"]),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = try #require(result?.items.map(\.text))
        #expect(texts.contains("کتابخانه"))
        #expect(texts.contains("کتاب"))
    }

    @Test("suggest surfaces a fuzzy (typo-tolerant) match for a misspelled prefix (task 8.4, wired into the service)")
    func suggestSurfacesFuzzyMatchForTypo() async throws {
        let service = try await Self.makeService(unigrams: [
            UnigramEntry(surface: "سلام", count: 100),
            UnigramEntry(surface: "سیب", count: 50),
        ])
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "صلام"), // typo: ص instead of س (§6.6.6 confusion group)
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = try #require(result?.items.map(\.text))
        #expect(texts.contains("سلام"))
    }

    @Test("suggest's blockOffensive filter also removes an offensive word reached only via fuzzy search")
    func suggestBlocksOffensiveFuzzyMatch() async throws {
        var options = KLMBuildOptions()
        options.offensiveWords = ["سلام"]
        let service = try await Self.makeService(unigrams: [UnigramEntry(surface: "سلام", count: 100)], options: options)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: Self.context(prefix: "صلام"),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = result?.items.map(\.text) ?? []
        #expect(!texts.contains("سلام"))
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
