#if canImport(UIKit)
    import Foundation
    import InputEngine
    import KelidCore
    import KelidSettings
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
                    blockOffensive: predictionSettings.blockOffensive
                ),
                incognito: state.incognito
            )

            Task { [weak self, suggestionService] in
                let result = await suggestionService.suggest(request)
                guard let self, generation == suggestionGeneration else { return }
                state.suggestions = result
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
