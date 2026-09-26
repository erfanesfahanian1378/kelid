import PersianText

/// §6.7.3's next-word candidate + Stupid Backoff scoring:
///
/// ```text
/// candidates = trigram entries (w1, w2) ∪ bigram entries (w2) ∪ top-20 unigrams
/// S(w|w1,w2) = P_tri if present, else 0.4 × P_bi if present, else 0.16 × P_uni
/// log10 S = log10 P + k·log10(0.4)
/// ```
public struct NextWordCandidate: Sendable, Equatable {
    public let wordID: UInt32
    public let surface: String
    /// The Stupid-Backoff-adjusted `log10 S(w|context)` — already includes
    /// the `k·log10(0.4)` penalty for whichever order actually matched.
    public let log10Score: Double
}

public enum BackoffScorer {
    private static let log10PointFour = -0.3979400086720376 // log10(0.4), precomputed (Foundation-free)

    /// `w1`/`w2` are the previous two words' ids (`w2` is the *immediately*
    /// preceding word; `w1` the one before that) — `nil` when unavailable
    /// (e.g. at a sentence start, where only `<s>`'s id is meaningful as
    /// `w2`). Hidden words (`<s>`) are never returned as a candidate
    /// themselves, only used as context.
    public static func nextWords(lexicon: Lexicon, w1: UInt32?, w2: UInt32?, limit: Int = 20) -> [NextWordCandidate] {
        var bestLog10Score: [UInt32: Double] = [:]

        if let w1, let w2, lexicon.hasTrigrams {
            for candidate in lexicon.trigramCandidates(forContext: w1, w2) {
                bestLog10Score[candidate.next] = lexicon.log10TrigramProbability(candidate.score)
            }
        }
        if let w2, lexicon.hasBigrams {
            for candidate in lexicon.bigramCandidates(forContext: w2) where bestLog10Score[candidate.next] == nil {
                bestLog10Score[candidate.next] = lexicon.log10BigramProbability(candidate.score) + log10PointFour
            }
        }
        // Top-20 unigrams: word ids are assigned by descending frequency
        // (§6.7.2), so ids `0..<20` (skipping hidden entries) already *are*
        // the top-20 unigrams — no separate lookup needed.
        var unigramsAdded = 0
        var nextID: UInt32 = 0
        while unigramsAdded < 20, Int(nextID) < lexicon.wordCount {
            defer { nextID += 1 }
            guard lexicon.flags(nextID) & KLMFormat.WordFlags.hidden == 0 else { continue }
            unigramsAdded += 1
            guard bestLog10Score[nextID] == nil else { continue }
            bestLog10Score[nextID] = lexicon.log10Probability(nextID) + 2 * log10PointFour
        }

        return bestLog10Score
            .map { NextWordCandidate(wordID: $0.key, surface: lexicon.surface($0.key), log10Score: $0.value) }
            .sorted { $0.log10Score == $1.log10Score ? $0.wordID < $1.wordID : $0.log10Score > $1.log10Score }
            .prefix(limit)
            .map { $0 }
    }

    /// Task 8.3's third candidate set: next-word candidates whose surface's
    /// `matchKey` starts with the typed key — "what makes a rare but
    /// contextually likely word appear from its first letter."
    public static func contextAwareCandidates(lexicon: Lexicon, w1: UInt32?, w2: UInt32?, typedKey: String,
                                              limit: Int = 20) -> [NextWordCandidate]
    {
        guard !typedKey.isEmpty else { return [] }
        return nextWords(lexicon: lexicon, w1: w1, w2: w2, limit: limit * 4)
            .filter { PersianNormalization.matchKey($0.surface).hasPrefix(typedKey) }
            .prefix(limit)
            .map { $0 }
    }
}
