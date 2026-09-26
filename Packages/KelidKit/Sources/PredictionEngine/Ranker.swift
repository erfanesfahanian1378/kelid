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

    public init(
        gamma: Double = 1.2,
        completionLengthPenalty: Double = 0.05,
        completionLengthCap: Int = 6,
        exactMatchBonus: Double = 0.15
    ) {
        self.gamma = gamma
        self.completionLengthPenalty = completionLengthPenalty
        self.completionLengthCap = completionLengthCap
        self.exactMatchBonus = exactMatchBonus
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
        config: RankerConfig = RankerConfig()
    ) -> [RankedSuggestion] {
        let ranked = completions.map { completion -> RankedSuggestion in
            let log10LanguageScore = lexicon.log10Probability(completion.wordID)
            let candidateKey = PersianNormalization.matchKey(completion.surface)
            // Phase 7's completions are always exact-prefix matches — a real
            // (nonzero) edit cost only shows up once fuzzy search (Phase 8)
            // contributes candidates through this same ranker.
            let editCost = 0.0
            let log10Channel = -config.gamma * editCost
            let lengthDifference = min(max(candidateKey.count - typedKey.count, 0), config.completionLengthCap)
            let log10Completion = -config.completionLengthPenalty * Double(lengthDifference)
            let exactBonus = candidateKey == typedKey ? config.exactMatchBonus : 0
            let score = log10LanguageScore + log10Channel + log10Completion + exactBonus
            return RankedSuggestion(wordID: completion.wordID, surface: completion.surface, score: score)
        }
        // Tie-break: lower word id (more frequent) — §6.7.5's own rule.
        return ranked.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
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
