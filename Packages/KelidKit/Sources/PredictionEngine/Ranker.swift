import Foundation
import PersianText

/// §6.7.5's scoring constants. All tuned properly in Phase 8 with the eval
/// harness (§6.7.12); Phase 7 ships the spec's own stated defaults.
public struct RankerConfig: Sendable, Equatable {
    /// `γ` in `channel(t|w) = 10^(-γ · editCost(t, k(w)))`.
    public var gamma: Double
    /// The `0.05` in `completion = 10^(-0.05 · min(|k(w)| - |t|, 6))`.
    public var completionLengthPenalty: Double
    /// The `6` length-difference cap in the same formula.
    public var completionLengthCap: Int
    /// The `0.15` bonus when `k(w) == t` exactly.
    public var exactMatchBonus: Double
    /// Task 8.5's blending hook: `λ` in `S(w|ctx) = λ·S_user + (1−λ)·S_lang`
    /// (§6.7.5). Held at `0` — meaning `S(w|ctx) = S_lang` exactly, what
    /// `score(...)` below already computes — until Phase 9's `UserModel`
    /// exists to supply `S_user`; the field exists now so Phase 9 only has
    /// to *use* it, not add it.
    public var personalWeight: Double

    public init(
        gamma: Double = 1.2,
        completionLengthPenalty: Double = 0.05,
        completionLengthCap: Int = 6,
        exactMatchBonus: Double = 0.15,
        personalWeight: Double = 0
    ) {
        self.gamma = gamma
        self.completionLengthPenalty = completionLengthPenalty
        self.completionLengthCap = completionLengthCap
        self.exactMatchBonus = exactMatchBonus
        self.personalWeight = personalWeight
    }
}

public struct RankedSuggestion: Sendable, Equatable {
    public let wordID: UInt32
    public let surface: String
    public let score: Double
}

/// §6.7.5's scoring formula, restricted to what Phase 7 actually has:
/// completion-only candidates from `Lexicon.completions` (always an exact
/// prefix match on `matchKey`, since fuzzy search is Phase 8), no
/// `UserModel` yet (personal blending is Phase 9), so `S(w|ctx)` is always
/// the language model's own unigram probability.
public enum Ranker {
    public static func rank(
        completions: [LexiconCompletion],
        typedKey: String,
        lexicon: Lexicon,
        personalScores: [String: Double] = [:],
        config: RankerConfig = RankerConfig()
    ) -> [RankedSuggestion] {
        let context = ScoringContext(typedKey: typedKey, lexicon: lexicon, config: config, personalScores: personalScores)
        // Phase 7's completions are always exact-prefix matches — a real
        // (nonzero) edit cost only shows up once fuzzy search (Phase 8)
        // contributes candidates through `rank(fuzzy:...)` below.
        let ranked = completions.map { score(wordID: $0.wordID, surface: $0.surface, editCost: 0, context: context) }
        // Tie-break: lower word id (more frequent) — §6.7.5's own rule.
        return ranked.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
    }

    /// Same §6.7.5 formula as `rank(completions:...)`, but for fuzzy
    /// (typo-tolerant) candidates (task 8.4) — here `editCost` is the real
    /// weighted Damerau–Levenshtein distance rather than always 0, so the
    /// `channel(t|w) = 10^(-γ · editCost)` term actually penalizes distant
    /// matches.
    public static func rank(
        fuzzy: [FuzzyMatch],
        typedKey: String,
        lexicon: Lexicon,
        personalScores: [String: Double] = [:],
        config: RankerConfig = RankerConfig()
    ) -> [RankedSuggestion] {
        let context = ScoringContext(typedKey: typedKey, lexicon: lexicon, config: config, personalScores: personalScores)
        let ranked = fuzzy.map { score(wordID: $0.wordID, surface: $0.surface, editCost: $0.editCost, context: context) }
        return ranked.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
    }

    /// Task 9.4: candidates that exist *only* in the personal model (a
    /// genuinely new word the base language model has never seen) — no
    /// `wordID` to look up a language-model score for, so `S_lang` is
    /// simply `0` in §6.7.5's blend (`S(w|ctx) = λ·S_user + (1−λ)·0`).
    /// `lexicon` is still needed for `ScoringContext`'s shape even though
    /// this path never reads a language-model score from it.
    public static func rank(
        personalOnly candidates: [(surface: String, editCost: Double)],
        typedKey: String,
        lexicon: Lexicon,
        personalScores: [String: Double],
        config: RankerConfig = RankerConfig()
    ) -> [RankedSuggestion] {
        let context = ScoringContext(typedKey: typedKey, lexicon: lexicon, config: config, personalScores: personalScores)
        let ranked = candidates.map { score(wordID: nil, surface: $0.surface, editCost: $0.editCost, context: context) }
        return ranked.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
    }

    /// Task 9.4: re-blends an already-computed next-word candidate score
    /// (§6.7.3's Stupid Backoff, no channel/completion/bonus terms —
    /// there's no typed text to match against for an empty prefix) with
    /// `UserModel`'s own `S_user` for the same surface.
    public static func blendedNextWordScore(
        surface: String,
        log10LanguageScore: Double,
        personalScores: [String: Double],
        config: RankerConfig
    ) -> Double {
        blend(log10LanguageScore: log10LanguageScore, surface: surface, personalScores: personalScores, config: config)
    }

