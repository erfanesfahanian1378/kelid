# Kelid — Progress

## Status
| Phase | Title | Status | Date | Notes |
|---|---|---|---|---|
| 0 | Project bootstrap | 🟡 implemented, Simulator-verified — awaiting your physical-iPhone manual test | 2026-09-25 | See Phase 0 handoff notes below |
| 1 | Foundation | 🟡 implemented, Simulator-verified — awaiting your physical-iPhone manual test | 2026-09-25 | See checklist below. Built on top of Phase 0 without waiting for your on-device sign-off (you asked to keep going) — if Phase 0's manual test turns up a problem, re-check whether it affects Phase 1's assumptions. |
| 2 | Layout engine and layouts | ☐ | | |
| 3 | Typing surface and input engine | ☐ | | |
| 4 | Resizing and one-handed mode | ☐ | | |
| 5 | Clipboard core and edit tools | ☐ | | |
| 6 | Language data pipeline | ☐ | | |
| 7 | Prediction I | ☐ | | |
| 8 | Prediction II | ☐ | | |
| 9 | Personal learning and modes | ☐ | | |
| 10 | Companion app | ☐ | | |
| 11 | Themes | ☐ | | |
| 12 | Emoji | ☐ | | |
| 13 | Hardening and release | ☐ | | |

## Current phase checklist (Phase 1 acceptance criteria)
- [x] All tests pass on macOS (`make test-mac`) and iOS (`make test-ios`). — verified: 62 tests across 11 KelidKit modules, macOS **and** the iPhone 17 Simulator (iOS 27.0), plus the full app+extension build (`make build` → BUILD SUCCEEDED) and `make lint` (0 serious violations) from a clean `make clean gen build test lint` run.
- [ ] With the keyboard shown in the app's Try-it field, flipping the debug toggle in the app changes the diagnostics line within 1 second. — **not yet verified interactively**; needs tapping through the UI (Simulator or iPhone), which this session can't synthesize. See "How to test" below.
- [ ] With Full Access off, the keyboard still shows and works (local settings); the diagnostics line says so. — **not yet verified interactively.**
- [ ] The app's Home tab shows "Keyboard active, Full Access ✓" after using the keyboard once with Full Access on. — **not yet verified interactively.** (Confirmed the *other* state works: a fresh install with the keyboard never used correctly shows "Not detected" — screenshot-verified.)
- [ ] No `0xDEAD10CC` or other crash after 20 cycles of: show keyboard → home screen → back. — **not yet verified**; needs real interaction cycles.

## Phase 0 checklist — still outstanding
Phase 0's on-device checklist (physical iPhone: keyboard appears in Settings, سلام/hello/⌫, globe key, ±20 height, Full Access status line) was never completed by you — see the Phase 0 handoff notes further down for the full list and steps. Phase 1 was built on top of it anyway at your request; nothing in Phase 1 depends on a specific outcome of that test, but please still work through it.

