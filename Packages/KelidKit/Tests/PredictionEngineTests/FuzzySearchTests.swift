import Foundation
import KelidCore
@testable import PersianText
@testable import PredictionEngine
import Testing

/// Task 8.4's required tests: "adjacent-key substitution (سلان → سلام),
/// homophones (صلام → سلام, طهران/تهران), transposition (teh → the),
/// insertion/deletion, budget cut-off."
@Suite("Lexicon.fuzzyMatches (task 8.4, §6.7.3/§6.6.6)")
struct FuzzySearchTests {
    static func makeLexicon(_ unigrams: [UnigramEntry], language: LanguageID = .fa) throws -> Lexicon {
        let data = try KLMWriter.build(language: language, unigrams: unigrams, maxWords: 200_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelid-fuzzy-\(UUID().uuidString).klm")
        try data.write(to: url)
        return try Lexicon(file: KLMFile(path: url.path))
    }

    @Test("adjacent-key substitution: سلان (typo for سلام, ن next to م) fuzzy-matches سلام")
    func adjacentKeySubstitution() throws {
        let lexicon = try Self.makeLexicon([
            UnigramEntry(surface: "سلام", count: 100),
            UnigramEntry(surface: "کتاب", count: 100),
        ])
        // A synthetic keyboard-adjacency map (ن next to م), standing in for
        // the real `KeyboardLayout.ProximityMap` `KeyboardUI` would build
        // from the actual fa.standard layout.
        let proximity = FuzzyProximityMap(adjacency: ["ن": ["م"], "م": ["ن"]])
        let matches = lexicon.fuzzyMatches(typedKey: "سلان", proximity: proximity)
        #expect(matches.contains { $0.surface == "سلام" })
        // Cost should be the 0.6 adjacency substitution, not the generic 1.0.
        let salaam = try #require(matches.first { $0.surface == "سلام" })
        #expect(abs(salaam.editCost - 0.6) < 0.01)
    }

    @Test("without a proximity map, the same substitution costs the generic 1.0 and may still pass under maxCost=1.0")
    func substitutionWithoutProximityCostsGeneric() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "سلام", count: 100)])
        let matches = lexicon.fuzzyMatches(typedKey: "سلان") // no proximity map
        let salaam = try #require(matches.first { $0.surface == "سلام" })
        #expect(abs(salaam.editCost - 1.0) < 0.01) // generic substitution cost, well within maxCost=2.0 for a 4-char typed key
    }

    @Test("homophone (confusion group): صلام fuzzy-matches سلام at the س/ص/ث group cost")
    func homophoneConfusionGroupSAD() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "سلام", count: 100)])
        let matches = lexicon.fuzzyMatches(typedKey: "صلام")
        let salaam = try #require(matches.first { $0.surface == "سلام" })
        #expect(abs(salaam.editCost - 0.4) < 0.01) // §6.6.6's س↔ص cost
    }

    @Test("homophone (confusion group): طهران fuzzy-matches تهران at the ت/ط group cost")
    func homophoneConfusionGroupTehran() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "تهران", count: 100)])
        let matches = lexicon.fuzzyMatches(typedKey: "طهران")
        let tehran = try #require(matches.first { $0.surface == "تهران" })
        #expect(abs(tehran.editCost - 0.4) < 0.01) // §6.6.6's ت↔ط cost
    }

    @Test("transposition: teh fuzzy-matches the at the 0.8 transposition cost")
    func transpositionTehMatchesThe() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "the", count: 100)], language: .en)
        let matches = lexicon.fuzzyMatches(typedKey: "teh")
        let the = try #require(matches.first { $0.surface == "the" })
        #expect(abs(the.editCost - 0.8) < 0.01)
    }

    @Test("deletion: helo (missing a letter) fuzzy-matches hello")
    func deletionMatchesLongerWord() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "hello", count: 100)], language: .en)
        let matches = lexicon.fuzzyMatches(typedKey: "helo")
        #expect(matches.contains { $0.surface == "hello" })
    }

    @Test("insertion of a doubled letter: helllo fuzzy-matches hello at the cheaper 0.5 doubled-letter cost")
    func doubledLetterInsertionIsCheaper() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "hello", count: 100)], language: .en)
        let matches = lexicon.fuzzyMatches(typedKey: "helllo") // extra "l"
        let hello = try #require(matches.first { $0.surface == "hello" })
        #expect(abs(hello.editCost - 0.5) < 0.01)
    }

    @Test("maxCost is 1.0 for typed keys of length <= 3 and 2.0 otherwise")
    func maxCostThresholds() {
        #expect(Lexicon.fuzzyMaxCost(forTypedLength: 1) == 1.0)
        #expect(Lexicon.fuzzyMaxCost(forTypedLength: 3) == 1.0)
        #expect(Lexicon.fuzzyMaxCost(forTypedLength: 4) == 2.0)
        #expect(Lexicon.fuzzyMaxCost(forTypedLength: 10) == 2.0)
    }

    @Test("a match whose edit cost exceeds maxCost for a short typed key is excluded")
    func excessiveCostIsExcludedForShortKeys() throws {
        let lexicon = try Self.makeLexicon([UnigramEntry(surface: "hello", count: 100)], language: .en)
        // "abc" (3 chars, maxCost=1.0) is nowhere near "hello" — must not match.
        let matches = lexicon.fuzzyMatches(typedKey: "abc")
        #expect(!matches.contains { $0.surface == "hello" })
    }

    @Test("budget cut-off: fuzzy search over a large vocabulary completes and returns a bounded result set")
    func budgetCutOffCompletesOnLargeVocabulary() throws {
        var generator = SplitMix64(seed: 99)
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var seen = Set<String>()
        var unigrams: [UnigramEntry] = [UnigramEntry(surface: "helloworld", count: 1_000_000)]
        while unigrams.count < 5000 {
            let length = Int.random(in: 4 ... 10, using: &generator)
            let surface = String((0 ..< length).map { _ in letters.randomElement(using: &generator)! })
            guard seen.insert(surface).inserted else { continue }
            unigrams.append(UnigramEntry(surface: surface, count: UInt64.random(in: 1 ... 1000, using: &generator)))
        }
        let lexicon = try Self.makeLexicon(unigrams, language: .en)
        // A long, nonsense typed key over a large, mostly-unrelated
        // vocabulary — mainly checks this returns promptly and sanely
        // rather than visiting the whole trie or hanging.
        let matches = lexicon.fuzzyMatches(typedKey: "helloworldxyz", limit: 20)
        #expect(matches.count <= 20)
    }
}
