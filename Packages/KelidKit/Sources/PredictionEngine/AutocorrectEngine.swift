import PersianText

/// §6.7.9's autocorrect decision (task 8.6) — pure and independent of
/// `InputEngine`/field traits (§4.2: `PredictionEngine` can't depend on
/// `InputEngine`). Rule 1 (mode is `.auto`, the field allows it, prediction
/// is enabled) and rule 5/6 (actually replacing the text, remembering
/// `lastAutocorrection`, reverting on backspace) are `KeyboardUI`'s and
/// `InputProcessor`'s jobs respectively; this only decides *what* `t` would
/// become, given it's already known the decision is worth asking for.
public enum AutocorrectEngine {
    /// §6.7.9 rule 3's `q_min` — a word already scored at or above this (out
    /// of the quantized `0...255` unigram score range) counts as "already
    /// known" and is never autocorrected away.
    public static let knownWordScoreThreshold: UInt8 = 20

    /// `nil` means "no change" — either `t` is already fine, or no candidate
    /// clears the correction bar. Rule 3's other half ("or it isn't in the
    /// user model with `eff ≥ 1`") is Phase 9's `UserModel` and out of scope
    /// here, same as every other personal-learning input to this formula.
    public static func decide(
        typed: String,
        lexicon: Lexicon,
        proximity: FuzzyProximityMap,
        strength: Double,
        config: RankerConfig = RankerConfig()
    ) -> String? {
        let key = PersianNormalization.matchKey(typed)
        guard key.count >= 2 else { return nil } // rule 2: >= 2 graphemes
        guard !typed.contains(where: \.isNumber) else { return nil } // rule 2: no digits
        guard !isAllCaps(typed) else { return nil } // rule 2: not all caps (English)
        guard !looksLikeURLOrEmail(typed) else { return nil } // rule 2: not URL/email-like

        // Rule 3: `t` is not already a known word.
        if let existingID = lexicon.wordID(forSurface: typed), lexicon.score(existingID) >= knownWordScoreThreshold {
            return nil
        }

        // Rule 4: the best candidate must be a real correction (a positive
        // edit cost — `prefixMode: false` since `t` is a *complete* word at
        // this point, not something still being typed) with a clear margin
        // over the runner-up. `τ = 1.0 − 0.8·strength` (log10 units).
        let maxCost = Lexicon.fuzzyMaxCost(forTypedLength: key.count)
        let matches = lexicon.fuzzyMatches(typedKey: key, proximity: proximity, prefixMode: false, limit: 5)
            .filter { $0.editCost > 0 && $0.editCost <= maxCost }
        guard !matches.isEmpty else { return nil }
        let ranked = Ranker.rank(fuzzy: matches, typedKey: key, lexicon: lexicon, config: config)
        guard let best = ranked.first else { return nil }
        let tau = 1.0 - 0.8 * strength
        if let second = ranked.dropFirst().first, best.score - second.score < tau {
            return nil
        }
        return best.surface
    }

    private static func isAllCaps(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 2 && letters == letters.uppercased() && letters != letters.lowercased()
    }

    /// A best-effort, single-word heuristic — good enough to avoid
    /// "correcting" the middle of something like `user@example.com` or
    /// `example.com` typed directly into a text field (rather than a
    /// dedicated URL/email field, where autocorrect is already off by
    /// field trait).
    private static func looksLikeURLOrEmail(_ text: String) -> Bool {
        if text.contains("@"), text.contains(".") {
            return true
        }
        if text.contains("://") {
            return true
        }
        if text.lowercased().hasPrefix("www.") {
            return true
        }
        if let dotIndex = text.firstIndex(of: "."), dotIndex != text.startIndex, text.index(after: dotIndex) < text.endIndex {
            return true
        }
        return false
    }
}
