import Foundation
import KelidCore
@testable import PredictionEngine
import Testing

/// Task 8.6's decision table (§6.7.9): known word → no change; URL-like →
/// no change; margin rule; a real typo corrects.
@Suite("AutocorrectEngine (§6.7.9)")
struct AutocorrectEngineTests {
    static func makeLexicon(_ unigrams: [UnigramEntry], language: LanguageID = .en) throws -> Lexicon {
        let data = try KLMWriter.build(language: language, unigrams: unigrams, maxWords: 200_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-autocorrect-\(UUID().uuidString).klm")
        try data.write(to: url)
        return try Lexicon(file: KLMFile(path: url.path))
    }

    @Test("a clear typo with no close competitor corrects to the known word")
    func clearTypoCorrects() throws {
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "the", count: 100_000),
            UnigramEntry(surface: "hello", count: 100),
        ])
        let corrected = AutocorrectEngine.decide(typed: "teh", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == "the")
    }

    @Test("a known word (score >= q_min) is never autocorrected away")
    func knownWordIsUnchanged() throws {
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "teh", count: 100_000), // a made-up but "known" (high-score) word
            UnigramEntry(surface: "the", count: 1),
        ])
        let corrected = AutocorrectEngine.decide(typed: "teh", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("a word under the q_min threshold but with no real correction candidate is unchanged")
    func noCandidateMeansNoChange() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "xyzzy", count: 1)])
        let corrected = AutocorrectEngine.decide(typed: "plugh", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("an email-like typed word is never autocorrected")
    func emailLikeIsUnchanged() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "example", count: 100_000)])
        let corrected = AutocorrectEngine.decide(typed: "user@example.com", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("a bare-domain-like typed word is never autocorrected")
    func domainLikeIsUnchanged() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "example", count: 100_000)])
        let corrected = AutocorrectEngine.decide(typed: "example.com", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("an all-caps typed word is never autocorrected (English shouting is not a typo)")
    func allCapsIsUnchanged() throws {
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "the", count: 100_000),
        ])
        let corrected = AutocorrectEngine.decide(typed: "TEH", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("a typed word containing a digit is never autocorrected")
    func digitsAreUnchanged() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "hello", count: 100_000)])
        let corrected = AutocorrectEngine.decide(typed: "hell0", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("a single-character typed word is never autocorrected (rule 2: >= 2 graphemes)")
    func singleCharacterIsUnchanged() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "a", count: 100_000)])
        let corrected = AutocorrectEngine.decide(typed: "x", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("margin rule: two near-equally likely corrections with no clear winner leave the word unchanged")
    func ambiguousCorrectionIsUnchanged() throws {
        // "cat" and "car" are both one substitution away from "cak" (a
        // typo), with the same frequency -> no candidate clears the margin.
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "cat", count: 1000),
            UnigramEntry(surface: "car", count: 1000),
        ])
        let corrected = AutocorrectEngine.decide(typed: "cak", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == nil)
    }

    @Test("a higher autocorrectStrength lowers the margin bar, allowing a closer call to still correct")
    func higherStrengthLowersMarginBar() throws {
        // "cat" (4x more frequent than "car") gives a ~0.6 log10 score gap
        // (both are a single, same-cost substitution away from "cak"): below
        // τ(strength=0)=1.0, above τ(strength=1)=0.2.
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "cat", count: 4000),
            UnigramEntry(surface: "car", count: 1000),
        ])
        let atLowStrength = AutocorrectEngine.decide(typed: "cak", lexicon: lexicon, proximity: .empty, strength: 0.0)
        let atHighStrength = AutocorrectEngine.decide(typed: "cak", lexicon: lexicon, proximity: .empty, strength: 1.0)
        #expect(atLowStrength == nil)
        #expect(atHighStrength == "cat")
    }

    @Test("Persian confusion-group homophone corrects (شما typo of what would be a more common word)")
    func persianConfusionGroupCorrects() throws {
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "سلام", count: 100_000),
            UnigramEntry(surface: "کتاب", count: 100),
        ], language: .fa)
        let corrected = AutocorrectEngine.decide(typed: "صلام", lexicon: lexicon, proximity: .empty, strength: 0.5)
        #expect(corrected == "سلام")
    }
}
