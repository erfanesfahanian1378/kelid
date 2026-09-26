import KelidCore
import PersianText

/// §6.7.4's `SuggestionRequest.context` — the same shape as
/// `InputEngine.TypingContext`, but `PredictionEngine` can't import
/// `InputEngine` (§4.2's dependency table has them as siblings, not one
/// depending on the other) — `KeyboardUI`, which depends on both, converts
/// between the two when calling `SuggestionService`.
public struct SuggestionContext: Sendable, Equatable {
    public var prefix: String
    public var suffix: String
    public var previousWords: [String]
    public var isSentenceStart: Bool
    public var language: LanguageID

    public init(
        prefix: String,
        suffix: String,
        previousWords: [String],
        isSentenceStart: Bool,
        language: LanguageID
    ) {
        self.prefix = prefix
        self.suffix = suffix
        self.previousWords = previousWords
        self.isSentenceStart = isSentenceStart
        self.language = language
    }
}

/// The narrow slice of `KelidSettings.PredictionSettings` `SuggestionService`
/// actually reads — same "narrow slice" pattern `InputEngine.InputSettings`
/// already established in Phase 3, for the same reason: `PredictionEngine`
/// doesn't depend on `KelidSettings` (§4.2).
public struct PredictionEngineSettings: Sendable, Equatable {
    public var enabled: Bool
    public var suggestionCount: Int
    public var showVerbatimSlot: Bool
    public var preferZWNJForms: Bool
    public var blockOffensive: Bool
    /// Task 8.11: `KelidSettings.PredictionSettings.nextWord` — whether an
    /// empty prefix (after a space or at a sentence start) predicts next
    /// words at all (task 8.2). Doesn't affect a non-empty prefix's own
    /// completions.
    public var nextWordEnabled: Bool
    /// Task 8.6: `KelidSettings.AutocorrectMode != .off` — `.suggestOnly`
    /// also wants the candidate computed (to bold it in the center slot,
    /// §6.7.5), just not auto-applied; only `KeyboardUI` (which knows the
    /// actual 3-way mode) decides whether to *apply* it, so this is
    /// deliberately just a bool, not `PredictionEngine`'s own copy of that
    /// enum (§4.2: it can't depend on `KelidSettings` anyway).
    public var autocorrectEnabled: Bool
    public var autocorrectStrength: Double

    public init(
        enabled: Bool = true,
        suggestionCount: Int = 3,
        showVerbatimSlot: Bool = true,
        preferZWNJForms: Bool = true,
        blockOffensive: Bool = true,
        nextWordEnabled: Bool = true,
        autocorrectEnabled: Bool = false,
        autocorrectStrength: Double = 0.5
    ) {
        self.enabled = enabled
        self.suggestionCount = suggestionCount
        self.showVerbatimSlot = showVerbatimSlot
        self.preferZWNJForms = preferZWNJForms
        self.blockOffensive = blockOffensive
        self.nextWordEnabled = nextWordEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.autocorrectStrength = autocorrectStrength
    }
}

/// A ranked candidate ready for display/insertion — `KeyboardUI` maps this
/// to `InputEngine.Suggestion` when constructing `.insertSuggestion(_:)`.
public struct SuggestionCandidate: Sendable, Equatable {
    public let text: String
    public let wordID: UInt32?

    public init(text: String, wordID: UInt32? = nil) {
        self.text = text
        self.wordID = wordID
    }
}

public struct SuggestionRequest: Sendable, Equatable {
    public let generation: Int
    public let context: SuggestionContext
    public let settings: PredictionEngineSettings
    public let incognito: Bool

    public init(generation: Int, context: SuggestionContext, settings: PredictionEngineSettings, incognito: Bool) {
        self.generation = generation
        self.context = context
        self.settings = settings
        self.incognito = incognito
    }
}

public struct SuggestionResult: Sendable, Equatable {
    public var verbatim: SuggestionCandidate?
    public var items: [SuggestionCandidate]
    public var autocorrect: SuggestionCandidate?
    public var emoji: [String]

