#if canImport(UIKit)
    import Foundation
    import InputEngine
    import KelidCore
    import KelidSettings
    import KelidStorage
    import KeyboardLayout
    import PredictionEngine
    import UIKit

    /// Prediction (Phase 7/9) — model loading, building a `SuggestionRequest`
    /// from `InputProcessor`'s own `TypingContext`, and turning a tapped
    /// suggestion bar slot into `.insertSuggestion(_:)` — split out of
    /// `KeyboardController.swift` itself purely to keep that type's body
    /// under SwiftLint's `type_body_length`; behaviorally this is still
    /// part of `KeyboardController`, just declared in a second file.
    extension KeyboardController {
        /// Task 7.6/9.2: "loads models in a background Task (utility
        /// priority) after the first frame" — called once from `init`, after
        /// `rebuild()` has already produced the keyboard's first real
        /// layout, so this never delays it. Loads both the base language
        /// models (Phase 7) and each language's personal `UserModel` (task
        /// 9.2) from the same `userModelDatabase` `KeyboardServices` hands
        /// this controller — one `UserModelStoreAdapter` per language,
        /// wrapping a shared `UserModelRepository`.
        func loadPredictionModels() {
            Task(priority: .utility) { [suggestionService] in
                try? await suggestionService.load(languages: LanguageID.allCases, resources: ExtensionModelLocator())
            }
            let repository = UserModelRepository(database: userModelDatabase)
            let learning = settings.learning
            let userModelSettings = UserModelSettings(
                halfLifeDays: Double(learning.halfLifeDays),
                maxWords: learning.maxUserWords,
                newWordThreshold: Double(learning.newWordThreshold)
            )
            let stores: [LanguageID: any UserModelStore] = Dictionary(
                uniqueKeysWithValues: LanguageID.allCases.map { ($0, UserModelStoreAdapter(repository: repository, language: $0)) }
            )
            Task(priority: .utility) { [suggestionService] in
                try? await suggestionService.loadUserModels(stores, settings: userModelSettings)
            }
        }

        /// Task 9.2's write-behind flush (§6.7.6: "5 s / disappear /
        /// background") — started from `viewWillAppear`/stopped from
        /// `viewDidDisappear`, same lifecycle as `startClipboardPolling()`/
        /// `stopClipboardPolling()` (including the selector-based `Timer`
        /// API, per decision 24: the closure-based overload risks landing in
        /// `@Sendable`/non-isolated territory under Swift 6 strict
        /// concurrency for a `@MainActor`-isolated target/selector).
        public func startUserModelFlushTimer() {
            stopUserModelFlushTimer()
            userModelFlushTimer = Timer.scheduledTimer(
                timeInterval: 5.0, target: self, selector: #selector(handleUserModelFlushTick), userInfo: nil, repeats: true
            )
        }

        /// Also flushes immediately — covers both the "disappear" and
        /// "background" halves of §6.7.6's write-behind trigger list, since
        /// `KeyboardViewController` calls this from `viewDidDisappear` and
        /// this controller has no separate background-only hook of its own.
        public func stopUserModelFlushTimer() {
            userModelFlushTimer?.invalidate()
            userModelFlushTimer = nil
            Task { [suggestionService] in
                await suggestionService.flushUserModels()
            }
        }

        @objc fileprivate func handleUserModelFlushTick() {
            Task { [suggestionService] in
                await suggestionService.flushUserModels()
            }
        }

        /// Task 9.7: the toolbar's incognito toggle — flips the session-only
        /// `KeyboardState.incognito` flag (gates both learning, via `.learn`
        /// below, and suggestion requests, already checked in
        /// `requestSuggestions()`) and persists it to
        /// `KelidSettings.LearningSettings.incognito` too, since §6.1.6 lists
        /// it as edited from both "KB" and "App." Also clears any suggestion
        /// bar immediately, matching "no chip/no suggestions while
        /// incognito."
        public func toggleIncognito() {
            state.incognito = !state.incognito
            let newValue = state.incognito
            onRequestSettingsChange? { $0.learning.incognito = newValue }
            rootView.toolbarStrip.setIncognito(state.incognito)
            restyle()
            state.suggestions = nil
            requestSuggestions()
        }

        /// §6.7.8's commit — `InputProcessor` already filtered by field-
        /// sensitivity and word shape (task 9.3); this is the other half
        /// only `KeyboardUI` can check (`learning.enabled`/incognito, per
        /// `SuggestionService.recordCommit`'s own doc comment), then forwards
        /// to `PredictionEngine`'s wider `UserModelCommitSource` (a strict
        /// superset of `InputEngine.CommitSource` — see that type's doc
        /// comment).
        func handleLearn(_ event: CommitEvent) {
            guard settings.learning.enabled, !state.incognito else { return }
            let learnPhrases = settings.learning.learnPhrases
            let source = Self.userModelCommitSource(for: event.source)
            let language = event.language
            Task { [suggestionService] in
                await suggestionService.recordCommit(
                    word: event.word,
                    language: language,
                    source: source,
                    previousWords: event.previousWords,
                    learnPhrases: learnPhrases
                )
                // §6.7.8: "Reverting an autocorrect adds the pair
                // (typed → corrected) to blockedCorrections."
                if let revertedCorrection = event.revertedCorrection {
                    try? await suggestionService.blockCorrection(typed: event.word, corrected: revertedCorrection, language: language)
                }
            }
        }

        /// Task 9.6: `KeyboardViewController` is the only thing that can
        /// call `UIInputViewController.requestSupplementaryLexicon` at all
        /// — it parses the raw `UILexicon` (its own text-replacement-vs-
        /// contact-name heuristic) and hands the two halves here.
        /// `replacements` applies to the *current* typing language only,
        /// same as every other per-language prediction setting — `UILexicon`
        /// itself has no language tagging, so a shortcut typed in the other
        /// language simply won't match until the user switches to it (this
        /// call is re-made on every language change's next appearance
        /// anyway, via the same 1-hour cache path).
        public func applySupplementaryLexicon(textReplacements: [String: String], contactNames: [String]) {
            let language = state.language
            Task { [suggestionService] in
                await suggestionService.updateTextReplacements(textReplacements, for: language)
                await suggestionService.addContactNames(contactNames, language: language)
            }
        }

        private static func userModelCommitSource(for source: CommitSource) -> UserModelCommitSource {
            switch source {
            case .typed: .typed
            case .accepted: .accepted
            case .verbatim: .verbatim
            case .revert: .revert
            }
        }

        /// Task 7.8: bridges `KeyboardState.suggestions` to the toolbar's
        /// actual suggestion bar — same `withObservationTracking`
        /// re-registration pattern as `observeToolbarText()`. Called once
        /// from `init`.
        func observeSuggestions() {
            withObservationTracking {
                _ = state.suggestions
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.applySuggestionsToToolbar()
                    self.observeSuggestions()
                }
            }
        }

        private func applySuggestionsToToolbar() {
            // §6.1.4's toolbar.mode: `.iconsOnly`/`.hidden` never show the
            // suggestion bar even when there's a real result to show;
            // `.auto`/`.suggestionsOnly` do.
            let mode = settings.toolbar.mode
            let result = (mode == .iconsOnly || mode == .hidden) ? nil : state.suggestions
            rootView.toolbarStrip.applySuggestions(result, isRTL: state.language == .fa)
        }

        /// Wires the toolbar strip's suggestion-bar callbacks — called once
        /// from `init`, alongside its other `rootView.toolbarStrip.onTap*`
        /// wiring.
        func wireSuggestionBar() {
            rootView.toolbarStrip.onTapSuggestionSlot = { [weak self] slotIndex in
                guard let self, let result = state.suggestions else { return }
                let slots = ToolbarStripView.slots(for: result)
                guard slotIndex < slots.count else { return }
                let slot = slots[slotIndex]
                let candidate = (result.items + [result.verbatim].compactMap { $0 }).first { $0.text == slot.text }
                    ?? SuggestionCandidate(text: slot.text)
                tapSuggestion(candidate, isVerbatim: slot.isVerbatim)
            }
            rootView.toolbarStrip.onLongPressSuggestionSlot = { [weak self] slotIndex in
                guard let self, let result = state.suggestions else { return }
                let slots = ToolbarStripView.slots(for: result)
                guard slotIndex < slots.count else { return }
                let word = slots[slotIndex].text
                let language = state.language
                onPresentSuggestionMenu?(
                    word,
                    { [weak self] in self?.dontSuggestWord(word, language: language) },
                    { [weak self] in self?.forgetWord(word, language: language) },
                    { [weak self] in self?.onDismissSuggestionMenu?() }
                )
            }
            rootView.toolbarStrip.onTapEmoji = { [weak self] emoji in
                // Plain already-resolved text the user didn't type — the
                // same shape `insertClip` already exists for (task 5.8).
                self?.perform(.insertClip(emoji))
            }
        }

        /// Task 7.7: "a request is sent after every action that changes
        /// text or cursor" — `InputProcessor.handle(_:in:)` already emits
        /// `.requestSuggestions` for exactly those actions; this builds the
        /// actual request from its own `context`/`settings` and applies
        /// whatever comes back, dropping superseded results by generation.
        func requestSuggestions() {
            suggestionGeneration += 1
            let generation = suggestionGeneration
            let typingContext = inputProcessor.context
            let predictionSettings = settings.prediction[state.language]

            guard predictionSettings.enabled, !state.incognito else {
                state.suggestions = nil
                return
            }

            let request = SuggestionRequest(
                generation: generation,
                context: SuggestionContext(
                    prefix: typingContext.prefix,
                    suffix: typingContext.suffix,
                    previousWords: typingContext.previousWords,
                    isSentenceStart: typingContext.isSentenceStart,
                    language: typingContext.language
                ),
                settings: PredictionEngineSettings(
                    enabled: predictionSettings.enabled,
                    suggestionCount: predictionSettings.suggestionCount,
                    showVerbatimSlot: predictionSettings.showVerbatimSlot,
                    preferZWNJForms: predictionSettings.preferZWNJForms,
                    blockOffensive: predictionSettings.blockOffensive,
                    nextWordEnabled: predictionSettings.nextWord,
                    autocorrectEnabled: predictionSettings.autocorrect != .off,
                    autocorrectStrength: predictionSettings.autocorrectStrength,
                    source: Self.sourceMode(for: predictionSettings.source),
                    personalWeight: predictionSettings.personalWeight
                ),
                incognito: state.incognito
            )

            Task { [weak self, suggestionService] in
                var result = await suggestionService.suggest(request)
                guard let self, generation == suggestionGeneration else { return }
                if predictionSettings.emojiSuggestions {
                    result?.emoji = emojiSuggestionWord(typed: typingContext.prefix, previousWords: typingContext.previousWords)
                        .map { emojiSuggester.suggest(forWord: $0, language: state.language.rawValue) } ?? []
                }
                state.suggestions = result
            }
        }

        /// §4.2's narrow-slice conversion (same reasoning as decision 57):
        /// `KelidSettings.PredictionSource` and `PredictionEngine.PredictionSourceMode`
        /// have identical cases, just different types on either side of a
        /// dependency `PredictionEngine` can't have on `KelidSettings`.
        private static func sourceMode(for source: PredictionSource) -> PredictionSourceMode {
            switch source {
            case .off: .off
            case .personalOnly: .personalOnly
            case .languageOnly: .languageOnly
            case .hybrid: .hybrid
            }
        }

        /// §6.7.10: "Shown when the current prefix (a complete word) or the
        /// last committed word matches a keyword" — the typed word takes
        /// priority (it's what the user is looking at right now); falls
        /// back to the most recently committed word only once the prefix is
        /// empty (just after a space/sentence start). `nil` when neither
        /// exists (e.g. the very start of a document).
        private func emojiSuggestionWord(typed: String, previousWords: [String]) -> String? {
            !typed.isEmpty ? typed : previousWords.last
        }

        /// Task 8.4: rebuilds the fuzzy-search adjacency map from the
        /// current layout's real key geometry (`KeyboardLayout.ProximityMap`)
        /// and pushes it to the suggestion service as `PredictionEngine`'s
        /// own narrow `FuzzyProximityMap` (§4.2 — `PredictionEngine` can't
        /// depend on `KeyboardLayout` directly). Called from
        /// `applyGeometry()` on every layout/size-class change, so a stale
        /// map from a previous size or one-handed width never lingers.
        func updateFuzzyProximity(from computed: ComputedLayout) {
            let keyboardProximity = KeyboardLayout.ProximityMap.build(from: computed)
            var adjacency: [Character: Set<Character>] = [:]
            for (key, neighbors) in keyboardProximity.neighbors {
                guard key.count == 1, let keyChar = key.first else { continue }
                adjacency[keyChar] = Set(neighbors.filter { $0.count == 1 }.compactMap(\.first))
            }
            let proximity = FuzzyProximityMap(adjacency: adjacency)
            let language = state.language
            Task { [suggestionService] in
                await suggestionService.updateLayout(proximity, for: language)
            }
        }

        /// Task 8.6: intercepts a separator action (`.space`, `.returnKey`,
        /// or a punctuation `.character(_:)`) when `.auto` autocorrect has a
        /// ready candidate — `requestSuggestions()` already keeps
        /// `state.suggestions?.autocorrect` continuously up to date
        /// (§6.7.9), so no fresh async round-trip is needed at the moment a
        /// separator is tapped. `perform(_:)` calls this before ever handing
        /// the action to `InputProcessor`.
        func autocorrectedAction(for action: InputAction) -> InputAction {
            guard let separator = Self.autocorrectSeparator(for: action),
                  settings.prediction[state.language].autocorrect == .auto,
                  inputProcessor.context.traits.allowsAutocorrect, // rule 1
                  let corrected = state.suggestions?.autocorrect?.text
            else {
                return action
            }
            return .applyAutocorrect(corrected: corrected, separator: separator)
        }

        /// §6.7.9: "Evaluated on a separator (space, punctuation, return)."
        /// `internal` (not `private`): `KeyboardController+Snippets.swift`
        /// (a separate file) calls this too — `private` is file-scoped in
        /// Swift, even across extensions of the same type.
        static func autocorrectSeparator(for action: InputAction) -> String? {
            switch action {
            case .space:
                return " "
            case .returnKey:
                return "\n"
            case let .character(text):
                guard text.count == 1, let char = text.first, isAutocorrectSeparatorCharacter(char) else { return nil }
                return text
            default:
                return nil
            }
        }

        /// A suggestion bar slot was tapped (task 7.8) — round-trips through
        /// `InputAction.insertSuggestion`, same as every other text
        /// operation, so undo/shadow-buffer bookkeeping stay centralized in
        /// `InputProcessor`.
        public func tapSuggestion(_ candidate: SuggestionCandidate, isVerbatim: Bool = false) {
            perform(.insertSuggestion(Suggestion(text: candidate.text, isVerbatim: isVerbatim)))
            state.suggestions = nil
        }

        /// Task 9.5: "Don't suggest '…'" — blocks the word (§6.7.8's
        /// blocklist, applies in every prediction source mode) and confirms
        /// with a toast. Also immediately re-requests suggestions so the
        /// now-blocked word disappears from the bar right away, not just on
        /// the next keystroke.
        func dontSuggestWord(_ word: String, language: LanguageID) {
            Task { [suggestionService] in
                try? await suggestionService.block(surface: word, language: language)
            }
            state.toast = "Won't suggest \"\(word)\" anymore"
            state.suggestions = nil
            requestSuggestions()
        }

        /// Task 9.5: "Forget '…'" — deletes the word's personal data
        /// entirely (§6.7.8).
        func forgetWord(_ word: String, language: LanguageID) {
            Task { [suggestionService] in
                try? await suggestionService.forget(surface: word, language: language)
            }
            state.toast = "Forgot \"\(word)\""
            state.suggestions = nil
            requestSuggestions()
        }

        /// Task 9.8's Quick Settings "Clear my learned words for this
        /// language" — deletes every personal word/n-gram/blocklist entry
        /// for `language`, in memory and in the database.
        public func clearLearnedWords(for language: LanguageID) {
            Task { [suggestionService] in
                try? await suggestionService.clearPersonalData(for: language)
            }
            state.toast = "Cleared your learned words"
            state.suggestions = nil
            requestSuggestions()
        }
    }
#endif
