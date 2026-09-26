import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

/// Task 9.6: "Text replacements appear as the best suggestion when the
/// typed word equals the shortcut." Split into its own file, matching the
/// established pattern of splitting large test suites by topic.
@Suite("SuggestionService text replacements (task 9.6, §6.11's C16)")
struct SuggestionServiceTextReplacementTests {
    @Test("a typed word matching a shortcut surfaces its expansion as the top suggestion")
    func matchingShortcutIsTopSuggestion() async throws {
        let service = try await SuggestionServiceTests.makeService(
            unigrams: [UnigramEntry(surface: "omgosh", count: 1_000_000)], language: .en
        )
        await service.updateTextReplacements(["omw": "on my way!"], for: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "omw", language: .en),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        #expect(result?.items.first?.text == "on my way!")
    }

    @Test("a typed prefix that only partially matches a shortcut does not trigger it")
    func partialMatchDoesNotTrigger() async throws {
        let service = try await SuggestionServiceTests.makeService(
            unigrams: [UnigramEntry(surface: "omega", count: 100)], language: .en
        )
        await service.updateTextReplacements(["omw": "on my way!"], for: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "om", language: .en),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = result?.items.map(\.text) ?? []
        #expect(!texts.contains("on my way!"))
    }

    @Test("updateTextReplacements replaces the whole table, so a removed shortcut stops triggering")
    func updateReplacesWholeTable() async throws {
        let service = try await SuggestionServiceTests.makeService(
            unigrams: [UnigramEntry(surface: "other", count: 100)], language: .en
        )
        await service.updateTextReplacements(["omw": "on my way!"], for: .en)
        await service.updateTextReplacements(["brb": "be right back"], for: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "omw", language: .en),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = result?.items.map(\.text) ?? []
        #expect(!texts.contains("on my way!"))
    }

    @Test("text replacements are scoped per language")
    func replacementsAreScopedPerLanguage() async throws {
        let service = try await SuggestionServiceTests.makeService(unigrams: [UnigramEntry(surface: "سلام", count: 100)])
        await service.updateTextReplacements(["omw": "on my way!"], for: .en)
        let result = await service.suggest(SuggestionRequest(
            generation: 1,
            context: SuggestionServiceTests.context(prefix: "omw", language: .fa),
            settings: PredictionEngineSettings(),
            incognito: false
        ))
        let texts = result?.items.map(\.text) ?? []
        #expect(!texts.contains("on my way!"))
    }
}
