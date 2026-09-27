# Kelid — handoff for the next session (Xcode-connected)

Written 2026-09-27, end of a long CLI-only session. This session could build via
`xcodebuild`/`swift test` but had **no way to run the app in the Simulator, tap
anything, or see live rendering** — every UI check depended on the user manually
screenshotting the Simulator and pasting Console.app crash logs back. That's the
reason this handoff exists: whoever picks this up next (with real Xcode/Simulator
access) can verify things directly instead of relying on a screenshot relay.

**Read `CLAUDE.md` and `PROGRESS.md` first** (PROGRESS.md's Decision log entries
94–105 and its "Device findings" section at the very bottom cover everything
described here in full technical detail — this file is a shorter, action-oriented
summary of the same material, not a replacement for it).

## Where the project stands

All of Phases 0–11 (§8 in `PLAN.md`) are implemented, unit-tested, and pass a real
`xcodebuild build` + `xcodebuild test` as of the last commit on `main`. Phase 12
(emoji panel) and Phase 13 (hardening/release) haven't been started.

**None of Phases 0–11 have had a real successful interactive on-device pass.**
Tonight was the first real attempt, on the Simulator, and it surfaced several
genuine bugs that had never been caught before (nothing in this project had ever
actually been *run and tapped on* until tonight). Those are fixed now (see below).
One thing — word prediction — is still unresolved and is the actual priority.

## Fixed tonight (all pushed to `main`, in order)

1. **A real crash, twice** (commits `0bb7cb4`, `5ea7670`) — `KeyboardViewController.refreshSupplementaryLexiconIfNeeded`'s
   `requestSupplementaryLexicon` completion touched main-actor state from a
   background queue UIKit actually delivers it on, and the whole keyboard
   extension process died the moment it fired (which is on every fresh
   install). This was almost certainly why the keyboard kept "disappearing"/
   "glitching" earlier tonight — and see the prediction section below, because
   this crash used to interrupt the language-model load essentially every time,
   which may be the actual explanation for tonight's still-open prediction bug.
2. **A real layout bug** (commit `fc88b03`) — the English QWERTY page's number
   row was showing Persian digits, because digit-script selection ignored which
   language's layout was actually being composed.
3. **A real theme-selection bug** (commit `ea28f69`) — tapping a theme in the
   app's Themes gallery only updated *half* of a light/dark theme pair
   (`AppearanceSettings.lightThemeID`/`darkThemeID`), never touching
   `themeMode` itself. Since the app defaults to "follow the host app's
   light/dark state," tapping a theme very often changed a slot the keyboard
   wasn't even resolving to, so nothing visibly happened. Now tapping a theme
   card always switches to `.fixed` mode with that exact theme — unambiguous.
4. **A real toolbar bug** (commit `7fbc363`) — a new "save clipboard now"
   button (added tonight, see below) was never added to the code that hides
   icons when suggestions are showing, so it sat on top of part of the
   suggestion bar whenever real suggestions appeared.
5. Two real UX gaps, fixed by request: automatic clipboard capture cannot work
   on iOS (background pasteboard reads are silently blocked by the OS unless
   tied to a direct tap — this is a platform limitation, not a bug) — added a
   dedicated "save clipboard now" toolbar button instead (commit `fc88b03`).
6. The app's own UI (not the keyboard) was redesigned with a real Liquid Glass
   look (`glassEffect`/`.ultraThinMaterial`, commit `fd8bc4c`) on the Home tab
   only — other app tabs (Settings, Clipboard, Dictionary) still use plain
   `Form`/`List` and would need the same treatment for full consistency.
7. The keyboard's own default theme was changed from the plain "Light" theme
   to "Glass" (commit `8ba38b2`), and Glass's corner radius/shadow were made
   more rounded/soft (commit `a9e48de`) after direct feedback that the
   default still looked "outdated."

## Not fixed — the actual priority: word prediction

**Symptom:** typing a real, common word prefix ("hell") in the Try-it box
produces zero suggestions in the toolbar's suggestion bar — the toolbar just
shows the icon row instead, as if no suggestions were computed at all.

**What's been ruled out from source alone** (i.e., don't re-derive these,
they're confirmed):

