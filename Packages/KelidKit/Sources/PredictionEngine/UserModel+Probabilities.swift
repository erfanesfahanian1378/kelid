import Foundation

/// §6.7.6's probability formulas, split out of UserModel.swift to clear
/// SwiftLint's `type_body_length` error threshold — same recurring pattern
/// as decisions 27/32/39/62. Behaviorally a no-op: still one actor, same
/// isolation, same tests.
public extension UserModel {
    // MARK: - Probabilities (§6.7.6)

    /// `P_uni(w) = eff(w) / (Σ eff + 50)`.
    func unigramProbability(_ surface: String) -> Double? {
        guard let id = surfaceToID[surface], let entry = words[id] else { return nil }
        let now = clock.now()
        let eff = effectiveCount(entry, now: now)
        let total = words.values.reduce(0.0) { $0 + effectiveCount($1, now: now) }
        return eff / (total + 50)
    }

    /// `P_bi(w|w1) = eff(w1,w) / (eff(w1) + 5)`.
    func bigramProbability(context w1: String, word: String) -> Double? {
        guard let id1 = surfaceToID[w1], let id2 = surfaceToID[word], let contextEntry = words[id1],
              let stat = bigrams[Self.packBigram(id1, id2)]
        else { return nil }
        let now = clock.now()
        let eff = effectiveCount(stat.count, lastUsedAt: stat.lastUsedAt, now: now)
        let contextEff = effectiveCount(contextEntry, now: now)
        return eff / (contextEff + 5)
    }

    /// `P_tri(w|w1,w2) = eff(w1,w2,w) / (eff(w1,w2) + 3)`.
    func trigramProbability(w1: String, w2: String, word: String) -> Double? {
        guard let id1 = surfaceToID[w1], let id2 = surfaceToID[w2], let id3 = surfaceToID[word],
              let contextStat = bigrams[Self.packBigram(id1, id2)],
              let stat = trigrams[TrigramKey(id1: id1, id2: id2, id3: id3)]
        else { return nil }
        let now = clock.now()
        let eff = effectiveCount(stat.count, lastUsedAt: stat.lastUsedAt, now: now)
        let contextEff = effectiveCount(contextStat.count, lastUsedAt: contextStat.lastUsedAt, now: now)
        return eff / (contextEff + 3)
    }

    /// `S_user` — the same Stupid-Backoff shape §6.7.3 uses for the
    /// language model (trigram if present, else `0.4×` bigram, else
    /// `0.16×` unigram), applied to `UserModel`'s own real-valued
    /// probabilities. `0` (not `nil`) for a word the model has never seen,
    /// so callers can blend it directly without an extra optional check.
    func stupidBackoffScore(word: String, w1: String?, w2: String?) -> Double {
        if let w1, let w2, let triProb = trigramProbability(w1: w1, w2: w2, word: word) {
            return triProb
        }
        if let w2, let biProb = bigramProbability(context: w2, word: word) {
            return 0.4 * biProb
        }
        if let uniProb = unigramProbability(word) {
            return 0.16 * uniProb
        }
        return 0
    }

    /// §6.7.8's "new words ... only suggested after `eff ≥
    /// newWordThreshold`" — `isKnownToLanguageModel` lets the caller (which
    /// has the base `Lexicon`) exempt words the base model already knows,
    /// since that rule only exists to keep one-off typos out of
    /// suggestions for genuinely *new* coinages.
    func isSuggestable(_ surface: String, isKnownToLanguageModel: Bool) -> Bool {
        guard let id = surfaceToID[surface], let entry = words[id] else { return false }
        guard !isKnownToLanguageModel else { return true }
        return effectiveCount(entry, now: clock.now()) >= settings.newWordThreshold
    }
}
