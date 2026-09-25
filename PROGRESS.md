# Kelid — Progress

## Status
| Phase | Title | Status | Date | Notes |
|---|---|---|---|---|
| 0 | Project bootstrap | 🟡 in progress — Simulator fully verified, awaiting your physical-iPhone manual test | 2026-09-25 | See checklist below |
| 1 | Foundation | ☐ | | |
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

## Current phase checklist (Phase 0 acceptance criteria)
- [x] `make gen && make build && make test && make lint` succeed from a fresh clone (after creating `Local.xcconfig`). — fully verified, including `make test-ios`: `xcodebuild -downloadPlatform iOS` was used to install the iOS 27.0 Simulator runtime (this Mac had Xcode but zero Simulator runtimes), a device was created, and `make test` (test-mac + test-ios) passed end-to-end — **TEST SUCCEEDED**, 15/15 tests on `arm64-apple-ios17.0-simulator`.
- [ ] On the Simulator **and** your iPhone: the app installs, and *Kelid* appears under Settings → General → Keyboard → Keyboards → Add New Keyboard. — **not yet verified on-device; this is your manual test, see below.**
- [ ] In Notes: switching to Kelid works, the buttons insert "سلام" / "hello", ⌫ deletes, 🌐 switches keyboards (long-press shows the list) on devices that need it. — **not yet verified on-device.**
- [ ] −20 / +20 visibly changes the keyboard height, with no Auto Layout errors in the console. — **not yet verified on-device.**
- [ ] The status line shows Full Access ✗ → ✓ after enabling it in Settings, and AppGroup read ✓ once Full Access is on. — **not yet verified on-device.**
- [x] `CLAUDE.md`, `PROGRESS.md` and `README.md` exist. Not yet tagged `phase-0` — tag it yourself once the on-device checks above pass (`git tag phase-0`), per the plan's own workflow (§0.2 step 7).

## Handoff notes (newest first)
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

## Measurements
| Date | Device | iOS | Metric | Value | Notes |
|---|---|---|---|---|---|
| 2026-09-25 | — (Simulator build only, generic destination) | — | `make build` | BUILD SUCCEEDED | No device/Simulator memory or latency measurements yet — those need a real device/booted Simulator (Phase 0 doesn't require them; see §6.13 for when they start mattering, Phase 3+). |
| 2026-09-25 | Simulator: iPhone 17 | iOS 27.0 (24A434) | `make test` (test-mac + test-ios) | TEST SUCCEEDED, 15/15 tests | First real `xcodebuild test` run against a booted-capable Simulator device, after installing the iOS Simulator runtime (it wasn't present at all on this Mac). |

## Device findings
(Pasteboard lab results, deletion behavior per host, sound IDs, height-constraint variant, etc.)
- None yet — no on-device testing has happened. First entries expected after your Phase 0 manual test
  (in particular, whether the §6.3.4 priority-999 height constraint works cleanly on your iOS
  version/device, per the note in that section about `rileytestut/Clip`'s alternative).
