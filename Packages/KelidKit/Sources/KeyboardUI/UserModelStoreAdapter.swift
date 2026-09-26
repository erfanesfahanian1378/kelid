#if canImport(UIKit)
    import Foundation
    import KelidCore
    import KelidStorage
    import PredictionEngine

    /// Task 9.1/9.2's storage seam — `PredictionEngine.UserModel` talks only
    /// to the narrow `UserModelStore` protocol (§4.2: it can't depend on
    /// `KelidStorage` directly); this is the concrete adapter `KeyboardUI`
    /// supplies, one per language, each wrapping the same
    /// `KelidStorage.UserModelRepository` (itself a thin GRDB actor around
    /// one `DatabaseManager`).
    struct UserModelStoreAdapter: UserModelStore {
        let repository: UserModelRepository
        let language: LanguageID

        func loadWords(limit: Int) async throws -> [UserModelWordRecord] {
            try await repository.loadWords(language: language, limit: limit).map {
                UserModelWordRecord(
                    surface: $0.surface, matchKey: $0.matchKey, count: $0.count, lastUsedAt: $0.lastUsedAt,
                    source: Self.commitSource(for: $0.source), isBlocked: $0.isBlocked
                )
            }
        }

        func loadBigrams(limit: Int) async throws -> [UserModelBigramRecord] {
            try await repository.loadBigrams(language: language, limit: limit).map {
                UserModelBigramRecord(w1: $0.w1, w2: $0.w2, count: $0.count, lastUsedAt: $0.lastUsedAt)
            }
        }

        func loadTrigrams(limit: Int) async throws -> [UserModelTrigramRecord] {
            try await repository.loadTrigrams(language: language, limit: limit).map {
                UserModelTrigramRecord(w1: $0.w1, w2: $0.w2, w3: $0.w3, count: $0.count, lastUsedAt: $0.lastUsedAt)
            }
        }

        func loadBlockedWords() async throws -> Set<String> {
            try await repository.loadBlockedWords(language: language)
        }

        func loadBlockedCorrections() async throws -> Set<UserModelBlockedCorrection> {
            let pairs = try await repository.loadBlockedCorrections(language: language)
            return Set(pairs.map { UserModelBlockedCorrection(typed: $0.typed, corrected: $0.corrected) })
        }

        func flush(words: [UserModelWordRecord], bigrams: [UserModelBigramRecord], trigrams: [UserModelTrigramRecord]) async throws {
            let wordDeltas = words.map {
                UserWordDelta(
                    surface: $0.surface, matchKey: $0.matchKey, count: $0.count, lastUsedAt: $0.lastUsedAt,
                    source: Self.wordSource(for: $0.source)
                )
            }
            let bigramDeltas = bigrams.map { UserBigramDelta(w1: $0.w1, w2: $0.w2, count: $0.count, lastUsedAt: $0.lastUsedAt) }
            let trigramDeltas = trigrams.map {
                UserTrigramDelta(w1: $0.w1, w2: $0.w2, w3: $0.w3, count: $0.count, lastUsedAt: $0.lastUsedAt)
            }
            try await repository.flush(language: language, words: wordDeltas, bigrams: bigramDeltas, trigrams: trigramDeltas)
        }

        func setBlocked(_ blocked: Bool, surface: String) async throws {
            try await repository.setBlocked(blocked, surface: surface, language: language)
        }

        func forget(surface: String) async throws {
            try await repository.forget(surface: surface, language: language)
        }

        func blockCorrection(typed: String, corrected: String) async throws {
            try await repository.blockCorrection(typed: typed, corrected: corrected, language: language)
        }

        func deleteAllWords() async throws {
            try await repository.deleteAll(language: language)
        }

        /// `UserModelCommitSource` has two cases (`.verbatim`/`.revert`) with
        /// no direct storage equivalent — both are "the user typed this
        /// themselves," same bucket as `.typed` for storage/pruning purposes
        /// (only `.manual`/`.contacts`/`.importSource` are ever treated
        /// specially, by `UserModelRepository.prune`'s "never evict .manual").
        private static func wordSource(for source: UserModelCommitSource) -> UserWordSource {
            switch source {
            case .typed, .verbatim, .revert: .typed
            case .accepted: .accepted
            case .importText: .importSource
            case .contacts: .contacts
            case .manual: .manual
            }
        }

        /// The inverse mapping, used when *loading* rows back — `.replacement`
        /// (a `KelidStorage`-only case, currently unused: text replacements
        /// are never persisted as user words, see task 9.6) maps to
        /// `.manual`'s no-decay/never-evicted treatment as the closest fit.
        private static func commitSource(for source: UserWordSource) -> UserModelCommitSource {
            switch source {
            case .typed: .typed
            case .accepted: .accepted
            case .manual: .manual
            case .importSource: .importText
            case .contacts: .contacts
            case .replacement: .manual
            }
        }
    }
#endif
