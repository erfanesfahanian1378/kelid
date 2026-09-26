import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

/// Task 9.4's required tests: blending per mode on fixtures — personal-only
/// returns only user words, language-only ignores the user model, λ
/// extremes (hybrid) blend both. Split into its own file, matching the
/// established pattern of splitting large test suites by topic.
///
/// The personal word here is "yo", always typed in full (not just its
/// first letter "y") — a real 1-character typed prefix is legitimately
/// within fuzzy search's own `maxCost` of a single generic substitution
/// (§6.7.3: `maxCost = 1.0` for `|typed| ≤ 3`), so with a vocabulary this
/// tiny, "y" alone would also fuzzy-match "hello" (as if "y" were a typo
/// for "h") — real behavior, not a bug, just an artifact of a
/// one-word-vocabulary fixture that a real ~100k-word model wouldn't hit
/// this way. Typing "yo" in full avoids that coincidence entirely.
@Suite("SuggestionService personalization (task 9.4, §6.7.5/§6.7.7)")
struct SuggestionServicePersonalizationTests {
    /// Builds a service with a real language model plus a real `UserModel`
    /// (backed by the same `MockUserModelStore` `UserModelTests.swift`
    /// defines — internal, so directly reusable across files in this
    /// target) seeded with `personalWords`.
    static func makeService(
        unigrams: [UnigramEntry],
        personalWords: [UserModelWordRecord],
        language: LanguageID = .en
    ) async throws -> SuggestionService {
        let service = try await SuggestionServiceTests.makeService(unigrams: unigrams, language: language)
        let store = MockUserModelStore()
        for word in personalWords {
            store.seedWord(word)
            // `UserModel.load()` reads blocked status from the store's own
            // `loadBlockedWords()`, not `UserModelWordRecord.isBlocked`
            // (which only exists to mirror the real DB schema on the write
            // side) — the mock needs both kept in sync by hand.
            if word.isBlocked {
                try await store.setBlocked(true, surface: word.surface)
            }
        }
        try await service.loadUserModels([language: store])
        return service
    }

    static func settings(source: PredictionSourceMode, personalWeight: Double = 0.6) -> PredictionEngineSettings {
        var settings = PredictionEngineSettings()
        settings.source = source
        settings.personalWeight = personalWeight
        return settings
    }

    @Test(".off mode returns nil regardless of what the language model or user model would otherwise suggest")
    func offModeReturnsNil() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed)]
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "h", language: .en),
            settings: Self.settings(source: .off),
            incognito: false
        ))
        #expect(result == nil)
    }

    @Test(".languageOnly mode ignores the user model entirely, even for a word the user has typed a lot")
    func languageOnlyIgnoresUserModel() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 50, lastUsedAt: Date(), source: .typed)]
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .languageOnly),
            incognito: false
        ))
        // "yo" only exists personally -> languageOnly must not surface it.
        let items = result?.items ?? []
        #expect(items.isEmpty)
    }

    @Test(".personalOnly mode returns only user words, never a language-model-only word")
    func personalOnlyReturnsOnlyUserWords() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed)]
        )
        let helloResult = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "h", language: .en),
            settings: Self.settings(source: .personalOnly),
            incognito: false
        ))
        #expect(!(helloResult?.items ?? []).contains { $0.text == "hello" }) // language-only word, must not appear

        let yoResult = await service.suggest(SuggestionRequest(
            generation: 2,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .personalOnly),
            incognito: false
        ))
        #expect((yoResult?.items ?? []).contains { $0.text == "yo" }) // personal word, must appear
    }

    @Test(".hybrid mode surfaces both a language-model word and a personal-only new word")
    func hybridSurfacesBothSources() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed)]
        )
        let helloResult = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "h", language: .en),
            settings: Self.settings(source: .hybrid),
            incognito: false
        ))
        #expect((helloResult?.items ?? []).contains { $0.text == "hello" })

        let yoResult = await service.suggest(SuggestionRequest(
            generation: 2,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .hybrid),
            incognito: false
        ))
        #expect((yoResult?.items ?? []).contains { $0.text == "yo" })
    }

    @Test("in hybrid mode, a word the user personally uses a lot outranks a language-model word it would otherwise lose to")
    func hybridPersonalUsageCanOutrankLanguageFrequency() async throws {
        // "rare" is far less frequent than "common" in the language model,
        // but the user has typed "rare" constantly -> hybrid blending
        // should let personal usage overcome the raw frequency gap.
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "rare", count: 1), UnigramEntry(surface: "regular", count: 100_000)],
            personalWords: [UserModelWordRecord(surface: "rare", matchKey: "rare", count: 500, lastUsedAt: Date(), source: .typed)]
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "r", language: .en),
            settings: Self.settings(source: .hybrid, personalWeight: 0.9),
            incognito: false
        ))
        let texts = try #require(result?.items.map(\.text))
        #expect(texts.first == "rare")
    }

    @Test("blocked personal words never appear, even in personalOnly mode")
    func blockedPersonalWordsNeverAppear() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(
                surface: "yo",
                matchKey: "yo",
                count: 5,
                lastUsedAt: Date(),
                source: .typed,
                isBlocked: true
            )]
        )
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .personalOnly),
            incognito: false
        ))
        #expect(!(result?.items ?? []).contains { $0.text == "yo" })
    }

    // MARK: - Task 9.5's long-press menu passthroughs

    @Test("SuggestionService.block hides a previously-suggestable personal word in personalOnly mode")
    func serviceBlockHidesPersonalWord() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed)]
        )
        try await service.block(surface: "yo", language: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .personalOnly),
            incognito: false
        ))
        #expect(!(result?.items ?? []).contains { $0.text == "yo" })
    }

    @Test("SuggestionService.unblock un-hides a word blocked via .block")
    func serviceUnblockRestoresPersonalWord() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed)]
        )
        try await service.block(surface: "yo", language: .en)
        try await service.unblock(surface: "yo", language: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .personalOnly),
            incognito: false
        ))
        #expect((result?.items ?? []).contains { $0.text == "yo" })
    }

    @Test("SuggestionService.forget removes a personal word from the candidate set entirely")
    func serviceForgetRemovesPersonalWord() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed)]
        )
        try await service.forget(surface: "yo", language: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "yo", language: .en),
            settings: Self.settings(source: .personalOnly),
            incognito: false
        ))
        #expect(!(result?.items ?? []).contains { $0.text == "yo" })
        #expect(await service.personalWordCount(for: .en) == 0)
    }

    @Test("SuggestionService.personalWordCount reflects the loaded UserModel's word count")
    func servicePersonalWordCountReflectsUserModel() async throws {
        let service = try await Self.makeService(
            unigrams: [UnigramEntry(surface: "hello", count: 100)],
            personalWords: [
                UserModelWordRecord(surface: "yo", matchKey: "yo", count: 5, lastUsedAt: Date(), source: .typed),
                UserModelWordRecord(surface: "bruh", matchKey: "bruh", count: 3, lastUsedAt: Date(), source: .typed),
            ]
        )
        #expect(await service.personalWordCount(for: .en) == 2)
        #expect(await service.personalWordCount(for: .fa) == 0) // no UserModel loaded for fa
    }
}
