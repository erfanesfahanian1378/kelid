#if canImport(UIKit)
    import InputEngine
    import KelidCore

    /// Task 10.5's text expansion — "a snippet's shortcut followed by space
    /// is replaced by the snippet text" — split out of `KeyboardController.swift`
    /// itself purely to keep that type's body under SwiftLint's
    /// `type_body_length`; behaviorally this is still part of
    /// `KeyboardController`, just declared in a second file.
    extension KeyboardController {
        /// Called once from `init`, and again every time `.snippetsChanged`
        /// fires (another process editing shortcuts, or this controller's
        /// own Snippets panel tab) — keeps `shortcutToSnippetText` from
        /// ever drifting stale for more than one round trip.
        func loadSnippetShortcuts() {
            Task { [snippetRepository] in
                let groups = await (try? snippetRepository.listAllGroupedByFolder()) ?? []
                var mapping: [String: String] = [:]
                for snippet in groups.flatMap(\.snippets) {
                    guard let shortcut = snippet.shortcut else { continue }
                    mapping[shortcut] = snippet.text
                }
                self.shortcutToSnippetText = mapping
            }
        }

        /// Called once from `init` — mirrors `SettingsStore`'s own
        /// `.settings.changed` observation pattern.
        func observeSnippetChanges() {
            snippetsObservationToken = DarwinNotifier.shared.observe(.snippetsChanged) { [weak self] in
                MainActor.assumeIsolated {
                    self?.loadSnippetShortcuts()
                }
            }
        }

        /// §6.7.8-adjacent interception, same shape as `autocorrectedAction(for:)`:
        /// runs *before* it in `perform(_:)`, since a typed shortcut is
        /// never simultaneously a real word autocorrect would touch.
        /// `settings.snippets.expansionEnabled` gates the whole feature.
        func expandedAction(for action: InputAction) -> InputAction {
            guard settings.snippets.expansionEnabled,
                  let separator = Self.autocorrectSeparator(for: action),
                  let snippetText = shortcutToSnippetText[inputProcessor.context.prefix]
            else {
                return action
            }
            return .expandSnippet(text: snippetText, separator: separator)
        }
    }
#endif