    /// Groups `rank`'s shared, per-call-invariant inputs so `score(...)`
    /// stays under SwiftLint's parameter-count limit.
    private struct ScoringContext {
        let typedKey: String
        let lexicon: Lexicon
        let config: RankerConfig
        let personalScores: [String: Double]
    }

    /// `wordID` is `nil` for a personal-only candidate the base language
    /// model has never seen (`rank(personalOnly:...)`) — `RankedSuggestion`
    /// still needs *some* `UInt32` (used only for sort tie-breaking and as
    /// an internal merge key elsewhere; `matchKey` is what actually
    /// identifies a word once personal candidates are in the mix), so this
    /// substitutes `UInt32.max` rather than a real language-model id.
    private static func score(wordID: UInt32?, surface: String, editCost: Double, context: ScoringContext) -> RankedSuggestion {
        let log10LanguageScore = wordID.map { context.lexicon.log10Probability($0) }
        let candidateKey = PersianNormalization.matchKey(surface)
        let log10Channel = -context.config.gamma * editCost
        let lengthDifference = min(max(candidateKey.count - context.typedKey.count, 0), context.config.completionLengthCap)
        let log10Completion = -context.config.completionLengthPenalty * Double(lengthDifference)
        let exactBonus = candidateKey == context.typedKey ? context.config.exactMatchBonus : 0
        let blendedLog10Score = blend(
            log10LanguageScore: log10LanguageScore,
            surface: surface,
            personalScores: context.personalScores,
            config: context.config
        )
        let total = blendedLog10Score + log10Channel + log10Completion + exactBonus
        return RankedSuggestion(wordID: wordID ?? UInt32.max, surface: surface, score: total)
    }

    /// §6.7.5's `S(w|ctx) = λ·S_user + (1−λ)·S_lang`, in linear probability
    /// space (both source scores are stored/computed as log10). `λ = 0`
    /// (the default until a personal-source mode is active) returns
    /// `log10LanguageScore` completely unchanged — task 8.5/8.6's existing,
    /// already-tested behavior — without ever touching `personalScores` or
    /// doing the `pow`/`log10` round trip.
    private static func blend(log10LanguageScore: Double?, surface: String, personalScores: [String: Double],
                              config: RankerConfig) -> Double
    {
        guard config.personalWeight > 0 else {
            return log10LanguageScore ?? -700 // no language-model score and no personal blending: unreachable in practice
        }
        let sUser = personalScores[PersianNormalization.matchKey(surface)] ?? 0
        let sLang = log10LanguageScore.map { pow(10, $0) } ?? 0
        let blended = config.personalWeight * sUser + (1 - config.personalWeight) * sLang
        return log10(max(blended, .leastNormalMagnitude))
    }

    /// §6.7.5's dedupe rule: collapse candidates that are really the same
    /// word, keeping the highest-ranked one — unless `preferZWNJForms` is
    /// on and a lower-ranked ZWNJ-spelled variant exists, in which case it
    /// takes over that ranking slot (content swap, not a position change).
    ///
    /// Grouped by `matchKey`, not `canonical(surface)` despite §6.7.5's own
    /// wording ("dedupe by canonical(surface)"): `canonical()` deliberately
    /// *preserves* internal ZWNJ (§6.6.2 only strips ZWNJ at word
    /// edges/next to a space), so "می‌خوام" and "میخوام" have two different
    /// canonical forms and would never collapse under that key — exactly
    /// the pair this dedup rule exists to merge (§6.7.2's own TTRM example
    /// groups them under one match key for this reason). `matchKey`, which
    /// strips ZWNJ unconditionally, is what actually treats them as the
    /// same word while still preserving *which* variant is which so the
    /// `preferZWNJForms` swap below can choose between them.
    public static func dedupe(_ ranked: [RankedSuggestion], preferZWNJForms: Bool) -> [RankedSuggestion] {
        var bestByMatchKey: [String: RankedSuggestion] = [:]
        var order: [String] = []
        for candidate in ranked {
            let matchKey = PersianNormalization.matchKey(candidate.surface)
            guard let existing = bestByMatchKey[matchKey] else {
                bestByMatchKey[matchKey] = candidate
                order.append(matchKey)
                continue
            }
            let candidateHasZWNJ = PersianNormalization.containsZWNJ(candidate.surface)
            let existingHasZWNJ = PersianNormalization.containsZWNJ(existing.surface)
            if preferZWNJForms, candidateHasZWNJ, !existingHasZWNJ {
                bestByMatchKey[matchKey] = candidate
            }
        }
        return order.compactMap { bestByMatchKey[$0] }
    }

    /// §6.7.5's English casing rule: all-caps typed text (≥2 letters)
    /// uppercases the candidate; an uppercase first letter (manual or at a
    /// sentence start under auto-cap) capitalizes it.
    public static func applyCasing(_ surface: String, typed: String, isSentenceStart: Bool) -> String {
        let letters = typed.filter(\.isLetter)
        if letters.count >= 2, letters == letters.uppercased(), letters != letters.lowercased() {
            return surface.uppercased()
        }
        if let firstTyped = typed.first, firstTyped.isUppercase {
            return capitalizeFirstLetter(surface)
        }
        if typed.isEmpty, isSentenceStart {
            return capitalizeFirstLetter(surface)
        }
        return surface
    }

    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
