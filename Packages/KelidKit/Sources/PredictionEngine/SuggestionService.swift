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

/// §6.7.7's 4 prediction source modes — `PredictionEngine`'s own copy of
/// `KelidSettings.PredictionSource` (§4.2: it can't depend on
/// `KelidSettings`). `.personalOnly`/`.languageOnly` map to fixed λ (1.0/
/// 0.0 per §6.7.7's own table) rather than needing their own separate code
/// paths — see `SuggestionService.effectivePersonalWeight`.
public enum PredictionSourceMode: Sendable, Equatable {
    case off
    case personalOnly
    case languageOnly
    case hybrid
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
    /// Task 9.4 (§6.7.7).
    public var source: PredictionSourceMode
    /// λ for `.hybrid` specifically — `.personalOnly`/`.languageOnly` use
    /// their own fixed λ (1.0/0.0) regardless of this value.
    public var personalWeight: Double

    public init(
        enabled: Bool = true,
        suggestionCount: Int = 3,
        showVerbatimSlot: Bool = true,
        preferZWNJForms: Bool = true,
        blockOffensive: Bool = true,
        nextWordEnabled: Bool = true,
        autocorrectEnabled: Bool = false,
        autocorrectStrength: Double = 0.5,
        source: PredictionSourceMode = .languageOnly,
        personalWeight: Double = 0.6
    ) {
        self.enabled = enabled
        self.suggestionCount = suggestionCount
        self.showVerbatimSlot = showVerbatimSlot
        self.preferZWNJForms = preferZWNJForms
        self.blockOffensive = blockOffensive
        self.nextWordEnabled = nextWordEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.source = source
        self.personalWeight = personalWeight
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

/// §6.7.4. `learn(_:)`/`UserModel[lang]` (task 9.2–9.4) are real now;
/// `updateLayout(_:for:)` takes `FuzzyProximityMap` rather than §6.7.4's
/// literal `ProximityMap` — the same "narrow slice" reasoning as
/// `SuggestionContext`/`PredictionEngineSettings` (§4.2: `PredictionEngine`
/// can't depend on `KeyboardLayout`); `KeyboardUI` builds one from the real
/// `KeyboardLayout.ProximityMap` on layout or size change and calls this.
public actor SuggestionService {
    private var lexicons: [LanguageID: Lexicon] = [:]
    private var files: [LanguageID: KLMFile] = [:] // kept alive alongside their Lexicon
    private var proximityMaps: [LanguageID: FuzzyProximityMap] = [:]
    private var userModels: [LanguageID: UserModel] = [:]
    /// Task 9.6: `requestSupplementaryLexicon`'s text replacements, keyed by
    /// `matchKey(shortcut)` — checked against the typed word's own matchKey
    /// in `suggest(_:)`, not persisted (refreshed by `KeyboardUI` on its own
    /// 1-hour cache cycle, straight from the live system list each time).
    private var textReplacements: [LanguageID: [String: String]] = [:]
    private var latestGeneration = Int.min
    /// Task 9.2/10.6's "reload on `.userdict.changed`" — set up once, the
    /// first time `loadUserModels` runs.
    private var userDictObservationToken: DarwinObservationToken?

    public init() {}

    public func load(languages: [LanguageID], resources: any ModelLocator) async throws {
        for language in languages {
            guard let url = resources.url(for: language) else { continue }
            let file = try KLMFile(path: url.path)
            files[language] = file
            lexicons[language] = Lexicon(file: file)
        }
    }

    // MARK: - Personal learning (task 9.2/9.4)

    /// Loads a `UserModel` per language from its own `UserModelStore` —
    /// `KeyboardUI` supplies one backed by `KelidStorage.UserModelRepository`
    /// (§4.2: `PredictionEngine` can't depend on `KelidStorage` directly).
    public func loadUserModels(_ stores: [LanguageID: any UserModelStore], settings: UserModelSettings = UserModelSettings()) async throws {
        for (language, store) in stores {
            let model = UserModel(language: language, settings: settings, store: store)
            try await model.load()
            try? await model.rebuildPersonalLexicon(baseLexicon: lexicons[language])
            userModels[language] = model
        }
        observeUserDictChangesIfNeeded()
    }

    /// Task 9.2/10.6: reloads every loaded `UserModel` from its store —
    /// wired once here rather than in `KeyboardUI`, so `PredictionEngine`
    /// stays the one place that owns `UserModel`'s whole lifecycle.
    private func observeUserDictChangesIfNeeded() {
        guard userDictObservationToken == nil else { return }
        userDictObservationToken = DarwinNotifier.shared.observe(.userDictChanged) { [weak self] in
            guard let self else { return }
            Task { await self.reloadUserModels() }
        }
    }

    private func reloadUserModels() async {
        for (language, model) in userModels {
            try? await model.reload()
            try? await model.rebuildPersonalLexicon(baseLexicon: lexicons[language])
        }
    }

    /// Task 9.6: `requestSupplementaryLexicon`'s text replacements
    /// (`userInput → documentText`) — `KeyboardUI` calls this once per hour
    /// (its own cache window) with whatever `UILexicon` currently reports.
    /// Replaces the whole table for `language` rather than merging, so a
    /// shortcut deleted in iOS Settings actually disappears here too.
    public func updateTextReplacements(_ replacements: [String: String], for language: LanguageID) {
        textReplacements[language] = Dictionary(
            replacements.map { (PersianNormalization.matchKey($0.key), $0.value) }, uniquingKeysWith: { _, new in new }
        )
    }

    /// Task 9.6: "contact names become no-decay user words" — forwarded
    /// straight to that language's `UserModel`; a no-op if it hasn't loaded
    /// yet (same tolerance every other `UserModel`-touching method here has).
    public func addContactNames(_ names: [String], language: LanguageID) async {
        guard let model = userModels[language] else { return }
        await model.addContactNames(names)
        try? await model.rebuildPersonalLexicon(baseLexicon: lexicons[language])
    }

    /// §6.7.8's commit — `KeyboardUI` calls this after its own
    /// `learning.enabled`/incognito checks pass (`InputProcessor` only
    /// checks field-sensitivity/word-shape, §4.2: it can't reach
    /// `KelidSettings.LearningSettings`/`KeyboardState.incognito` either).
    public func recordCommit(
        word: String,
        language: LanguageID,
        source: UserModelCommitSource,
        previousWords: [String],
        learnPhrases: Bool
    ) async {
        guard let model = userModels[language] else { return }
        let matchKey = PersianNormalization.matchKey(word)
        await model.recordCommit(
            surface: word,
            matchKey: matchKey,
            source: source,
            previousWords: previousWords,
            learnPhrases: learnPhrases
        )
        // The personal candidate set changes meaningfully only rarely
        // (a brand-new word crossing `newWordThreshold`); rebuilding after
        // every single commit would be wasteful, but rebuilding is cheap
        // enough (task 8.10-style: a tiny vocabulary) that doing it here,
        // synchronously with the commit that might have changed it, is
        // simpler and safer than trying to detect exactly when a rebuild is
        // actually needed.
        try? await model.rebuildPersonalLexicon(baseLexicon: lexicons[language])
    }

    /// §6.7.6's write-behind flush — call every 5s, on `viewWillDisappear`,
    /// and on host background (task 9.2).
    public func flushUserModels() async {
        for model in userModels.values {
            try? await model.flush()
        }
    }

    public func block(surface: String, language: LanguageID) async throws {
        try await userModels[language]?.block(surface: surface)
    }

    public func unblock(surface: String, language: LanguageID) async throws {
        try await userModels[language]?.unblock(surface: surface)
    }

    /// §6.7.8's "Forget" — also drops the word from the rebuilt personal
    /// lexicon immediately, not just the next flush.
    public func forget(surface: String, language: LanguageID) async throws {
        try await userModels[language]?.forget(surface: surface)
        try? await userModels[language]?.rebuildPersonalLexicon(baseLexicon: lexicons[language])
    }

    public func blockCorrection(typed: String, corrected: String, language: LanguageID) async throws {
        try await userModels[language]?.blockCorrection(typed: typed, corrected: corrected)
    }

    /// Task 9.8's Quick Settings "Clear my learned words for this language."
    public func clearPersonalData(for language: LanguageID) async throws {
        try await userModels[language]?.clearAll()
    }

    /// Task 9.10's "still learning" hint threshold check.
    public func personalWordCount(for language: LanguageID) async -> Int {
        guard let model = userModels[language] else { return 0 }
        return await model.wordCount
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
        // §6.7.7: "Off: none (only the clip chip and toolbar are shown)" —
        // learning (via `.learn` effects / `recordCommit`) is a completely
        // separate code path from `suggest(_:)`, so it's unaffected by this.
        guard request.settings.source != .off else { return nil }
        guard request.context.suffix.isEmpty else { return nil } // mid-word cursor — suggestions disabled (v1, §6.4.8)
        guard let lexicon = lexicons[request.context.language] else { return nil }

        let typed = request.context.prefix
        let contextIDs = Self.resolveContextIDs(previousWords: request.context.previousWords, lexicon: lexicon)
        // §6.7.7's own table: `.personalOnly`/`.languageOnly` are fixed
        // λ = 1.0/0.0, not independently-coded modes — `.hybrid` alone uses
        // the user's own slider value.
        let lambda: Double = switch request.settings.source {
        case .off: 0 // unreachable (already returned above)
        case .personalOnly: 1.0
        case .languageOnly: 0.0
        case .hybrid: request.settings.personalWeight
        }
        let userModel = lambda > 0 ? userModels[request.context.language] : nil
        // §6.7.7: "Personal only: UserModel only" — the language model's
        // own candidates are excluded from the *set* entirely, not merely
        // outscored, since an unblended one would otherwise still surface
        // when nothing personal outranks it (there's nothing to rank it
        // below). Empty-prefix personal-only next-word prediction isn't
        // implemented this phase (`UserModel` has no "enumerate top n-gram
        // continuations" API yet, only "score a given word") — see
        // PROGRESS.md — so personal-only + empty prefix has no candidates
        // at all for now, rather than silently leaking an unblended one.
        let isPersonalOnly = request.settings.source == .personalOnly
        let rankerConfig = RankerConfig(personalWeight: lambda)

        var ranked: [RankedSuggestion]
        if typed.isEmpty {
            guard !isPersonalOnly else { return nil }
            guard let nextWordRanked = await rankNextWordCandidates(
                request: request, lexicon: lexicon, contextIDs: contextIDs, userModel: userModel, rankerConfig: rankerConfig
            ) else { return nil }
            ranked = nextWordRanked
        } else {
            ranked = await rankPrefixCandidates(
                typed: typed, request: request, lexicon: lexicon, contextIDs: contextIDs, userModel: userModel,
                isPersonalOnly: isPersonalOnly, rankerConfig: rankerConfig
            )
        }

        ranked = Ranker.dedupe(ranked, preferZWNJForms: request.settings.preferZWNJForms)
        if request.settings.blockOffensive {
            // `wordID == .max` marks a personal-only candidate (task 9.4:
            // `Ranker.rank(personalOnly:...)`, no language-model id at all)
            // — `lexicon.isOffensive` must never be called with it, since
            // it isn't a valid id in *this* lexicon and would read out of
            // the mmapped `.klm` file's bounds. Personal words aren't
            // auto-flagged offensive by construction; §6.7.8's block/forget
            // is the mechanism for those instead.
            ranked = ranked.filter { $0.wordID == UInt32.max || !lexicon.isOffensive($0.wordID) }
        }

        let isEnglish = request.context.language == .en
        let candidates = ranked.map { candidate -> SuggestionCandidate in
            let surface = isEnglish
                ? Ranker.applyCasing(candidate.surface, typed: typed, isSentenceStart: request.context.isSentenceStart)
                : candidate.surface
            // Never leak the internal "no language-model id" sentinel
            // (`Ranker`'s `personalOnly` candidates) — `nil` is the real,
            // documented meaning of `SuggestionCandidate.wordID` for that.
            return SuggestionCandidate(text: surface, wordID: candidate.wordID == UInt32.max ? nil : candidate.wordID)
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
            ), await !(userModel?.isBlockedCorrection(typed: typed, corrected: corrected) ?? false) {
                let surface = isEnglish ? Ranker
                    .applyCasing(corrected, typed: typed, isSentenceStart: request.context.isSentenceStart) : corrected
                autocorrect = SuggestionCandidate(text: surface, wordID: lexicon.wordID(forSurface: corrected))
            }
        }

        guard request.generation == latestGeneration else { return nil }
        return SuggestionResult(verbatim: verbatim, items: items, autocorrect: autocorrect, emoji: [])
    }

    /// Task 8.11/8.2/9.4: empty-prefix next-word branch of `suggest(_:)`,
    /// extracted to keep that function under SwiftLint's line-length limit.
    /// `nil` means "no empty-prefix predictions at all" — either the
    /// `nextWord` setting is off, or the lexicon has no n-gram data yet
    /// (a unigrams-only model, e.g. before `make data-full` has run — see
    /// Phase 6's own handoff notes) — distinct from "predictions, but zero
    /// candidates," which returns `[]` instead.
    private func rankNextWordCandidates(
        request: SuggestionRequest,
        lexicon: Lexicon,
        contextIDs: (w1: UInt32?, w2: UInt32?),
        userModel: UserModel?,
        rankerConfig: RankerConfig
    ) async -> [RankedSuggestion]? {
        guard request.settings.nextWordEnabled else { return nil }
        guard lexicon.hasBigrams || lexicon.hasTrigrams else { return nil }
        let previousWords = request.context.previousWords
        let w1Surface: String? = previousWords.count >= 2 ? previousWords[previousWords.count - 2] : nil
        let w2Surface = previousWords.last
        let nextWords = BackoffScorer.nextWords(lexicon: lexicon, w1: contextIDs.w1, w2: contextIDs.w2, limit: 32)
        var personalScores: [String: Double] = [:]
        if let userModel {
            for candidate in nextWords {
                personalScores[PersianNormalization.matchKey(candidate.surface)] = await userModel.stupidBackoffScore(
                    word: candidate.surface, w1: w1Surface, w2: w2Surface
                )
            }
        }
        return nextWords.map { candidate in
            let score = userModel != nil
                ? Ranker.blendedNextWordScore(
                    surface: candidate.surface, log10LanguageScore: candidate.log10Score, personalScores: personalScores,
                    config: rankerConfig
                )
                : candidate.log10Score
            return RankedSuggestion(wordID: candidate.wordID, surface: candidate.surface, score: score)
        }
    }

    /// Task 9.4: non-empty-prefix branch of `suggest(_:)`, extracted for the
    /// same reason as `rankNextWordCandidates`. Gathers language-lexicon
    /// completions/fuzzy/context candidates (skipped entirely in
    /// personal-only mode — see the comment on `isPersonalOnly` in
    /// `suggest(_:)`), personal-only candidates (a word the language model
    /// has never seen at all), and `S_user` for *every* candidate surface
    /// seen so far from any source — one shared dictionary feeds every
    /// blended score, so a word found via two different sources blends
    /// identically either way. Merged by `matchKey`, not `wordID`: a
    /// personal-only candidate and a language-model candidate use
    /// independent id spaces (two separate `.klm`-backed lexicons), so only
    /// the surface identifies a word uniquely once both are in the mix.
    private func rankPrefixCandidates(
        typed: String,
        request: SuggestionRequest,
        lexicon: Lexicon,
        contextIDs: (w1: UInt32?, w2: UInt32?),
        userModel: UserModel?,
        isPersonalOnly: Bool,
        rankerConfig: RankerConfig
    ) async -> [RankedSuggestion] {
        let key = PersianNormalization.matchKey(typed)
        let proximity = proximityMaps[request.context.language] ?? .empty
        let completions = isPersonalOnly ? [] : lexicon.completions(prefixKey: key, limit: 32)
        let fuzzy = isPersonalOnly ? [] : lexicon.fuzzyMatches(typedKey: key, proximity: proximity, limit: 32)
        let contextCandidates = (!isPersonalOnly && (lexicon.hasBigrams || lexicon.hasTrigrams))
            ? BackoffScorer.contextAwareCandidates(lexicon: lexicon, w1: contextIDs.w1, w2: contextIDs.w2, typedKey: key, limit: 32)
            : []

        let previousWords = request.context.previousWords
        let w1Surface: String? = previousWords.count >= 2 ? previousWords[previousWords.count - 2] : nil
        let w2Surface = previousWords.last

        var personalScores: [String: Double] = [:]
        var personalOnlyCandidates: [(surface: String, editCost: Double)] = []
        if let userModel {
            var knownSurfaces = Set(completions.map(\.surface) + fuzzy.map(\.surface) + contextCandidates.map(\.surface))
            let personalCompletions = await userModel.personalCompletions(prefixKey: key, limit: 32)
            let personalFuzzy = await userModel.personalFuzzyMatches(typedKey: key, proximity: proximity, limit: 32)
            for match in personalCompletions where !knownSurfaces.contains(match.surface) {
                personalOnlyCandidates.append((surface: match.surface, editCost: 0))
                knownSurfaces.insert(match.surface)
            }
            for match in personalFuzzy where !knownSurfaces.contains(match.surface) {
                personalOnlyCandidates.append((surface: match.surface, editCost: match.editCost))
                knownSurfaces.insert(match.surface)
            }
            for surface in knownSurfaces {
                personalScores[PersianNormalization.matchKey(surface)] = await userModel.stupidBackoffScore(
                    word: surface, w1: w1Surface, w2: w2Surface
                )
            }
        }

        var candidateLists = Ranker.rank(
            completions: completions,
            typedKey: key,
            lexicon: lexicon,
            personalScores: personalScores,
            config: rankerConfig
        )
            + Ranker.rank(fuzzy: fuzzy, typedKey: key, lexicon: lexicon, personalScores: personalScores, config: rankerConfig)
        if !personalOnlyCandidates.isEmpty {
            candidateLists += Ranker.rank(
                personalOnly: personalOnlyCandidates, typedKey: key, lexicon: lexicon, personalScores: personalScores,
                config: rankerConfig
            )
        }
        candidateLists += contextCandidates.map { candidate in
            let score = userModel != nil
                ? Ranker.blendedNextWordScore(
                    surface: candidate.surface, log10LanguageScore: candidate.log10Score, personalScores: personalScores,
                    config: rankerConfig
                )
                : candidate.log10Score
            return RankedSuggestion(wordID: candidate.wordID, surface: candidate.surface, score: score)
        }

        var bestByMatchKey: [String: RankedSuggestion] = [:]
        for candidate in candidateLists {
            let matchKey = PersianNormalization.matchKey(candidate.surface)
            if let existing = bestByMatchKey[matchKey], existing.score >= candidate.score {
                continue
            }
            bestByMatchKey[matchKey] = candidate
        }
        // Task 9.6: "Text replacements appear as the best suggestion when
        // the typed word equals the shortcut" — `.greatestFiniteMagnitude`
        // guarantees first place regardless of anything else in the mix,
        // and unconditionally overwrites any same-matchKey LM/personal
        // candidate (a user's own configured shortcut always wins).
        if let phrase = textReplacements[request.context.language]?[key] {
            let matchKey = PersianNormalization.matchKey(phrase)
            bestByMatchKey[matchKey] = RankedSuggestion(wordID: UInt32.max, surface: phrase, score: .greatestFiniteMagnitude)
        }
        return bestByMatchKey.values.sorted { $0.score == $1.score ? $0.wordID < $1.wordID : $0.score > $1.score }
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
