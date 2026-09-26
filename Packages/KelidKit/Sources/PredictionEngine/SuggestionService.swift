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

    public init(
        enabled: Bool = true,
        suggestionCount: Int = 3,
        showVerbatimSlot: Bool = true,
        preferZWNJForms: Bool = true,
        blockOffensive: Bool = true
    ) {
        self.enabled = enabled
        self.suggestionCount = suggestionCount
        self.showVerbatimSlot = showVerbatimSlot
        self.preferZWNJForms = preferZWNJForms
        self.blockOffensive = blockOffensive
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

/// §6.7.4. Completion-only for Phase 7 (task 7.6): next-word, fuzzy
/// (typo-tolerant) matching, autocorrect and personal learning all need
/// pieces that don't exist yet (`ProximityMap` wiring, `UserModel`) and
/// arrive with Phase 8/9 — `learn(_:)`/`updateLayout(_:for:)` from §6.7.4's
/// full API aren't implemented yet for the same reason (their parameter
/// types, `CommitEvent`/`ProximityMap`, live in modules `PredictionEngine`
/// doesn't depend on either).
public actor SuggestionService {
    private var lexicons: [LanguageID: Lexicon] = [:]
    private var files: [LanguageID: KLMFile] = [:] // kept alive alongside their Lexicon
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
        // Phase 7 is completion-only — an empty prefix would mean next-word
        // prediction, which needs n-gram data the KLM doesn't have until
        // Phase 8.
        guard !typed.isEmpty else { return nil }

        let key = PersianNormalization.matchKey(typed)
        let completions = lexicon.completions(prefixKey: key, limit: 32)
        var ranked = Ranker.rank(completions: completions, typedKey: key, lexicon: lexicon)
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

        let verbatim = request.settings.showVerbatimSlot ? SuggestionCandidate(text: typed) : nil
        let items = Array(candidates.prefix(max(request.settings.suggestionCount, 0)))

        guard request.generation == latestGeneration else { return nil }
        return SuggestionResult(verbatim: verbatim, items: items, autocorrect: nil, emoji: [])
    }
}
