#if canImport(UIKit)
    import Foundation
    import InputEngine
    import KelidCore
    import KelidSettings
    import KeyboardLayout
    import PredictionEngine
    import UIKit

    /// Prediction (Phase 7) — model loading, building a `SuggestionRequest`
    /// from `InputProcessor`'s own `TypingContext`, and turning a tapped
    /// suggestion bar slot into `.insertSuggestion(_:)` — split out of
    /// `KeyboardController.swift` itself purely to keep that type's body
    /// under SwiftLint's `type_body_length`; behaviorally this is still
    /// part of `KeyboardController`, just declared in a second file.
    extension KeyboardController {
        /// Task 7.6: "loads models in a background Task (utility priority)
        /// after the first frame" — called once from `init`, after `rebuild()`
        /// has already produced the keyboard's first real layout, so this
        /// never delays it.
        func loadPredictionModels() {
            Task(priority: .utility) { [suggestionService] in
                try? await suggestionService.load(languages: LanguageID.allCases, resources: ExtensionModelLocator())
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
                let text = slots[slotIndex].text
                let candidate = (result.items + [result.verbatim].compactMap { $0 }).first { $0.text == text }
                    ?? SuggestionCandidate(text: text)
                tapSuggestion(candidate)
            }
            rootView.toolbarStrip.onLongPressSuggestionSlot = { [weak self] _ in
                // Task 7.8: "long-press shows a placeholder menu (\"Don't
                // suggest\" arrives in Phase 9)" — no real action yet.
                self?.state.toast = "Suggestion options arrive in a future update"
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
                    autocorrectStrength: predictionSettings.autocorrectStrength
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
        private static func autocorrectSeparator(for action: InputAction) -> String? {
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
        public func tapSuggestion(_ candidate: SuggestionCandidate) {
            perform(.insertSuggestion(Suggestion(text: candidate.text)))
            state.suggestions = nil
        }
    }
#endif