## Handoff notes (newest first)
### 2026-09-25 — Phase 1 (tasks 1.1–1.9)
- **Done:**
  - `KelidCore`: `AppGroup.identifier` (reads `KelidAppGroupID`); `ContainerPaths.resolve(fullAccess:)`
    (shared App Group container vs. a local per-process fallback built from `NSHomeDirectory()`, with
    injectable lookup/fallback for testing); `DarwinNotifier` (wraps
    `CFNotificationCenterGetDarwinNotifyCenter`, thread-safe, always delivers handlers on main, plus an
    in-process `postInProcess` used by tests and by same-process delivery); `Clock` protocol +
    `SystemClock` + `TestClock`; `MemoryProbe.footprintMB()` (exact §6.13 code); `Signposts` (`os_signpost`
    wrappers sharing `Log`'s subsystem). `LanguageID` also added here (needed by `KelidSettings`, not
    listed as its own task but required by several §6.1 groups).
  - `KelidSettings`: the **entire** `KeyboardSettings` catalog from §6.1 (general, size, toolbar,
    prediction ×2 languages, learning, clipboard, appearance, emoji, snippets, advanced) — every default,
    range and option from the spec tables, each with its own tolerant `init(from decoder:)` (§6.1.1) and
    `clamped()`. `SizeProfile` and per-language `PredictionSettings` are *not* directly `Decodable`
    (portrait/landscape and fa/en need different defaults for the same fields, which the §6.1.1 template's
    `Self()`-based default can't express) — they expose a `decode(from:default:)` static function that
    `SizeSettings`/`PredictionLanguageSettings` call with the right default for each side. `SettingsStore`
    (`@Observable @MainActor`): `load()` (shared-vs-local, newer `updatedAt` wins), `update(_:)`
    (stamp/clamp/save/broadcast), self-reload on `.settings.changed`, `sizeProfile(for:)`,
    `resolvedPrediction(for:)`.
  - `InputEngine`: `TextDocument` protocol (`@MainActor`) and `FieldTraits` (UIKit-free mirrors of
    `UIKeyboardType`/`UIReturnKeyType`/`UITextAutocapitalizationType`/`UITextAutocorrectionType`/
    `UITextSpellCheckingType`/`UIKeyboardAppearance`, `textContentType` kept as a raw `String?`).
    `MockTextDocument` lives in `Tests/InputEngineTests/` (the plan allows either that or a separate
    support target) with all four host-imitation switches from §6.4.8: context limit
    (unlimited/characters(n)/currentParagraphOnly), nil context, delayed context
    (`contextDelay`/`settleContext()`), and per-scalar vs. per-grapheme deletion — the combining-mark test
    (`"a" + U+0301`) confirms scalar mode leaves the bare "a" behind while grapheme mode deletes the whole
    "á" in one call.
  - `KelidStorage`: `DatabaseManager` (an `actor`, so every method is naturally async) implementing
    §6.11.2 exactly — coordinated open via `NSFileCoordinator(.forMerging)`, persistent WAL
    (`SQLITE_FCNTL_PERSIST_WAL`), `busyMode = .timeout(2)`, `observesSuspensionNotifications = true`,
    `suspend()`/`resume()` posting GRDB's own `Database.suspendNotification`/`resumeNotification`, a
    `v0_meta` migration, and read-only fallback via `migrator.hasBeenSuperseded(_:)` (§6.11.4). Added a
    `state` property (`.unavailable`/`.open`/`.suspended`) beyond what task 1.5 lists, for task 1.8's
    diagnostics line.
  - Keyboard target: `ProxyTextDocument` (wraps `UITextDocumentProxy`, full trait mapping both ways) and
    `KeyboardServices` (process-level singleton: `SettingsStore`, lazy `DatabaseManager`, `hasFullAccess`,
    heartbeat write, `isAppGroupReadable`). `KeyboardViewController` rewritten for lifecycle wiring (task
    1.6): `viewWillAppear`/return-from-background open+resume the DB, reload settings, refresh
    `hasFullAccess`, write the heartbeat; `viewDidDisappear`/entering background suspend the DB;
    `NSNotification.Name.NSExtensionHostDidEnterBackground`/`.NSExtensionHostWillEnterForeground` observed
    for the background/foreground pair Apple's docs describe separately from the UIKit lifecycle calls;
    `textDidChange` refreshes the diagnostics line. The سلام/hello/⌫ buttons now route through
    `currentDocument: TextDocument` (a fresh `ProxyTextDocument` per access) instead of touching
    `textDocumentProxy` directly, dog-fooding rule 5.1.5. Diagnostics line (task 1.8) shows Full Access,
    App Group readable, DB state, memory MB, settings `updatedAt`, and `keyPopups` (so the live-sync test
    has something to watch).
  - App: Home tab gained a "Keyboard status" card (§6.10's three states — active / Full Access off? / not
    detected — read from `kb.heartbeat`/`kb.hasFullAccess`, refreshed every 2s while the view is visible)
    and a temporary "Key popups" debug `Toggle` (task 1.9) bound straight to
    `settingsStore.settings.general.keyPopups` through `SettingsStore.update`.
  - Full verification: `make clean gen build test lint` all green from scratch — 62 tests total across 11
    KelidKit modules, on **both** macOS and the iPhone 17 Simulator (iOS 27.0); app+extension build
    succeeds; `make lint` exits 0 (0 serious violations). Also installed+launched the rebuilt app on the
    Simulator again and screenshotted it: no crash, and the new "Keyboard status" card correctly reads
    "Not detected" on a fresh install (the only state easily verifiable without synthesizing taps).

- **Not done / known issues:**
  - **All of Phase 1's interactive acceptance criteria are unverified** (live-sync timing, Full-Access-off
    behavior, the "Keyboard active" heartbeat state, the 20-cycle crash test) — see the checklist above and
    "How to test" below. Same root cause as Phase 0: this session can't synthesize taps.
  - **Phase 0's on-device checklist is still outstanding too** — you asked to keep going before doing it,
    so Phase 1 was built without that checkpoint. Nothing here depends on a particular Phase-0 outcome, but
    please still work through both.
  - Two GRDB-specific quirks worth knowing if you touch `DatabaseManager` tests: (1) suspend/resume
    notifications were observed to **not** be scoped to the specific `DatabasePool` passed as `object:` —
    concurrently-running tests suspending/resuming different pools interfered with each other, so
    `DatabaseManagerTests` is `@Suite(..., .serialized)`; (2) `DatabaseMigrator.hasBeenSuperseded(_:)`
    takes a `Database`, not a `DatabasePool` — call it inside `pool.read { db in ... }`.