- The real, committed `.klm` language files are not corrupt and are not the
  problem — `swift test --filter SuggestionBenchmarkTests` (macOS, this same
  session) loads the *exact* committed `fa.klm` and produces real completions
  in well under a millisecond per call.
- The `.klm` files are genuinely present in the built extension bundle at the
  path `ExtensionModelLocator` looks for them (`Kelid.app/PlugIns/KelidKeyboard.appex/{en,fa}.klm`,
  confirmed via `find` on the actual `DerivedData` build output).
- `PredictionSettings.enabled` defaults to `true`, `source` defaults to
  `.hybrid` — predictions should be on by default with no user action needed.
- The toolbar's suggestion-vs-icon-row switch itself works correctly in code
  (`ToolbarStripView.applySuggestions`) — bug #4 above (the button overlapping
  suggestions) was found and fixed, but that bug alone wouldn't make
  suggestions compute to *zero*, only look partially obscured if they existed.

**What's genuinely unknown, and needs a real device/Simulator to answer:**
`SuggestionService.load(languages:resources:)` silently `continue`s past any
language whose `ModelLocator.url(for:)` returns `nil` — **no thrown error, no
log, nothing visible** if a language quietly fails to resolve or parse its
`.klm` at real runtime (as opposed to the isolated test above, which never
exercises the real `ExtensionModelLocator`/`Bundle.main` path inside an actual
running extension process). This is the leading theory.

**Diagnostic already added and pushed** (commit `a60b062`), not yet checked by
anyone with real Simulator access: `SuggestionService.loadedLanguages` (a new
public property) is now shown in the keyboard's own debug overlay. To check it:

1. In the Kelid app: **Settings → Advanced → Debug overlay** → turn it on.
2. Show the keyboard (e.g. the Home tab's "Try it" box).
3. Look at the thin black strip at the very top edge of the keyboard. It now
   includes a `pred en✓/✗ fa✓/✗` segment.
4. **If it says `en✗`** (or `fa✗`): the English (or Persian) model silently
   failed to load — that's the real bug, and the next step is adding real
   logging (`Log.logger(...)`) around `KLMFile.init(path:)`'s throw sites in
   `SuggestionService.load`, or just removing the `try?` around
   `loadPredictionModels()`'s call in `KeyboardController.swift` temporarily
   to let the real error surface (currently swallowed silently — see
   `Packages/KelidKit/Sources/KeyboardUI/KeyboardController+Suggestions.swift`,
   `loadPredictionModels()`).
5. **If it says `en✓ fa✓`**: the models loaded fine, and the bug is somewhere
   in `requestSuggestions()`'s request-building or `SuggestionService.suggest(_:)`'s
   ranking — in that case, check `state.incognito` isn't stuck `true`, check
   what `LanguageID` is actually active when typing English (`state.language`),
   and consider temporarily logging the actual `SuggestionRequest`/`SuggestionResult`
   in `KeyboardController+Suggestions.swift`'s `requestSuggestions()` to see
   what's actually being asked for and returned.

Either way, **do not re-investigate the things already ruled out above** — go
straight to whichever branch the debug overlay's `pred` indicator points to.

## Known real gaps (not bugs, just not done)

- Only the Home tab got the Liquid Glass redesign — Settings/Clipboard/Dictionary
  tabs are still plain `Form`/`List`, per user request for consistency.
- `make data-full` (the real Wikipedia-scale language data pipeline) has never
  been run — the committed `.klm` files are quick-path/unigram-scale only.
- Phase 12 (emoji panel) and Phase 13 (hardening) haven't been started.
- Everything in Phases 0–11 still needs a real *physical device* pass at some
  point (haptics, real sound, real memory limits — the Simulator doesn't
  enforce the keyboard extension's real ~48–60MB memory ceiling).

## Working directory

`/Users/erfanesfahanian/Downloads/iphone keyboard` — `make gen` regenerates
`Kelid.xcodeproj` from `project.yml` (needed after adding new source files or
changing `project.yml`; not needed for edits to existing files). `make build`
builds all three targets (`Kelid`, `KelidKeyboard`, `KelidShare`) for the
Simulator from the CLI. `make test` runs the full suite (`swift test` + the
iOS-only `xcodebuild test` suite). All green as of commit `a60b062`.