    public init(verbatim: SuggestionCandidate?, items: [SuggestionCandidate], autocorrect: SuggestionCandidate?, emoji: [String]) {
        self.verbatim = verbatim
        self.items = items
        self.autocorrect = autocorrect
        self.emoji = emoji
    }
}

/// §6.7.4. Completion + next-word + fuzzy (Phase 7/8): personal learning
/// still needs pieces that don't exist yet (`UserModel`) — `learn(_:)` from
/// §6.7.4's full API isn't implemented yet for that reason (its parameter
/// type, `CommitEvent`, is Phase 9's). `updateLayout(_:for:)` takes
/// `FuzzyProximityMap` rather than §6.7.4's literal `ProximityMap` — the
/// same "narrow slice" reasoning as `SuggestionContext`/
/// `PredictionEngineSettings` (§4.2: `PredictionEngine` can't depend on
/// `KeyboardLayout`); `KeyboardUI` builds one from the real
/// `KeyboardLayout.ProximityMap` on layout or size change and calls this.
public actor SuggestionService {
    private var lexicons: [LanguageID: Lexicon] = [:]
    private var files: [LanguageID: KLMFile] = [:] // kept alive alongside their Lexicon
    private var proximityMaps: [LanguageID: FuzzyProximityMap] = [:]
    private var latestGeneration = Int.min

    public init() {}

    public func load(languages: [LanguageID], resources: any ModelLocator) async throws {
        for language in languages {
            guard let url = resources.url(for: language) else { continue }
            let file = try KLMFile(path: url.path)
            files[language] = file
            lexicons[language] = Lexicon(file: file)
        }
    }

    /// Task 8.4: called on layout load or size-class change so fuzzy search
    /// has an up-to-date "adjacent key" map for the current keyboard.
    /// Missing a call (e.g. before the first layout load) just means fuzzy
    /// search falls back to `.empty` — still fully functional via the
    /// Persian confusion groups and the generic 1.0 substitution cost, just
    /// without the 0.6 adjacency discount.
    public func updateLayout(_ proximity: FuzzyProximityMap, for language: LanguageID) {
        proximityMaps[language] = proximity
    }

    /// `nil` means "superseded by a newer request" (§6.7.4) — checked both
    /// before and after doing the work, since a truly newer request could
    /// in principle complete first even though this method has no real
    /// suspension point in its current (synchronous, mmap-backed) body.
    public func suggest(_ request: SuggestionRequest) async -> SuggestionResult? {
        guard request.generation >= latestGeneration else { return nil }
        latestGeneration = request.generation

        guard request.generation == latestGeneration else { return nil }
        guard request.settings.enabled, !request.incognito else { return nil }
        guard request.context.suffix.isEmpty else { return nil } // mid-word cursor — suggestions disabled (v1, §6.4.8)
        guard let lexicon = lexicons[request.context.language] else { return nil }

        let typed = request.context.prefix
        let contextIDs = Self.resolveContextIDs(previousWords: request.context.previousWords, lexicon: lexicon)

        var ranked: [RankedSuggestion]
        if typed.isEmpty {
            // Task 8.11: `nextWord` setting off -> no empty-prefix
            // predictions at all (a non-empty prefix's completions are
            // unaffected either way).
            guard request.settings.nextWordEnabled else { return nil }
            // Task 8.2: next-word prediction — nothing to suggest without
            // any n-gram data at all (a unigrams-only model, e.g. before
            // `make data-full` has run — see Phase 6's own handoff notes).
            guard lexicon.hasBigrams || lexicon.hasTrigrams else { return nil }
            let nextWords = BackoffScorer.nextWords(lexicon: lexicon, w1: contextIDs.w1, w2: contextIDs.w2, limit: 32)
            ranked = nextWords.map { RankedSuggestion(wordID: $0.wordID, surface: $0.surface, score: $0.log10Score) }
        } else {
            let key = PersianNormalization.matchKey(typed)
            let completions = lexicon.completions(prefixKey: key, limit: 32)
            ranked = Ranker.rank(completions: completions, typedKey: key, lexicon: lexicon)

            // Task 8.3's full candidate set: trie completions (above) ∪
            // fuzzy (typo-tolerant) matches ∪ context-aware next-word
            // candidates whose match key starts with what's already typed
            // (user-model candidates are Phase 9). All merged by keeping
            // the higher score per word id, since each source's score is on
            // the same log10 scale (§6.7.5's `S(w|ctx) + channel + …`) even
            // though they come from different formulas.
            let proximity = proximityMaps[request.context.language] ?? .empty
            let fuzzy = lexicon.fuzzyMatches(typedKey: key, proximity: proximity, limit: 32)
            var candidateLists = ranked + Ranker.rank(fuzzy: fuzzy, typedKey: key, lexicon: lexicon)

            if lexicon.hasBigrams || lexicon.hasTrigrams {
                let contextCandidates = BackoffScorer.contextAwareCandidates(
                    lexicon: lexicon, w1: contextIDs.w1, w2: contextIDs.w2, typedKey: key, limit: 32
                )
                candidateLists += contextCandidates.map { RankedSuggestion(wordID: $0.wordID, surface: $0.surface, score: $0.log10Score) }
            }

            var bestByID: [UInt32: RankedSuggestion] = [:]
            for candidate in candidateLists {
                if let existing = bestByID[candidate.wordID], existing.score >= candidate.score {
                    continue
                }
                bestByID[candidate.wordID] = candidate
            }
            ranked = bestByID.values.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
        }

        ranked = Ranker.dedupe(ranked, preferZWNJForms: request.settings.preferZWNJForms)
        if request.settings.blockOffensive {
            ranked = ranked.filter { !lexicon.isOffensive($0.wordID) }
        }

        let isEnglish = request.context.language == .en
        let candidates = ranked.map { candidate -> SuggestionCandidate in
            let surface = isEnglish
                ? Ranker.applyCasing(candidate.surface, typed: typed, isSentenceStart: request.context.isSentenceStart)
                : candidate.surface
            return SuggestionCandidate(text: surface, wordID: candidate.wordID)
        }

        // No typed text -> nothing sensible to show in the verbatim slot,
        // regardless of `showVerbatimSlot` (there's nothing the user typed
        // yet to echo back).
        let verbatim = (request.settings.showVerbatimSlot && !typed.isEmpty) ? SuggestionCandidate(text: typed) : nil
        let items = Array(candidates.prefix(max(request.settings.suggestionCount, 0)))

        // Task 8.6: kept continuously up to date (like every other field
        // here) so it's already on hand the instant a separator is typed —
        // `KeyboardUI` never needs a fresh async round-trip just to decide
        // whether to autocorrect.
        var autocorrect: SuggestionCandidate?
        if request.settings.autocorrectEnabled, !typed.isEmpty {
            let proximity = proximityMaps[request.context.language] ?? .empty
            if let corrected = AutocorrectEngine.decide(
                typed: typed,
                lexicon: lexicon,
                proximity: proximity,
                strength: request.settings.autocorrectStrength
            ) {
                let surface = isEnglish ? Ranker
                    .applyCasing(corrected, typed: typed, isSentenceStart: request.context.isSentenceStart) : corrected
                autocorrect = SuggestionCandidate(text: surface, wordID: lexicon.wordID(forSurface: corrected))
            }
        }

        guard request.generation == latestGeneration else { return nil }
        return SuggestionResult(verbatim: verbatim, items: items, autocorrect: autocorrect, emoji: [])
    }

    /// §6.7.3's `nextWords(w1?, w2)` context: `previousWords.last` is the
    /// immediately-preceding word (`w2`); the entry before it, if any, is
    /// `w1`. Either can fail to resolve (a word not in this model's
    /// vocabulary) without failing the whole request — `nextWords` already
    /// treats a `nil` `w1`/`w2` as "no data at that order," backing off
    /// further exactly as §6.7.3 describes.
    private static func resolveContextIDs(previousWords: [String], lexicon: Lexicon) -> (w1: UInt32?, w2: UInt32?) {
        guard let last = previousWords.last else { return (nil, nil) }
        let w2 = lexicon.wordID(forExactSurface: last)
        guard previousWords.count >= 2 else { return (nil, w2) }
        let w1 = lexicon.wordID(forExactSurface: previousWords[previousWords.count - 2])
        return (w1, w2)
    }
}
