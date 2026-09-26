import Foundation
import KelidCore
import PersianText

/// §6.7.8's commit source tags, reused for `UserModel`'s own increment
/// weights (§6.7.6: "typed and committed 1.0 · accepted suggestion 1.0 ·
/// tapped verbatim 2.0 · original word after an autocorrect revert 2.0 ·
/// 'learn from text' import 0.5 per occurrence").
public enum UserModelCommitSource: String, Sendable, Equatable, CaseIterable {
    case typed
    case accepted
    case verbatim
    case revert
    case importText
    case contacts
    case manual
}

/// One persisted personal word, as `UserModelStore` loads/flushes it —
/// `PredictionEngine`'s own narrow shape (§4.2: it can't depend on
/// `KelidStorage`/GRDB directly), mirroring `KelidStorage.UserWord`'s
/// fields exactly so `KeyboardUI`'s adapter is a straight field-for-field
/// conversion.
public struct UserModelWordRecord: Sendable, Equatable {
    public let surface: String
    public let matchKey: String
    public let count: Double
    public let lastUsedAt: Date
    public let source: UserModelCommitSource
    public let isBlocked: Bool

    public init(surface: String, matchKey: String, count: Double, lastUsedAt: Date, source: UserModelCommitSource,
                isBlocked: Bool = false)
    {
        self.surface = surface
        self.matchKey = matchKey
        self.count = count
        self.lastUsedAt = lastUsedAt
        self.source = source
        self.isBlocked = isBlocked
    }
}

public struct UserModelBigramRecord: Sendable, Equatable {
    public let w1: String
    public let w2: String
    public let count: Double
    public let lastUsedAt: Date

