# Kelid — handoff for the next session

Updated 2026-09-27, end of a follow-up session that had **real Xcode/Simulator
access** (screenshots, real taps via a device-interaction subagent, and
`xcrun simctl spawn <UDID> log show` for the keyboard extension's own unified
log — the previous session had none of this and had to guess from source
alone). That previous session's handoff is superseded by this one; its
technical detail lives on in `PROGRESS.md`'s decision log (entries 94–106)
and "Device findings" section, which this file summarizes and updates.

**Read `CLAUDE.md` and `PROGRESS.md` first** (decisions 94–106 and the two
"Device findings" dated entries at the very bottom cover everything below in
full technical detail).

## Where the project stands

All of Phases 0–11 (§8 in `PLAN.md`) are implemented, unit-tested, and pass a
real `make build`/`make test`/`make lint` as of the last commit on `main`.
Phase 12 (emoji panel) and Phase 13 (hardening/release) haven't been started.

## Fixed this session: the word-prediction bug (previous session's top priority)

**Root-caused and fixed, with real device confirmation** — see decision 106
in `PROGRESS.md` for the full mechanism. Summary: `Lexicon.bestCompletions`
(the best-first heap search `fuzzyMatches` uses) had no cap on total heap
pops and no periodic truncation of its `collected` results array — both
safeguards its sibling `completions(prefixKey:)` already had. When many trie
nodes tie on the same quantized `maxScore` (common with a short 1-character
typed prefix, which leaves nearly every first letter simultaneously "within
budget"), the search degraded to a near-exhaustive, quadratic-cost walk of
the whole subtree. Measured on a real Simulator: `fuzzyMatches("h", …)`
against the real 120,000-word `en.klm` took **75+ seconds** before the fix.
Since `SuggestionService` is an actor, that one stuck call blocked every
later keystroke's suggestion request too — which is why suggestions never
appeared no matter how long someone typed or waited.

**Fix**: `Lexicon.bestCompletions` now caps total heap pops at a
`visitBudget` of 2000 and periodically truncates `collected` past
`limit * 4` entries, mirroring `completions(prefixKey:)`'s own existing
mitigation exactly. After the fix, the same call completes in ~16 ms, and
real suggestions ("Hell"/"Hello"/"Help" for a typed "Hell") appeared in the
Simulator's suggestion strip within milliseconds of each keystroke — verified
both visually (screenshots) and via unified-log timestamps.
`make build`/`make test`/`make lint` are all green afterward (one
intermittent, unrelated `UserModelTests` flake did not reproduce on re-run —
pre-existing test-parallelism flakiness, same class as decision 9/70, not a
regression from this fix).

No debug code was left behind: temporary diagnostic logging added mid-session
to trace the hang was fully removed once the root cause was confirmed. The
task 3.18 debug overlay (`pred fa✓/✗ en✓/✗`) is real, permanent instrumentation
and was left in place.

## Process notes for whoever has real Xcode/Simulator access next

- `mcp__xcode-tools__GetConsoleOutput` only surfaces the tracked **app**
  process's console output (the main `Kelid` app), not the keyboard
  extension's own separate process (a different PID, shown only as an opaque
  `RemotePlaceholder` in the accessibility hierarchy since cross-process AX
  access is disabled in the Simulator). To see the keyboard extension's own
  logs, use `xcrun simctl spawn <device-UDID> log show --predicate '...'`
  directly via the shell instead.
- `os.Logger`'s `.debug` level is **not** persisted to the unified log store
  by default — only `.default`/`.info`/`.error`/`.fault` reliably show up in
  `log show` without extra profile-based configuration. Use `.error` (or
  similar) for any *temporary* diagnostic logging you need to retrieve this
  way, and remove it once the real bug is found.
- `DeviceInteractionStartWorkspaceSession`'s session key seems to expire
  fairly quickly (a few minutes) between tool calls if you're doing other
  work (e.g. reading/editing source) in between interaction steps — if
  `DeviceInteractionInstallAndRun`/`DeviceInteractionSynthesize` return
  "Session with that key doesn't exist," just start a new session with a new
  key; no real state is lost.
- Actual device interaction (tapping keys, reading the screen) must be done
  by a subagent loading the `device-interaction` skill — brief it with the
  exact on-screen labels/paths (tab names, button labels, field names) rather
  than vague instructions, since it starts with no context of its own.

## Known real gaps (not bugs, just not done)

- Only the Home tab got the Liquid Glass redesign — Settings/Clipboard/Dictionary
  tabs are still plain `Form`/`List`, per user request for consistency.
- `make data-full` (the real Wikipedia-scale language data pipeline) has never
  been run — the committed `.klm` files are quick-path/unigram-scale only.
  (Note: this is unrelated to the bug fixed this session — that was a pure
  algorithmic bug in fuzzy search, not a data-scale issue.)
- Phase 12 (emoji panel) and Phase 13 (hardening) haven't been started.
- Everything in Phases 0–11 still needs a real *physical device* pass at some
  point (haptics, real sound, real memory limits — the Simulator doesn't
  enforce the keyboard extension's real ~48–60MB memory ceiling).
- The unchecked acceptance-criteria boxes near the top of `PROGRESS.md`
  (theme photo-background memory cost, host-app `keyboardAppearance`
  following, theme export/import round-trip on a second device, Vazirmatn
  rendering, snippet expansion on-device, Share Extension from Safari/Photos,
  Shortcut+Back-Tap flow, backup/restore round-trip, RTL/localization) are
  all still open — now that real Simulator access exists, these are good
  candidates for the next real interactive pass, in roughly that priority
  order (theme/appearance first, since those are the most visible).

## Working directory

`/Users/erfanesfahanian/Downloads/iphone keyboard` — `make gen` regenerates
`Kelid.xcodeproj` from `project.yml` (needed after adding new source files or
changing `project.yml`; not needed for edits to existing files). `make build`
builds all three targets (`Kelid`, `KelidKeyboard`, `KelidShare`) for the
Simulator from the CLI. `make test` runs the full suite (`swift test` + the
iOS-only `xcodebuild test` suite). All green as of this session's commit.