- **How to test (your turn):**
  1. Same setup as Phase 0 (real `Local.xcconfig`, install on your iPhone or use the already-booted
     Simulator).
  2. Open the Kelid app, then switch to Kelid in the "Try it" field (enable it in Settings first if you
     haven't). Confirm the diagnostics line under the typing buttons shows something like `FullAccess ✓ ·
     AppGroup ✓ · DB open · mem N MB` on one line and `settings@HH:mm:ss · keyPopups on/off · iOS …` on
     the next.
  3. Go back to the Kelid app (keep the keyboard's host field/app open in the background if your test
     setup allows switching without dismissing the keyboard — e.g. Slide Over / Split View on iPad, or
     just switch apps and back on iPhone) and flip **Key popups** in the new debug section. Switch back to
     the keyboard within a second or two and confirm `keyPopups` in the diagnostics line flipped too.
  4. On the Home tab, confirm the new "Keyboard status" card now reads **"Keyboard active, Full Access
     ✓"** (it should, since you just used the keyboard with Full Access on).
  5. Turn **off** Full Access for Kelid in Settings, then switch to it again in a text field — it should
     still show and let you type (سلام/hello/⌫ still work), and the diagnostics line should show
     `FullAccess ✗`.
  6. Cycle show-keyboard → home screen → back to the text field about 20 times; confirm no crash and the
     keyboard doesn't silently get replaced by the system one (a Jetsam kill would look like that — check
     Console.app for `KelidKeyboard…`/`JetsamEvent…` if it happens).
  7. If everything passes: tick the boxes above (and Phase 0's, if you also did those), commit, and
     `git tag phase-1` (and `phase-0` if not already tagged).

- **Next step:** once verified, start **Phase 2 — Layout engine and layouts** (§0.3 row 2: read §4.2, §5,
  §6.2, §6.3 plus the Phase 2 section) using the standard phase prompt from PLAN.md §0.5.

### 2026-09-25 — Phase 0 (tasks 0.1–0.12)
- **Done:**
  - Repo initialized (`git init`, `git lfs install`), `.gitignore` / `.gitattributes` per spec.
  - `Config/Base.xcconfig`, `Config/Local.xcconfig.example` (and a local `Config/Local.xcconfig` with the
    placeholder `com.example` prefix, gitignored, created so this environment could build/test — replace
    it with your own prefix and Team ID before installing on your iPhone).
  - `project.yml` (XcodeGen) generates `Kelid.xcodeproj` cleanly with 2.46.0; both app and keyboard-extension
    targets build for the iOS Simulator (`xcodebuild -scheme Kelid -destination 'generic/platform=iOS
    Simulator' build` → **BUILD SUCCEEDED**). No XcodeGen key renames were needed.
  - `Packages/KelidKit/Package.swift`: all 11 modules from PLAN.md §4.2 (KelidCore, KelidSettings,
    PersianText, KeyboardLayout, InputEngine, PredictionEngine, KelidStorage, ClipboardKit, ThemeKit,
    EmojiData, KeyboardUI), each with one public placeholder type and one passing test (15 tests total,
    all green via `swift test`). Dependencies wired: GRDB 7.x, swift-collections 1.x, swift-snapshot-testing
    (test only, KeyboardUITests). `KeyboardLayout`/`ThemeKit` ship placeholder resource folders
    (`Layouts/.keep`, `BuiltInThemes/.keep`); `EmojiData` ships `emoji.json` = `[]`. All three resources
    load correctly at runtime (tested). `KeyboardUI` uses `.defaultIsolation(MainActor.self)` and guards
    its `import UIKit` with `#if canImport(UIKit)` so `swift test` still builds on macOS.
  - `Tools/klm` package (separate from KelidKit, macOS-only): `klm --version` works and links
    `PredictionEngine`/`PersianText` from KelidKit.
  - `Keyboard/KeyboardViewController.swift`: status line (Full Access / AppGroup read / iOS version),
    سلام / hello / ⌫ buttons via `textDocumentProxy`, a 🌐 globe button wired to
    `handleInputModeList(from:with:)`, and −20/+20 height buttons using the §6.3.4 mechanism (priority-999
    constraint + `allowsSelfSizing`, starting at 260 pt).
  - `App/KelidApp.swift`: a one-tab `TabView` with setup steps, an "Open Settings" button, a "Try it"
    `TextEditor`, and an `app.probe` timestamp written to the shared App Group `UserDefaults` on launch.
  - `Makefile` (gen/build/test/test-mac/test-ios/lint/format/klm/data-quick/data-full/clean),
    `Tools/scripts/lint-no-network.sh`, `.swiftformat`, `.swiftlint.yml`.
  - `KelidCore/Log.swift`: `os.Logger` helper with one category per module, subsystem configured from
    `Bundle.main.bundleIdentifier` with `.keyboard`/`.share` suffix stripping so every process logs under
    one subsystem.
  - `CLAUDE.md` (Appendix A, filled in), `README.md` (prerequisites, setup, signing notes, enabling the
    keyboard, debugging).
  - Ran `swiftformat .` once to normalize all new files to the checked-in `.swiftformat` config; re-verified
    build + tests afterward (still green).
  - Full clean-state verification: `make clean gen build test-mac lint` all pass. `make klm` builds and
    `klm --version` runs.
  - **iOS Simulator runtime installed** (this Mac had Xcode 27 but no Simulator runtime at all — a
    one-time ~8 GB download): `xcodebuild -downloadPlatform iOS`, then `xcrun simctl create "iPhone 17"
    com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0` (a
    duplicate "iPhone 17" that Xcode auto-seeded once the runtime landed was deleted). `make test-ios` and
    the combined `make test` now both pass — **TEST SUCCEEDED**, all 15 tests on
    `arm64-apple-ios17.0-simulator`.
  - **Installed and launched the app on that Simulator** (`xcrun simctl install` / `launch`): it starts
    without crashing, `com.example.kelid`'s process stays alive, and `listapps` confirms the App Group
    (`group.com.example.kelid`) container was created. A screenshot confirms the UI renders exactly as
    coded — the three setup steps, "Open Settings", and the empty "Try it" field. Full interactive
    testing (adding the keyboard in Settings, typing, Full Access toggle, ±20 height) needs touch input
    this session can't synthesize — that's the manual step below, which you can now do **either in this
    already-booted Simulator or on your iPhone** (Simulator is faster to iterate on; iPhone is still
    required before calling the phase fully done, since the memory limit and real clipboard/haptics
    behavior only apply on-device — see §5.4).

- **Not done / known issues:**
  - **On-device (physical iPhone) manual test not performed** (see below) — I have no physical iPhone to
    install onto from this session. This is the human step the plan's own workflow (§0.2 step 6) expects
    you to do. (The Simulator side is now fully working — see below — but §6.13-class memory/haptics/
    clipboard behavior still needs a real device per §5.4.)
  - `Config/Local.xcconfig` in your checkout currently has the placeholder prefix `com.example` (needed
    to get a build working here). Replace `KELID_BUNDLE_PREFIX` with something like `com.yourname` and
    `KELID_TEAM_ID` with your real Apple Developer Team ID before installing on your iPhone — see
    README.md.
  - SwiftLint reports 15 `trailing_comma` warnings (0 errors) in `Package.swift` files and a couple of
    other spots, caused by SwiftFormat's default style (multi-line trailing commas) conflicting with
    SwiftLint's default `trailing_comma` rule (which wants none). Cosmetic only, `make lint` still exits
    0; left as-is since PLAN.md's task 0.9 only specified the `line_length` and `force_unwrapping` rules
    for `.swiftlint.yml`. Revisit if it gets noisy.

- **How to test (your turn):** the Simulator this session set up is already booted with the app
  installed (`com.example.kelid`, the placeholder-prefix build), so you can try steps 3–7 below in the
  Simulator right now for a fast check — but still repeat the whole thing on your **physical iPhone**
  before considering Phase 0 done, since the memory limit, haptics, sounds and real clipboard behavior
  only apply on-device (§5.4).
  1. `cp Config/Local.xcconfig.example Config/Local.xcconfig`, then edit it with your own bundle prefix
     and Team ID (see README.md). This **replaces** the placeholder one created for this session.
  2. `make gen && open Kelid.xcodeproj`, select your iPhone as the run destination, build & run the
     `Kelid` scheme (installs both the app and the keyboard extension).
  3. Settings → General → Keyboard → Keyboards → Add New Keyboard… → Kelid. Tap Kelid → turn on
     **Allow Full Access**.
  4. Open Notes (or Safari's address bar, or Messages), switch to Kelid with the globe key (long-press
     it if more than one third-party keyboard is installed, to confirm the switcher list appears).
  5. Tap **سلام** and **hello** — confirm both insert correctly (RTL/LTR mixing okay). Tap **⌫** —
     confirms it deletes.
  6. Tap **+20** a few times, then **−20** — confirm the keyboard visibly grows/shrinks with no jump or
     console Auto Layout warnings (watch via Xcode's console while attached — see README.md "Debugging").
  7. Check the status line: with Full Access off it should read `FullAccess ✗`; after turning Full
     Access on (step 3) and reopening the keyboard, it should read `FullAccess ✓` and
     `AppGroup read ✓` (the app writes `app.probe` on every launch, so open the Kelid app at least once
     first).
  8. If everything above passes: tick the boxes in the checklist above, `git add -A && git commit`, then
     `git tag phase-0`.
  9. If something fails: use the **Fix prompt** from PLAN.md §0.5, e.g. "Phase 0 manual test failed:
     the −20/+20 buttons don't resize the keyboard on iOS 17.4, iPhone 13. …".

- **Next step:** once the on-device checklist above is ticked and tagged `phase-0`, start a fresh AI
  session for **Phase 1 — Foundation** (`/clear` in Claude Code), using the standard phase prompt from
  PLAN.md §0.5.

## Decision log
| # | Date | Decision | Why | Affects |
|---|---|---|---|---|
| 1 | 2026-09-25 | Added `{ package: KelidKit, product: KelidCore }` as an explicit dependency of both the `Kelid` and `KelidKeyboard` targets in `project.yml`, in addition to what task 0.3's literal snippet lists (`KeyboardUI`, `KelidStorage` for the app; `KeyboardUI` for the extension). | Both `App/KelidApp.swift` and `Keyboard/KeyboardViewController.swift` need `Log` (task 0.10) directly, not just through a module that happens to depend on `KelidCore` transitively. Relying on a transitive, undeclared import would be fragile and contrary to rule 5.1.11 (dependencies should be explicit). | `project.yml`, App target, KelidKeyboard target |
| 2 | 2026-09-25 | Ran `swiftformat .` once, immediately after scaffolding all Phase 0 files, and treated its output as the checked-in state rather than hand-formatting to match `.swiftformat`. | Faster and more reliable than manually matching SwiftFormat's exact style (indent, doc-comment vs. `//`, MARK spacing, property-body wrapping) by hand; re-verified build + tests were unaffected. | All new Swift files |
| 3 | 2026-09-25 | Installed the iOS 27.0 Simulator runtime (`xcodebuild -downloadPlatform iOS`) and created an "iPhone 17" Simulator device, rather than leaving `make test-ios` unverified. | This machine had Xcode fully installed but no Simulator runtime at all — a one-time, machine-local setup gap rather than a project issue. Installing it let the acceptance criterion "`make test` succeeds" be fully verified instead of only partially (macOS side only). | Local machine state only (not part of the repo); no project files changed |
| 4 | 2026-09-25 | Added `KelidSettings`, `KelidStorage` and `InputEngine` as explicit `project.yml` dependencies of the `KelidKeyboard` target (same rationale as decision 1's `KelidCore`). | `KeyboardViewController`/`KeyboardServices`/`ProxyTextDocument` import all three directly for the Phase 1 lifecycle wiring, settings store and database. | `project.yml`, KelidKeyboard target |
| 5 | 2026-09-25 | `ContainerPaths`'s local-fallback base URL uses `NSHomeDirectory()`, not `FileManager.homeDirectoryForCurrentUser` as first written. | The real iOS build failed: `homeDirectoryForCurrentUser` is unavailable on iOS (macOS/Mac Catalyst only). `NSHomeDirectory()` is the standard iOS-available equivalent for a sandboxed process's own container root. | `Packages/KelidKit/Sources/KelidCore/ContainerPaths.swift` |
| 6 | 2026-09-25 | Used `NSNotification.Name.NSExtensionHostDidEnterBackground` / `.NSExtensionHostWillEnterForeground`, not the bare `NSExtensionHostDidEnterBackgroundNotification` names PLAN.md task 1.6 implies. | The real iOS build's compiler error named the exact renamed Swift symbols; Apple renamed these into `NSNotification.Name` statics in the Swift overlay. | `Keyboard/KeyboardViewController.swift` |
| 7 | 2026-09-25 | `SizeProfile` and per-language `PredictionSettings` are not directly `Decodable` — each exposes a `static func decode(from:default:)` that the parent (`SizeSettings`/`PredictionLanguageSettings`) calls once per side with the right default, instead of the §6.1.1 template's `let d = Self()` pattern. | Portrait/landscape (`rowHeight`, etc.) and fa/en (`personalWeight`, `autocorrect`) have *different* defaults for the *same* field names. A single `Self()`-based tolerant default can only express one set of defaults, so it would silently apply the wrong side's default to whichever nested object decodes first/second incorrectly. This is a structural extension of §6.1.1's pattern, not a deviation from its intent (every field is still individually tolerant-decoded with an explicit default). | `SizeSettings.swift`, `PredictionSettings.swift` |
| 8 | 2026-09-25 | Tuned `.swiftlint.yml`: `identifier_name` `min_length` lowered to 1 with `_` in `allowed_symbols`; `cyclomatic_complexity` warning threshold raised to 15. | SwiftLint's stock defaults made `make lint` fail (exit 2) on things the plan itself specifies or that are standard idiom: §6.1.1's own tolerant-decoding example uses `c`/`d`; GRDB's documented migration API uses `db`/`t`; `ProxyTextDocument`'s UIKit-trait-mapping functions are wide flat switches (12 cases), not genuinely complex logic. `identifier_name`'s `excluded` key turned out unsupported for per-rule scoping in this SwiftLint version, so this is a global (not test-only) relaxation. | `.swiftlint.yml` |
| 9 | 2026-09-25 | `DatabaseManagerTests` is `@Suite("DatabaseManager", .serialized)`. | Empirically, a test that suspended/resumed one `DatabasePool` interfered with a concurrently-running test using a *different* `DatabasePool` (a "Database is suspended" error appeared on an unrelated write) — GRDB's suspend/resume notifications don't appear to be scoped to the `object:` passed when posting, in practice. Serializing this suite fixed it; keep new `DatabaseManager` tests in the same suite (not a new one) unless this gets investigated further. | `Tests/KelidStorageTests/DatabaseManagerTests.swift` |

## Measurements
| Date | Device | iOS | Metric | Value | Notes |
|---|---|---|---|---|---|
| 2026-09-25 | — (Simulator build only, generic destination) | — | `make build` | BUILD SUCCEEDED | No device/Simulator memory or latency measurements yet — those need a real device/booted Simulator (Phase 0 doesn't require them; see §6.13 for when they start mattering, Phase 3+). |
| 2026-09-25 | Simulator: iPhone 17 | iOS 27.0 (24A434) | `make test` (test-mac + test-ios) | TEST SUCCEEDED, 15/15 tests | First real `xcodebuild test` run against a booted-capable Simulator device, after installing the iOS Simulator runtime (it wasn't present at all on this Mac). |
| 2026-09-25 | Simulator: iPhone 17 | iOS 27.0 (24A434) | `make test` (test-mac + test-ios), end of Phase 1 | TEST SUCCEEDED, 62/62 tests | Full KelidKit suite after Phase 1: KelidCore 16, KelidSettings 20, InputEngine 13, KelidStorage 6, plus 2 each for EmojiData/ThemeKit/KeyboardLayout and 1 each for PersianText/ClipboardKit/PredictionEngine/KeyboardUI placeholders. |
| 2026-09-25 | Simulator: iPhone 17 | iOS 27.0 (24A434) | App install + launch (post-Phase-1 rebuild) | No crash; "Keyboard status" card correctly shows "Not detected" | Screenshot-verified. Full interactive flows (heartbeat → "active", live settings sync, Full-Access-off typing) still need real taps — see Phase 1 handoff notes. |

## Device findings
(Pasteboard lab results, deletion behavior per host, sound IDs, height-constraint variant, etc.)
- None yet — no on-device testing has happened. First entries expected after your Phase 0 manual test
  (in particular, whether the §6.3.4 priority-999 height constraint works cleanly on your iOS
  version/device, per the note in that section about `rileytestut/Clip`'s alternative).