    public init(w1: String, w2: String, count: Double, lastUsedAt: Date) {
        self.w1 = w1
        self.w2 = w2
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

public struct UserModelTrigramRecord: Sendable, Equatable {
    public let w1: String
    public let w2: String
    public let w3: String
    public let count: Double
    public let lastUsedAt: Date

    public init(w1: String, w2: String, w3: String, count: Double, lastUsedAt: Date) {
        self.w1 = w1
        self.w2 = w2
        self.w3 = w3
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

public struct UserModelBlockedCorrection: Sendable, Hashable {
    public let typed: String
    public let corrected: String

    public init(typed: String, corrected: String) {
        self.typed = typed
        self.corrected = corrected
    }
}

/// Task 9.1/9.2's persistence seam — `PredictionEngine` can't depend on
/// `KelidStorage` (§4.2), so `UserModel` talks to this narrow protocol
/// instead; `KeyboardUI` (which depends on both) supplies a concrete
/// implementation backed by `KelidStorage.UserModelRepository`, bound to
/// one language, exactly like `ModelLocator`/`SuggestionService` already
/// does for the read-only KLM side.
public protocol UserModelStore: Sendable {
    func loadWords(limit: Int) async throws -> [UserModelWordRecord]
    func loadBigrams(limit: Int) async throws -> [UserModelBigramRecord]
    func loadTrigrams(limit: Int) async throws -> [UserModelTrigramRecord]
    func loadBlockedWords() async throws -> Set<String>
    func loadBlockedCorrections() async throws -> Set<UserModelBlockedCorrection>
    func flush(words: [UserModelWordRecord], bigrams: [UserModelBigramRecord], trigrams: [UserModelTrigramRecord]) async throws
    func setBlocked(_ blocked: Bool, surface: String) async throws
    func forget(surface: String) async throws
    func blockCorrection(typed: String, corrected: String) async throws
    /// Task 9.8's "Clear my learned words for this language."
    func deleteAllWords() async throws
}

public struct UserModelSettings: Sendable, Equatable {
    public var halfLifeDays: Double
    public var maxWords: Int
    public var maxBigrams: Int
    public var maxTrigrams: Int
    /// §6.7.8: "New words (not in the KLM) are stored right away but only
    /// suggested after `eff ≥ newWordThreshold`."
    public var newWordThreshold: Double

    public init(
        halfLifeDays: Double = 60,
        maxWords: Int = 20000,
        maxBigrams: Int = 30000,
        maxTrigrams: Int = 30000,
        newWordThreshold: Double = 2
    ) {
        self.halfLifeDays = halfLifeDays
        self.maxWords = maxWords
        self.maxBigrams = maxBigrams
        self.maxTrigrams = maxTrigrams
        self.newWordThreshold = newWordThreshold
    }
}

/// §6.7.6's `UserModel` (task 9.2) — one instance per language. Holds
/// interned words plus bigram/trigram stats in memory, computes §6.7.6's
/// exponential-decay `eff`/probability formulas, and write-behinds dirty
/// entries to a `UserModelStore` rather than writing on every keystroke.
///
/// The "small trie built from user words at load time" (§6.7.7, personal-
/// only fuzzy search) is a real, tiny `.klm` file built via the existing
/// `KLMWriter`/`KLMFile` machinery from Phase 7/8 — reusing that trie/fuzzy
/// implementation wholesale rather than duplicating it for a second,
/// user-scale vocabulary. This also *replaces* §6.7.6's own literal
/// "sorted array of (matchKey, id) for prefix scans" — the rebuilt
/// `Lexicon` already gives best-first-ranked prefix completions *and*
/// fuzzy search over the same data, a strict superset of what a bare
/// sorted-array binary search would provide.
public actor UserModel {
    private struct WordEntry {
        var surface: String
        var matchKey: String
        var count: Double
        var lastUsedAt: Date
        var source: UserModelCommitSource
    }

    /// Packed `(id1 << 32) | id2` — same packing scheme §6.7.6 itself
    /// specifies for bigrams.
    private typealias BigramKey = UInt64
    private struct TrigramKey: Hashable {
        let id1: UInt32
        let id2: UInt32
        let id3: UInt32
    }

    private struct NGramStat {
        var count: Double
        var lastUsedAt: Date
    }

    public let language: LanguageID
    private let settings: UserModelSettings
    private let store: UserModelStore
    private let clock: Clock

    private var surfaceToID: [String: UInt32] = [:]
    private var words: [UInt32: WordEntry] = [:]
    private var bigrams: [BigramKey: NGramStat] = [:]
    private var trigrams: [TrigramKey: NGramStat] = [:]
    private var blockedWords: Set<String> = []
    private var blockedCorrections: Set<UserModelBlockedCorrection> = []

    private var dirtyWordSurfaces: Set<String> = []
    private var dirtyBigramKeys: Set<BigramKey> = []
    private var dirtyTrigramKeys: Set<TrigramKey> = []

    private var nextID: UInt32 = 0
    public private(set) var isLoaded = false
    private var personalLexicon: Lexicon?
    private var personalLexiconTempFileURL: URL?

    public init(
        language: LanguageID,
        settings: UserModelSettings = UserModelSettings(),
        store: UserModelStore,
        clock: Clock = SystemClock()
    ) {
        self.language = language
        self.settings = settings
        self.store = store
        self.clock = clock
    }

    deinit {
        if let personalLexiconTempFileURL {
            try? FileManager.default.removeItem(at: personalLexiconTempFileURL)
        }
    }

    // MARK: - Load (task 9.2: "load asynchronously on first use")

    public func load() async throws {
        guard !isLoaded else { return }
        let wordRecords = try await store.loadWords(limit: settings.maxWords)
        for record in wordRecords {
            let id = internSurface(record.surface, matchKey: record.matchKey)
            words[id] = WordEntry(
                surface: record.surface, matchKey: record.matchKey, count: record.count, lastUsedAt: record.lastUsedAt,
                source: record.source
            )
        }

        for record in try await store.loadBigrams(limit: settings.maxBigrams) {
            guard let id1 = surfaceToID[record.w1], let id2 = surfaceToID[record.w2] else { continue }
            bigrams[Self.packBigram(id1, id2)] = NGramStat(count: record.count, lastUsedAt: record.lastUsedAt)
        }
        for record in try await store.loadTrigrams(limit: settings.maxTrigrams) {
            guard let id1 = surfaceToID[record.w1], let id2 = surfaceToID[record.w2], let id3 = surfaceToID[record.w3] else { continue }
            trigrams[TrigramKey(id1: id1, id2: id2, id3: id3)] = NGramStat(count: record.count, lastUsedAt: record.lastUsedAt)
        }
        blockedWords = try await store.loadBlockedWords()
        blockedCorrections = try await store.loadBlockedCorrections()
        isLoaded = true
    }

    public var wordCount: Int {
        words.count
    }

    public var bigramCount: Int {
        bigrams.count
    }

    public var trigramCount: Int {
        trigrams.count
    }

    // MARK: - Decay (§6.7.6)

    nonisolated func effectiveCount(_ count: Double, lastUsedAt: Date, now: Date) -> Double {
        let days = now.timeIntervalSince(lastUsedAt) / 86400
        return count * pow(0.5, days / settings.halfLifeDays)
    }

    /// Task 9.6: "contact names become no-decay user words" — `.manual`
    /// (a word added directly, e.g. a future dictionary-manager "add word"
    /// feature) gets the same treatment, since both are one-time entries a
    /// person deliberately added rather than something inferred from usage
    /// frequency that should fade if unused. Every other source still uses
    /// the plain time-decay formula above.
    private nonisolated func effectiveCount(_ entry: WordEntry, now: Date) -> Double {
        switch entry.source {
        case .manual, .contacts: entry.count
        case .typed, .accepted, .verbatim, .revert, .importText: effectiveCount(entry.count, lastUsedAt: entry.lastUsedAt, now: now)
        }
    }

    // MARK: - Commit recording (§6.7.6's increments, task 9.3 calls this)

    nonisolated static func increment(for source: UserModelCommitSource) -> Double {
        switch source {
        case .typed, .accepted: 1.0
        case .verbatim, .revert: 2.0
        case .importText: 0.5
        case .contacts, .manual: 0 // no-decay/one-time entries, not incremented by commits
        }
    }

    /// Records one committed word (§6.7.8's commit triggers) — updates
    /// `eff + increment`, marks it dirty for the next flush, and enforces
    /// the in-memory word cap. `previousWords` (already learnability-
    /// filtered, sentence-scoped) also updates the trailing bigram/trigram
    /// when `learnPhrases` is on and every word involved is learnable
    /// (both checked by the caller — `UserModel` trusts what it's given).
    public func recordCommit(surface: String, matchKey: String, source: UserModelCommitSource, previousWords: [String],
                             learnPhrases: Bool)
    {
        guard !blockedWords.contains(surface) else { return }
        let now = clock.now()
        let increment = Self.increment(for: source)

        let id = internSurface(surface, matchKey: matchKey)
        let priorEff = words[id].map { effectiveCount($0, now: now) } ?? 0
        words[id] = WordEntry(surface: surface, matchKey: matchKey, count: priorEff + increment, lastUsedAt: now, source: source)
        dirtyWordSurfaces.insert(surface)
        enforceWordCap()

        guard learnPhrases, let last = previousWords.last else { return }
        // `<s>` (sentence start) is never itself `recordCommit`-ed — unlike
        // a real previous word, which is always already interned by the
        // time it's used as context, since committing happens at every
        // word boundary in order — so it needs this lazy fallback rather
        // than requiring pre-existing interning. Its `eff` then stays at
        // its baseline (0), which just means `P_bi(w|<s>) = eff(<s>,w)/5`
        // — a fixed-denominator smoothing, not a real usage frequency, and
        // a reasonable approximation for "how often does a sentence start
        // with w."
        let lastID = surfaceToID[last] ?? internPseudoContextWord(last, now: now)
        recordBigram(id1: lastID, id2: id, now: now)
        if previousWords.count >= 2 {
            let secondLastSurface = previousWords[previousWords.count - 2]
            let secondLastID = surfaceToID[secondLastSurface] ?? internPseudoContextWord(secondLastSurface, now: now)
            recordTrigram(id1: secondLastID, id2: lastID, id3: id, now: now)
        }
    }

    /// Interns a context word (in practice, only ever `<s>`) that was never
    /// itself committed, with a zero-baseline `WordEntry` so bigram/trigram
    /// context lookups have something to read.
    private func internPseudoContextWord(_ surface: String, now: Date) -> UInt32 {
        let id = internSurface(surface, matchKey: surface)
        if words[id] == nil {
            words[id] = WordEntry(surface: surface, matchKey: surface, count: 0, lastUsedAt: now, source: .typed)
        }
        return id
    }

    private func recordBigram(id1: UInt32, id2: UInt32, now: Date) {
        let key = Self.packBigram(id1, id2)
        let existing = bigrams[key]
        let priorEff = existing.map { effectiveCount($0.count, lastUsedAt: $0.lastUsedAt, now: now) } ?? 0
        bigrams[key] = NGramStat(count: priorEff + 1.0, lastUsedAt: now)
        dirtyBigramKeys.insert(key)
        if bigrams.count > settings.maxBigrams {
            evictLowestEffNGram(from: &bigrams, dirty: &dirtyBigramKeys, now: now)
        }
    }

    private func recordTrigram(id1: UInt32, id2: UInt32, id3: UInt32, now: Date) {
        let key = TrigramKey(id1: id1, id2: id2, id3: id3)
        let existing = trigrams[key]
        let priorEff = existing.map { effectiveCount($0.count, lastUsedAt: $0.lastUsedAt, now: now) } ?? 0
        trigrams[key] = NGramStat(count: priorEff + 1.0, lastUsedAt: now)
        dirtyTrigramKeys.insert(key)
        if trigrams.count > settings.maxTrigrams {
            evictLowestEffNGram(from: &trigrams, dirty: &dirtyTrigramKeys, now: now)
        }
    }

    private func evictLowestEffNGram<Key: Hashable>(from table: inout [Key: NGramStat], dirty: inout Set<Key>, now: Date) {
        guard let worst = table.min(by: { effectiveCount($0.value.count, lastUsedAt: $0.value.lastUsedAt, now: now) <
                effectiveCount($1.value.count, lastUsedAt: $1.value.lastUsedAt, now: now)
        }) else { return }
        table.removeValue(forKey: worst.key)
        dirty.remove(worst.key)
    }

    /// §6.7.6's in-memory cap — evicts the lowest-`eff` word, never a
    /// `.manual` one ("never user-added words", same rule
    /// `UserModelRepository.prune` enforces on the DB side).
    private func enforceWordCap() {
        guard words.count > settings.maxWords else { return }
        let now = clock.now()
        guard let worst = words
            .filter({ $0.value.source != .manual })
            .min(by: { effectiveCount($0.value, now: now) < effectiveCount($1.value, now: now) })
        else { return }
        words.removeValue(forKey: worst.key)
        surfaceToID.removeValue(forKey: worst.value.surface)
        dirtyWordSurfaces.remove(worst.value.surface)
    }

    // MARK: - Block / forget (task 9.5's long-press menu)

    public func block(surface: String) async throws {
        blockedWords.insert(surface)
        try await store.setBlocked(true, surface: surface)
    }

    public func unblock(surface: String) async throws {
        blockedWords.remove(surface)
        try await store.setBlocked(false, surface: surface)
    }

    public func isBlocked(_ surface: String) -> Bool {
        blockedWords.contains(surface)
    }

    public func forget(surface: String) async throws {
        if let id = surfaceToID[surface] {
            words.removeValue(forKey: id)
            surfaceToID.removeValue(forKey: surface)
            bigrams = bigrams.filter { !Self.bigramMentions(id, $0.key) }
            trigrams = trigrams.filter { !Self.trigramMentions(id, $0.key) }
        }
        dirtyWordSurfaces.remove(surface)
        blockedWords.remove(surface)
        try await store.forget(surface: surface)
    }

    /// Task 9.6: "contact names become user words with source `contacts`
    /// and no decay" — each name not already known is seeded directly
    /// (bypassing `recordCommit`'s increment-based path entirely, since a
    /// contact name should be immediately suggestable, not need to "earn"
    /// visibility the way a fresh typo-turned-word does via
    /// `newWordThreshold`). An already-known name (e.g. re-imported on a
    /// later refresh) is left untouched, so real usage since the last
    /// import is never overwritten back down to the seed baseline.
    public func addContactNames(_ names: [String]) {
        let now = clock.now()
        let baseline = max(settings.newWordThreshold * 2, 10)
        for name in names where !name.isEmpty && surfaceToID[name] == nil {
            let matchKey = PersianNormalization.matchKey(name)
            let id = internSurface(name, matchKey: matchKey)
            words[id] = WordEntry(surface: name, matchKey: matchKey, count: baseline, lastUsedAt: now, source: .contacts)
            dirtyWordSurfaces.insert(name)
        }
        enforceWordCap()
    }

    public func blockCorrection(typed: String, corrected: String) async throws {
        blockedCorrections.insert(UserModelBlockedCorrection(typed: typed, corrected: corrected))
        try await store.blockCorrection(typed: typed, corrected: corrected)
    }

    public func isBlockedCorrection(typed: String, corrected: String) -> Bool {
        blockedCorrections.contains(UserModelBlockedCorrection(typed: typed, corrected: corrected))
    }

    /// Task 9.8's Quick Settings "Clear my learned words for this language"
    /// — every in-memory word/n-gram/blocklist entry, plus the persisted
    /// rows behind them, are gone; the personal lexicon is rebuilt (to an
    /// empty one) so completions/fuzzy search stop offering anything
    /// already-deleted straight away rather than waiting for the next
    /// natural rebuild trigger.
    public func clearAll() async throws {
        words.removeAll()
        surfaceToID.removeAll()
        bigrams.removeAll()
        trigrams.removeAll()
        blockedWords.removeAll()
        blockedCorrections.removeAll()
        dirtyWordSurfaces.removeAll()
        dirtyBigramKeys.removeAll()
        dirtyTrigramKeys.removeAll()
        try await store.deleteAllWords()
        try? rebuildPersonalLexicon(baseLexicon: nil)
    }

    private static func bigramMentions(_ id: UInt32, _ key: BigramKey) -> Bool {
        let id1 = UInt32(key >> 32)
        let id2 = UInt32(key & 0xFFFF_FFFF)
        return id1 == id || id2 == id
    }

    private static func trigramMentions(_ id: UInt32, _ key: TrigramKey) -> Bool {
        key.id1 == id || key.id2 == id || key.id3 == id
    }

    // MARK: - Probabilities (§6.7.6)

    /// `P_uni(w) = eff(w) / (Σ eff + 50)`.
    public func unigramProbability(_ surface: String) -> Double? {
        guard let id = surfaceToID[surface], let entry = words[id] else { return nil }
        let now = clock.now()
        let eff = effectiveCount(entry, now: now)
        let total = words.values.reduce(0.0) { $0 + effectiveCount($1, now: now) }
        return eff / (total + 50)
    }

    /// `P_bi(w|w1) = eff(w1,w) / (eff(w1) + 5)`.
    public func bigramProbability(context w1: String, word: String) -> Double? {
        guard let id1 = surfaceToID[w1], let id2 = surfaceToID[word], let contextEntry = words[id1],
              let stat = bigrams[Self.packBigram(id1, id2)]
        else { return nil }
        let now = clock.now()
        let eff = effectiveCount(stat.count, lastUsedAt: stat.lastUsedAt, now: now)
        let contextEff = effectiveCount(contextEntry, now: now)
        return eff / (contextEff + 5)
    }

    /// `P_tri(w|w1,w2) = eff(w1,w2,w) / (eff(w1,w2) + 3)`.
    public func trigramProbability(w1: String, w2: String, word: String) -> Double? {
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
    public func stupidBackoffScore(word: String, w1: String?, w2: String?) -> Double {
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
    public func isSuggestable(_ surface: String, isKnownToLanguageModel: Bool) -> Bool {
        guard let id = surfaceToID[surface], let entry = words[id] else { return false }
        guard !isKnownToLanguageModel else { return true }
        return effectiveCount(entry, now: clock.now()) >= settings.newWordThreshold
    }

    // MARK: - Personal-only candidate generation (§6.7.7)

    /// Rebuilds the small in-memory `.klm` trie used for personal-only
    /// mode's completions/fuzzy search — a real (tiny) file built via
    /// `KLMWriter`, reusing `Lexicon`'s existing best-first/fuzzy code
    /// wholesale. Only includes words that pass `isSuggestable` against
    /// `baseLexicon` (so a fresh one-off typo can't show up in personal
    /// completions before it's actually learned).
    public func rebuildPersonalLexicon(baseLexicon: Lexicon?) throws {
        let suggestable = words.values.filter { entry in
            isSuggestable(entry.surface, isKnownToLanguageModel: baseLexicon?.wordID(forSurface: entry.surface) != nil)
        }
        guard !suggestable.isEmpty else {
            personalLexicon = nil
            return
        }
        let now = clock.now()
        let unigrams = suggestable.map { entry in
            UnigramEntry(surface: entry.surface, count: UInt64(effectiveCount(entry, now: now) * 1000))
        }
        let data = try KLMWriter.build(language: language, unigrams: unigrams, maxWords: settings.maxWords)
        if let personalLexiconTempFileURL {
            try? FileManager.default.removeItem(at: personalLexiconTempFileURL)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelid-usermodel-\(language.rawValue)-\(UUID().uuidString).klm")
        try data.write(to: url)
        personalLexiconTempFileURL = url
        personalLexicon = try Lexicon(file: KLMFile(path: url.path))
    }

    public func personalCompletions(prefixKey: String, limit: Int = 20) -> [LexiconCompletion] {
        guard let personalLexicon else { return [] }
        return personalLexicon.completions(prefixKey: prefixKey, limit: limit).filter { !blockedWords.contains($0.surface) }
    }

    public func personalFuzzyMatches(typedKey: String, proximity: FuzzyProximityMap, limit: Int = 20) -> [FuzzyMatch] {
        guard let personalLexicon else { return [] }
        return personalLexicon.fuzzyMatches(typedKey: typedKey, proximity: proximity, limit: limit)
            .filter { !blockedWords.contains($0.surface) }
    }

    // MARK: - Write-behind flush (§6.7.6: "every 5s, on disappear, on background")

    public func flush() async throws {
        guard !dirtyWordSurfaces.isEmpty || !dirtyBigramKeys.isEmpty || !dirtyTrigramKeys.isEmpty else { return }
        let wordDeltas: [UserModelWordRecord] = dirtyWordSurfaces.compactMap { surface in
            guard let id = surfaceToID[surface], let entry = words[id] else { return nil }
            return UserModelWordRecord(
                surface: entry.surface, matchKey: entry.matchKey, count: entry.count, lastUsedAt: entry.lastUsedAt, source: entry.source
            )
        }
        let bigramDeltas: [UserModelBigramRecord] = dirtyBigramKeys.compactMap { key in
            guard let stat = bigrams[key] else { return nil }
            let id1 = UInt32(key >> 32)
            let id2 = UInt32(key & 0xFFFF_FFFF)
            guard let w1 = words[id1]?.surface, let w2 = words[id2]?.surface else { return nil }
            return UserModelBigramRecord(w1: w1, w2: w2, count: stat.count, lastUsedAt: stat.lastUsedAt)
        }
        let trigramDeltas: [UserModelTrigramRecord] = dirtyTrigramKeys.compactMap { key in
            guard let stat = trigrams[key], let w1 = words[key.id1]?.surface, let w2 = words[key.id2]?.surface,
                  let w3 = words[key.id3]?.surface
            else { return nil }
            return UserModelTrigramRecord(w1: w1, w2: w2, w3: w3, count: stat.count, lastUsedAt: stat.lastUsedAt)
        }
        try await store.flush(words: wordDeltas, bigrams: bigramDeltas, trigrams: trigramDeltas)
        dirtyWordSurfaces.removeAll()
        dirtyBigramKeys.removeAll()
        dirtyTrigramKeys.removeAll()
    }

    // MARK: - Interning

    private func internSurface(_ surface: String, matchKey _: String) -> UInt32 {
        if let existing = surfaceToID[surface] {
            return existing
        }
        let id = nextID
        nextID += 1
        surfaceToID[surface] = id
        return id
    }

    private static func packBigram(_ id1: UInt32, _ id2: UInt32) -> BigramKey {
        (BigramKey(id1) << 32) | BigramKey(id2)
    }
}
