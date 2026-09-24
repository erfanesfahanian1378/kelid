# Kelid (کلید) — Custom iPhone Keyboard · Master Plan

> **Working name:** "Kelid" (Persian for *key*). Rename it any time: the name lives in `Config/Local.xcconfig` and in a few display strings.
> **Plan version:** 1.0 · 2026-09-24 · **Target:** iOS 17+ (iPhone first) · **Languages:** Persian (فارسی) + English
> **Top priorities:** ① Clipboard manager ② Resizing ③ Persian word prediction + personal learning ④ Themes & options

This file is the **single source of truth** for building the keyboard. It has two readers:

1. **You (the project owner):** to see what will be built, in what order, and what to test on your iPhone after each phase.
2. **The AI coding assistant** (Claude Code or similar): to build **one phase per session** without needing any earlier chat history.

---

## Table of contents

- [0. How to use this plan](#0-how-to-use-this-plan)
- [1. Product vision](#1-product-vision)
- [2. iOS keyboard platform facts and hard constraints](#2-ios-keyboard-platform-facts-and-hard-constraints)
- [3. Key decisions](#3-key-decisions)
- [4. Architecture](#4-architecture)
- [5. Engineering conventions](#5-engineering-conventions)
- [6. Specifications](#6-specifications)
  - [6.1 Settings catalog](#61-settings-catalog)
  - [6.2 Layouts](#62-layouts)
  - [6.3 Geometry and resizing](#63-geometry-and-resizing)
  - [6.4 Input behavior](#64-input-behavior)
  - [6.5 Clipboard](#65-clipboard)
  - [6.6 Persian text processing](#66-persian-text-processing)
  - [6.7 Prediction and learning](#67-prediction-and-learning)
  - [6.8 Themes, fonts, sounds, haptics](#68-themes-fonts-sounds-haptics)
  - [6.9 Emoji](#69-emoji)
  - [6.10 Companion app](#610-companion-app)
  - [6.11 Storage](#611-storage)
  - [6.12 Privacy and security](#612-privacy-and-security)
  - [6.13 Performance and memory budgets](#613-performance-and-memory-budgets)
- [7. Libraries, data and reference code](#7-libraries-data-and-reference-code)
- [8. Phases](#8-phases)
- [9. QA matrix](#9-qa-matrix)
- [10. Risks and mitigations](#10-risks-and-mitigations)
- [Appendix A — CLAUDE.md](#appendix-a--claudemd-created-in-phase-0)
- [Appendix B — PROGRESS.md template](#appendix-b--progressmd-template)
- [Appendix C — Glossary](#appendix-c--glossary)
- [Appendix D — Links](#appendix-d--links)

---

## 0. How to use this plan

### 0.1 What you need

- **A Mac** with the latest stable **Xcode** (26 or newer) and its Command Line Tools.
- **An iPhone on iOS 17+**. The Simulator is fine for most work, but **memory limits, haptics, sounds and real clipboard behavior must be tested on the phone**.
- **An Apple ID.**
  - *Free account:* enough to build and run on your own iPhone. App Groups work on free accounts (Apple's capability table lists them for all membership types). Installs expire after **7 days**, so you re-run from Xcode.
  - *Paid Apple Developer Program ($99/year):* needed for TestFlight, the App Store, and installs that don't expire every week. Availability of the paid program depends on your country.
- **Homebrew tools:** `brew install xcodegen swiftformat swiftlint git-lfs`
- **Python 3.11+** (with `uv` or `venv`), used only by the language-data pipeline (Phase 6).
- **~30 GB free disk** for Wikipedia dumps and n-gram counting (Phase 6).

### 0.2 Workflow: one phase per AI session

1. Before Phase 0, fill in the decisions in **§0.4**.
2. Start a **fresh AI session for every phase** (in Claude Code: `/clear`), then paste the prompt from **§0.5**.
3. The AI reads `CLAUDE.md` → `PROGRESS.md` → **only** the PLAN.md sections listed for that phase in the **Context map (§0.3)** → the phase section itself.
4. The AI implements the tasks in order, running build + tests after each task.
5. The AI updates `PROGRESS.md` (checklist, handoff notes, decision log) and commits.
6. **You** run the phase's *Manual test* on your iPhone. Report problems in the same session, or open a "fix" session (§0.5).
7. When everything passes: `git tag phase-N`.

Phases marked **Size L** list split points ("Session A / Session B"). Don't start a phase until the previous phase's acceptance criteria pass.

### 0.3 Context map

Tell the AI to read only these sections (plus `CLAUDE.md`, `PROGRESS.md` and the phase itself). This keeps each session's context small.

| Phase | Title | Read these sections |
|---|---|---|
| 0 | Project bootstrap | §0, §2, §3, §4, §5, Appendix A, Appendix B |
| 1 | Foundation | §3, §4, §5, §6.1, §6.11, §6.12 |
| 2 | Layout engine and layouts | §4.2, §5, §6.2, §6.3 |
| 3 | Typing surface and input engine | §2, §4.4, §4.5, §5, §6.2, §6.3, §6.4, §6.8 (built-in light/dark only), §6.13 |
| 4 | ★ Resizing and one-handed mode | §2 (C12), §5, §6.1 (Size group), §6.3 |
| 5 | ★ Clipboard core and edit tools | §2 (C2–C5, C14, C18), §5, §6.4.9, §6.5, §6.6.4, §6.11, §6.12 |
| 6 | Language data pipeline | §6.6, §6.7.11, §6.7.12, §7.3 |
| 7 | Prediction I: lexicon and completions | §5, §6.6, §6.7.1–§6.7.5, §6.13 |
| 8 | Prediction II: next word, typos, autocorrect | §6.7 (all), §6.13 |
| 9 | Personal learning and prediction modes | §6.7.5–§6.7.9, §6.11, §6.12 |
| 10 | Companion app, snippets, capture helpers | §6.1, §6.5, §6.10, §6.11, §6.12 |
| 11 | Themes, fonts, sounds, haptics | §6.8, §6.13 |
| 12 | Emoji panel and search | §6.9, §6.13 |
| 13 | Hardening and release prep | §2, §6.12, §6.13, §9, §10 |
| 14–18 | Optional extras | the phase section + §6.7 |

### 0.4 Decisions to confirm before Phase 0

Write your answers in the right column (or tell the AI in the Phase 0 prompt). Defaults are used if you leave them empty.

| # | Decision | Default in this plan | Your choice |
|---|---|---|---|
| 1 | App name | Kelid / کلید | |
| 2 | Bundle ID prefix | `com.example` (use something like `com.yourname`) | |
| 3 | App Group ID | `group.<prefix>.kelid` | |
| 4 | Apple account | Free for development, paid when publishing | |
| 5 | Minimum iOS | **17.0** (iPhone XS/XR and newer). 16.0 is possible (adds iPhone 8/X) but means `ObservableObject` instead of `@Observable` everywhere. | |
| 6 | Default Persian layout | `fa.standard`: 12/11/9 keys, all 32 letters visible (§6.2) | |
| 7 | Digits in the Persian layout | Persian ۰–۹. Number pads and URL/email fields always use Latin 0–9. | |
| 8 | Publish on the App Store? | Maybe later. The plan keeps everything App-Store-safe. | |

### 0.5 Prompt templates

**Standard phase prompt** (copy, replace `<N>`):

```text
Implement Phase <N> of PLAN.md.
1) Read CLAUDE.md and PROGRESS.md.
2) In PLAN.md read ONLY the sections listed for Phase <N> in §0.3 and the "Phase <N>" section. Do not read other phases.
3) Implement the tasks in order. After each numbered task run `make build` and `make test` and fix failures before moving on.
4) If the plan is wrong or impossible somewhere, pick the smallest sensible fix, record it in PROGRESS.md → Decision log, and continue.
5) When finished: tick the acceptance checklist in PROGRESS.md, write handoff notes (done / not done / how to test / next step),
   and commit with the message "Phase <N>: <title>".
Finally, tell me exactly what to test by hand on my iPhone.
```

**Split-session prompt** (for Size L phases):

```text
Implement Phase <N>, tasks <N.a> to <N.b> only (Session <A/B> in PLAN.md). Same rules as the standard phase prompt.
Stop after task <N.b>, update PROGRESS.md with where you stopped, and commit.
```

**Fix prompt:**

```text
Phase <N> manual test failed: <what happened, in which app, iOS version, screenshot if possible>.
Read CLAUDE.md, PROGRESS.md and the Phase <N> section of PLAN.md. Find the root cause, fix it, add a regression
test if the logic is testable, update PROGRESS.md, commit.
```

**Review prompt** (optional, after each phase):

```text
Review all changes since git tag phase-<N-1> against PLAN.md Phase <N> acceptance criteria and CLAUDE.md rules.
List every violation (memory, main-thread work, missing tests, networking, hand-edited project file, missing
localization), then fix them.
```

(In Claude Code you can also run `/code-review` for this.)

### 0.6 Milestones

| Milestone | Phases | What you have at the end |
|---|---|---|
| **M1 Daily driver** | 0–5 | Persian + English keyboard with live resizing, one-handed mode, and a full clipboard manager inside the keyboard |
| **M2 Smart typing** | 6–9 | Persian and English word completion, next-word prediction, typo correction, personal learning, prediction-source modes |
| **M3 Make it yours** | 10–12 | Full companion app, snippets, Share Extension and Shortcuts capture, themes and theme editor, emoji panel |
| **M4 Ship quality** | 13 | Performance, memory, accessibility, localization, privacy manifest, App Store readiness |
| **M5 Extras (optional)** | 14–18 | Glide typing, Finglish→Persian, neural re-ranker, iCloud sync and iPad layouts, custom layout editor |

---

## 1. Product vision

### 1.1 Problem

The built-in iPhone keyboard has no clipboard history, can't be resized, and offers weak or no word prediction for Persian. Most third-party keyboards fix one of these but are heavy, send data to servers, or handle Persian badly (ZWNJ/نیم‌فاصله, Persian digits and punctuation, colloquial spelling). Kelid fixes all of these and stays **100% on-device, with no network access**.

### 1.2 Priorities

| Priority | Area | Meaning |
|---|---|---|
| **P0** | Clipboard manager | History, pinning, search, one-tap paste chip, sensitive-data filtering, snippets, edit tools |
| **P0** | Resizing | Height per orientation, one-handed mode, bottom lift, key spacing, font size, live drag-to-resize |
| **P1** | Persian-first typing | Correct layout, ZWNJ, Persian digits and punctuation, diacritics |
| **P1** | Prediction and learning | Completion, next word, typo correction, personal learning; **prediction source modes: Off / Personal only / Language only / Hybrid** |
| **P2** | Customization | Themes and theme editor, fonts, sounds, haptics, toolbar, many options |
| **P2** | Emoji and snippets | Emoji panel with Persian and English search, text expansion |
| **P3** | Extras | Glide typing, Finglish→Persian, iCloud sync, iPad layouts |

### 1.3 Full feature list (end state)

**Typing**
- Persian layout (ISIRI-9147-ordered, mobile-adapted) and English QWERTY.
- Symbols pages with Persian punctuation (، ؛ ؟ « » ٪ ٫ ﷼) and a diacritics row (َ ُ ِ ّ ً ْ ٔ).
- Persian or Latin digits, optional number row, numeric pad for number fields.
- Dedicated ZWNJ (نیم‌فاصله) key; suggestions use the correct ZWNJ spelling.
- Long-press alternates (آ أ إ ء …) and optional digit hints.
- Shift and caps lock, English auto-capitalization, double-space period, smart punctuation spacing.
- Space-bar trackpad (RTL-aware), swipe left on backspace to delete words, accelerating backspace.
- Language key (فا ⇄ EN) and the system globe key; return-key labels that match the field (Go, Search, Send…) in Persian and English.

**Size**
- Live resize mode with drag handles: height, bottom lift, width (one-handed).
- Separate profiles for portrait and landscape; presets S / M / L / XL.
- Key gap, font scale, toolbar height, reset.

**Clipboard**
- Automatic capture, history with a size limit and retention time.
- Pin, search (Persian-aware normalization), one-tap "just copied" chip.
- Sensitive-content filtering and OTP auto-expiry; image clips.
- Snippets with folders and text-expansion shortcuts.
- Edit panel: cursor by character, word or line; copy, cut, paste; delete word; undo.
- Management in the companion app, Share Extension, Shortcuts and Back Tap capture, Face ID lock.

**Prediction**
- Completion from the first letter, next-word prediction.
- Typo tolerance using key proximity and Persian homophones (ت/ط, س/ص/ث, ز/ذ/ض/ظ, ه/ح, ق/غ).
- Autocorrect: off / suggest-only / automatic, with backspace-to-revert.
- Emoji suggestions.

**Learning**
- Personal words and phrases (up to 3-word sequences), recency decay, a new-word threshold so typos aren't learned.
- Block or forget words; import text replacements and contact names; "learn from my text" import.
- Incognito mode; nothing is learned in password, email, URL or OTP fields.
- Per-language modes: Off / Personal only / Language only / Hybrid, with a personal-weight slider.

**Themes**
- 12+ built-in themes and a theme editor: colors, corner radius, borders, shadows, gradients, photo backgrounds with blur and dim, fonts including Vazirmatn.
- Automatic light/dark switching, import and export.
- Key sounds and sound packs, haptic strength, key-press animation.

**Emoji:** full panel, Persian and English search, skin tones, recents.

**Companion app:** onboarding, status checks, try-it field, every setting, clipboard / snippet / dictionary managers, backup and restore, licenses, privacy statement.

**Privacy:** no network, no analytics, data export and delete-all.

### 1.4 Non-goals

- **No servers, no network access**, no cloud AI.
- **No voice dictation.** Keyboard extensions can't use the microphone. On Face ID iPhones the system shows its own mic button under the keyboard.
- **No GIF or sticker search** (needs network).
- **No text selection or "Select All".** Third-party keyboards can't select text (§2).
- **No iPad-specific layouts before Phase 17.** The keyboard still works on iPad.

### 1.5 Success metrics

| Area | Target |
|---|---|
| Typing latency | Finger lift → character in the text field ≤ 16 ms. No dropped or reordered letters at 8+ taps per second. |
| Suggestion latency | p95 ≤ 20 ms after a keystroke on an iPhone XS-class device |
| Memory | ≤ 30 MB while typing, ≤ 45 MB peak with a panel open |
| Prediction quality (eval harness §6.7.12) | Starting targets for informal Persian: keystroke savings ≥ 25%, top-3 next-word accuracy ≥ 30%. Record real baselines in Phase 8 and never regress them. |
| Stability | No crashes and no memory-limit kills in one week of daily use |

---
## 2. iOS keyboard platform facts and hard constraints

Every design choice below comes from these constraints. The AI must re-read this section before touching memory, clipboard, storage or text-handling code.

### 2.1 Constraints and their consequences

| # | Fact / constraint | Consequence for Kelid |
|---|---|---|
| **C1** | Keyboard extensions have an **undocumented memory limit**, observed at about **48–60 MB** of `phys_footprint` depending on device and iOS version. Going over it gets the extension **killed silently** (no crash log), and iOS switches back to the previous keyboard. Dirty heap counts against the limit; clean, memory-mapped read-only files mostly don't. | Budget ≤ 30 MB typing and ≤ 45 MB peak (§6.13). Language models are **memory-mapped** (`mmap`), never loaded into heap. Panels load lazily and release on close. Images are downsampled. Memory is measured on a real device every phase. |
| **C2** | **Full Access** (`RequestsOpenAccess = YES` plus the user's toggle) is **off by default**. Without it: no `UIPasteboard`, no network, no audio playback or input clicks, and **no shared container** with the app. (Apple's guide lists the shared container as Full-Access-only. In practice App Group writes fail silently, and reads may work on some iOS versions. Never rely on either.) Haptics are unreliable without it. | The keyboard must be **fully usable without Full Access**: typing, static prediction, local learning, in-keyboard Quick Settings, built-in themes. Clipboard, sounds, haptics, app-made settings and custom themes need Full Access and show a clear explanation when it's missing. |
| **C3** | Reading pasteboard **contents** (`string`, `image`, `items`…) can show the "*Kelid pasted from X*" banner (iOS 14+) and, on iOS 16+, may trigger an "Allow Paste" prompt for reads not started by the user. Reading **metadata** (`changeCount`, `hasStrings`, `hasURLs`, `hasImages`, `types`, `detectPatterns`) does not. Exact behavior for keyboard extensions varies by iOS version and must be checked on device (Phase 5, task 5.0). | Detect changes through `changeCount` only. Read contents **only when `changeCount` changed**, or when the user taps. The setting `clipboard.captureMode` = `auto` / `onTap` / `off` is chosen from the on-device test. |
| **C4** | A keyboard can only **insert plain text** (`insertText`). It cannot insert images or rich text. | Tapping an image clip copies it to the system pasteboard and tells the user to long-press → Paste. |
| **C5** | A keyboard **cannot select text**, can't use the host's edit menu or undo manager, and can only move the cursor (`adjustTextPosition`). `selectedText` (iOS 11+) is readable. | The edit panel offers cursor moves, copy/cut of the current selection, paste, delete-word, and a keyboard-level undo. No "Select All". |
| **C6** | `documentContextBeforeInput` / `AfterInput` are **partial**: often only the current paragraph or sentence, sometimes `nil`. They can lag right after `adjustTextPosition`, and hosts behave differently. | Keep a local **shadow buffer** of recent input. Re-sync on `textDidChange`. Verify destructive edits (word replacement) against the context and correct if needed (§6.4.8). |
| **C7** | A keyboard **can't draw above its own view**, so top-row key popups get clipped. | The toolbar/suggestion strip above the keys gives popups room to overlap. When the strip is hidden, top-row keys use an in-key highlight instead. |
| **C8** | **Secure text fields** and **phone pads** (`.phonePad`, `.namePhonePad`) always use the system keyboard. | Nothing to build for those. We **must** provide layouts for `.numberPad`, `.decimalPad` and `.asciiCapableNumberPad`. |
| **C9** | Host apps can refuse custom keyboards (`shouldAllowExtensionPointIdentifier`). Many banking apps do. | Document it in the app FAQ. |
| **C10** | A **"next keyboard" key is mandatory** when `needsInputModeSwitchKey == true` (false on Face ID iPhones, where the system draws a globe under the keyboard). Long-press on the globe must call `handleInputModeList(from:with:)`. | The globe key is a real `UIControl` that forwards its touch events (§6.4.7). |
| **C11** | **No microphone** access. | No dictation (see §1.4). |
| **C12** | **Width is always the screen width.** Height can be changed any time after the view first appears, using an Auto Layout height constraint (Apple's guide). `UIInputView.allowsSelfSizing = true` enables self-sizing. | Resizing = height constraint (§6.3). "One-handed" mode = narrower **content** inside the full-width view. There is no floating keyboard. |
| **C13** | The extension process is **short-lived**: created, suspended and killed often. `UIInputViewController` instances are recreated per presentation, and the system may keep old ones alive. | Cold start ≤ 150 ms to first keys drawn. Heavy services (language model, database) are **process-level singletons**, loaded lazily. Per-controller memory stays small. Changes are persisted promptly. |
| **C14** | A shared SQLite file in the App Group can get the process killed with **`0xDEAD10CC`** if it holds a lock while suspended. | GRDB in WAL mode with suspension notifications, short transactions, and suspend on disappear or background (§6.11). |
| **C15** | **App Store Guideline 4.4.1** (keyboards): must provide real keyboard input; must offer a way to switch to the next keyboard; must **work without Full Access and without network**; may collect user activity only to improve the keyboard on the device; must **not launch other apps** (except Settings) or repurpose keys (e.g. long-press return opens the camera). | Degraded mode (C2). No `openURL` tricks in release builds. No networking. No surprising key behavior. |
| **C16** | Custom keyboards don't get system extras: QuickType password/OTP autofill, the system autocorrect engine, and system dictation. They **can** read the user's text replacements and some contact names through `requestSupplementaryLexicon`. | Use `UILexicon` for text replacements (Phase 9). |
| **C17** | Emoji glyph rendering is **memory-hungry**. | Paged `UICollectionView` with cell reuse, limited pages alive at once, caches purged on close (§6.9). |
| **C18** | A keyboard **can't run in the background**. Clipboard changes made while it's hidden can't be observed as they happen. | Capture on appear (via `changeCount`) and poll while visible. Offer a Share Extension and a Shortcuts action (plus Back Tap) for manual capture (Phase 10). |

### 2.2 What Full Access changes

| Capability | Without Full Access | With Full Access |
|---|---|---|
| Typing, layouts, static prediction | ✓ | ✓ |
| Personal learning | ✓ stored in the keyboard's own container (the app can't see it) | ✓ shared with the app (App Group) |
| Settings changed in the app reach the keyboard | ✗ (not guaranteed) → use in-keyboard Quick Settings | ✓ |
| Clipboard history, chip, copy/cut/paste | ✗ | ✓ |
| Key sounds, haptics | ✗ (treat as unavailable) | ✓ |
| Snippets, custom themes made in the app | ✗ (built-in themes only) | ✓ |
| Network | ✗ | Never used by Kelid |

---

## 3. Key decisions

Each decision says **why** and what else was considered. If a phase must change one, it records the change in `PROGRESS.md → Decision log`.

| ID | Decision | Why | Alternatives considered |
|---|---|---|---|
| **D-01** | **Build our own keyboard engine.** Do not depend on KeyboardKit. | KeyboardKit switched to a **closed-source license at v10.0.0** (verified Sep 2026: tags ≥ 10.0.0 ship a "Closed Source License"; **9.9.1 is the last MIT release**). Localized layouts (Persian) and autocomplete were Pro-only anyway. Owning the engine gives full control over RTL, resizing and panels. | KeyboardKit Pro (paid, closed); forking 9.9.1 (MIT, but aging APIs). **Allowed:** reading the 9.9.1 source for patterns. |
| **D-02** | **UIKit typing surface** (`KeyGridView`) + **SwiftUI for everything else** (toolbar, suggestion bar, panels, app). | Reliable multi-touch rollover, per-touch state machines and the lowest latency need raw `UITouch` handling. SwiftUI is faster to build for lists and settings. | All-SwiftUI (per-key `DragGesture`s make rollover and trackpad gestures fragile); all-UIKit (slower to build panels). |
| **D-03** | **XcodeGen** (`project.yml`) generates the Xcode project. Logic lives in a **local Swift package `KelidKit`** with many small modules. | AI assistants break hand-edited `.pbxproj` files; YAML is easy to edit and review. Pure-logic modules test in seconds with `swift test` on macOS. | Hand-managed Xcode project; Tuist (more powerful, more to learn). |
| **D-04** | **iOS 17.0 minimum, Swift 6 language mode.** App and extension targets default to `MainActor` isolation. Engine modules are nonisolated with `Sendable` types. | `@Observable`, modern SwiftUI, and strict concurrency without fighting UIKit. | iOS 16 (see §0.4 #5). |
| **D-05** | **Settings** = one versioned, tolerant `Codable` blob (`KeyboardSettings`) in App Group `UserDefaults`, mirrored locally in the keyboard. The newest `updatedAt` wins. | One atomic value is easy to sync, migrate and back up. The local mirror keeps the keyboard working without Full Access. | Many separate keys (hard to migrate and sync). |
| **D-06** | **GRDB (SQLite)** in the App Group for clips, snippets and the personal language model. Local-container fallback without Full Access. | Mature, MIT-licensed, documents multi-process sharing (WAL, suspension handling). Queries, migrations and paging come for free. | Core Data (heavier in an extension); plain JSON files (see fallback in §6.11.6). |
| **D-07** | **Prediction:** our own **memory-mapped binary model ("KLM")** = compact trie + unigram/bigram/trigram tables, **Stupid Backoff** scoring, and a **noisy-channel** typo model with key-proximity and Persian-homophone costs, blended with a **personal model**. No neural network in v1. | Fits the memory limit (mmap), is fast (< 20 ms), explainable, testable, and works offline. | KenLM runtime (LGPL, harder to embed); Core ML LSTM/transformer (memory risk, see optional Phase 16); `UITextChecker` (no Persian support; English fallback only). |
| **D-08** | **Data pipeline** in Python: **hazm** (Persian normalization and tokenization) + **DuckDB** (n-gram counting) → TSV → our Swift `klm` tool → `.klm`. Sources: Persian Wikipedia, OpenSubtitles-derived frequencies, and a word list from Lilak (§7.3). | Reproducible, runs on a Mac, license-clean, and mixes formal with colloquial text. | Reusing AOSP/HeliBoard dictionaries (mixed licenses; Persian one is experimental); KenLM `lmplz` (optional upgrade). |
| **D-09** | **One keyboard extension** with internal language switching (Persian ⇄ English). | Shared clipboard, learning and state; a single "Full Access" toggle for the user. | Two extensions (Persian and English separately): duplicate state, two permission toggles. |
| **D-10** | **Default Persian layout `fa.standard`**: ISIRI 9147 letter order adapted to 3 rows (12/11/9), all 32 letters visible, ZWNJ key in the bottom row. Layouts are **JSON data**, so they can change without code. | Familiar to users of the standard Persian keyboards; no hidden letters. | 4-row layout with number row (available via setting); compact 11-key rows (`fa.compact`, optional). |
| **D-11** | **No networking and no third-party SDKs** (analytics, crash reporting, ads) in any target. | Privacy is a feature, Guideline 4.4.1 compliance is simpler, and memory stays low. | — |
| **D-12** | **Distribution path:** personal builds (free account) → TestFlight → App Store (paid account). Everything stays App-Store-safe from day one. | Avoids a rewrite later. | Side-loading only. |
| **D-13** | **All user-facing text in String Catalogs (en + fa)**; the companion app fully supports RTL. | Persian-first product. | — |

---

## 4. Architecture

### 4.1 Processes and shared data

```text
┌──────────────────────────────────── iPhone ─────────────────────────────────────┐
│                                                                                 │
│  Kelid.app  (companion app, SwiftUI)                                            │
│   onboarding · status · try-it field · settings · clipboard & snippet manager  │
│   dictionary manager · theme gallery/editor · backup · about                   │
│        │ read/write                                                            │
│        ▼                                                                       │
│  ┌───────────────── App Group container: group.<prefix>.kelid ───────────────┐ │
│  │ UserDefaults suite: settings.v1 (JSON) · heartbeat · flags                │ │
│  │ Library/Application Support/Kelid/kelid.sqlite  (GRDB, WAL)               │ │
│  │    clip · snippet · snippet_folder · user_word · user_bigram ·            │ │
│  │    user_trigram · user_correction_block                                   │ │
│  │ Library/Application Support/Kelid/Themes/   (custom theme JSON + images)  │ │
│  │ Library/Application Support/Kelid/Clips/    (image clips + thumbnails)    │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│        ▲ read/write (needs Full Access)                                        │
│        │                                                                       │
│  KelidKeyboard.appex  (UIInputViewController)                                   │
│   bundle: LM/fa.klm · LM/en.klm · emoji data · sounds                          │
│   own container (fallback without Full Access): local settings mirror,         │
│   local user-model DB, emoji recents, last language, lastSeenChangeCount       │
│                                                                                 │
│  KelidShare.appex (Share Extension, Phase 10) ──► clip table                    │
│  App Intents in Kelid.app (Phase 10): "Save to Kelid" (Shortcuts, Back Tap)    │
│                                                                                 │
│  Darwin notifications between processes (§4.7)                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Modules (Swift package `Packages/KelidKit`)

Rule: **engine modules never import UIKit or SwiftUI**, so they can be tested with `swift test` on macOS. UIKit-only code is wrapped in `#if canImport(UIKit)` or lives in `KeyboardUI`.

| Module | Imports | Responsibility | Depends on |
|---|---|---|---|
| `KelidCore` | Foundation, os | App Group IDs and paths, `DarwinNotifier`, `Log` (os.Logger wrapper), `Clock` protocol, `MemoryProbe`, small utilities | — |
| `KelidSettings` | Foundation | `KeyboardSettings` model and defaults, tolerant decoding, migrations, clamping, `SettingsStore` | KelidCore |
| `PersianText` | Foundation | Normalization, match/search keys, tokenization, word-character rules, ZWNJ rules, digit conversion, direction detection | — |
| `KeyboardLayout` | Foundation (CoreGraphics types) | Layout JSON models (bundled as package resources), loader and validator, `BottomRowBuilder`, `LayoutEngine` geometry, `ProximityMap` | KelidCore, KelidSettings |
| `InputEngine` | Foundation | `TextDocument` protocol, `FieldTraits`, `InputProcessor` (key actions → text operations), shift/caps machine, autocap, punctuation and ZWNJ rules, `TypingContext`, suggestion acceptance, autocorrect revert, undo stack, learning events | PersianText, KeyboardLayout, KelidSettings |
| `PredictionEngine` | Foundation | KLM reader (mmap), lexicon and trie search, n-gram scoring, fuzzy search, `UserModel`, `Ranker`, `SuggestionService` (actor) | PersianText, KelidCore, swift-collections (HeapModule) |
| `KelidStorage` | Foundation, GRDB | Shared DB setup, migrations, repositories (clips, snippets, user model), suspension handling | KelidCore, GRDB |
| `ClipboardKit` | Foundation (+ UIKit behind `#if canImport(UIKit)`) | `PasteboardClient` protocol and live/fake clients, `ClipClassifier`, `ClipboardMonitor`, image downsampling | KelidStorage, PersianText, KelidCore |
| `ThemeKit` | Foundation (+ UIKit/SwiftUI bridges behind `#if canImport`) | Theme model, built-in themes, resolver, custom theme storage | KelidCore |
| `EmojiData` | Foundation | Emoji dataset loading, search index, recents, skin tones | PersianText |
| `KeyboardUI` | UIKit, SwiftUI | `KeyGridView`, `KeyView`, callouts, toolbar, suggestion bar, panels (clipboard, edit, emoji, quick settings, resize), `KeyboardRootView`, `KeyboardPreview` (for the app) | all of the above |
| `klm` (executable, macOS; **separate package `Tools/klm`**, so iOS builds never try to build it) | Foundation, ArgumentParser | `klm build`, `klm inspect`, `klm eval` | KelidKit products PredictionEngine, PersianText (local path) |

**App targets** (in `project.yml`):

| Target | Type | Sources | Links |
|---|---|---|---|
| `Kelid` | iOS app | `App/` | KeyboardUI, KelidStorage, ClipboardKit, ThemeKit, … |
| `KelidKeyboard` | App extension (`com.apple.keyboard-service`) | `Keyboard/` (thin: controller and wiring) | KeyboardUI (+ transitive) |
| `KelidShare` | Share extension (Phase 10) | `ShareExtension/` | KelidStorage, ClipboardKit |

### 4.3 Repository layout

```text
kelid/                                  (this folder)
├── CLAUDE.md                           AI working rules (Appendix A)
├── PLAN.md                             this plan
├── PROGRESS.md                         progress, handoff notes, decision log (Appendix B)
├── README.md                           human setup guide
├── project.yml                         XcodeGen spec
├── Makefile                            gen | build | test | lint | format | klm | data-quick | data-full
├── Config/
│   ├── Base.xcconfig                   shared build settings, includes Local.xcconfig
│   ├── Local.xcconfig.example          template: team ID, bundle prefix, app group
│   └── Local.xcconfig                  (gitignored) your values
├── App/                                companion app
│   ├── KelidApp.swift
│   ├── Features/{Onboarding,Home,Settings,Clipboard,Snippets,Dictionary,Themes,About}/
│   ├── Resources/{Assets.xcassets, Localizable.xcstrings}
│   ├── Info.plist · Kelid.entitlements · PrivacyInfo.xcprivacy
├── Keyboard/                           keyboard extension
│   ├── KeyboardViewController.swift
│   ├── KeyboardServices.swift          process-level service container
│   ├── ProxyTextDocument.swift         UITextDocumentProxy → TextDocument adapter
│   ├── Resources/{LM/fa.klm, LM/en.klm, Sounds/, Localizable.xcstrings}
│   ├── Info.plist · KelidKeyboard.entitlements · PrivacyInfo.xcprivacy
├── ShareExtension/                     (Phase 10)
├── Packages/KelidKit/
│   ├── Package.swift
│   ├── Sources/<one folder per module in §4.2>
│   └── Tests/<ModuleName>Tests/
├── Tools/
│   ├── data-pipeline/                  Python (Phase 6): pyproject.toml, pipeline/, data/ (gitignored), out/, reports/, eval/
│   ├── klm/                            Swift package: the `klm` command-line tool (macOS only)
│   └── scripts/                        helper shell scripts (lint-no-network.sh, bench.sh)
└── docs/
    ├── ATTRIBUTIONS.md                 all licenses and data sources (shown in the app)
    ├── PRIVACY.md                      privacy policy text
    └── QA-CHECKLIST.md                 manual test matrix (§9)
```

The generated `Kelid.xcodeproj` is **gitignored**. Run `make gen` after cloning or after editing `project.yml`.

### 4.4 Runtime flow and threading

```text
UITouch ─► KeyGridView (hit test → KeyTouchTracker per touch)
        ─► KeyAction (.character("س"), .backspace, .space, .zwnj, …)
        ─► KeyboardController (@MainActor)
             ├─ FeedbackService (haptic/sound fired at touch-down)
             ├─ InputProcessor.handle(action, doc: ProxyTextDocument) ─► insertText / deleteBackward / adjustTextPosition
             │     └─ returns [InputEffect] (shift/page/language changes, learning events, suggestion request…)
             └─ SuggestionService (actor, background) ◄─ TypingContext + generation number
                   └─ PredictionEngine (mmap LM + UserModel) ─► SuggestionResult ─► MainActor ─► SuggestionBar
```

- **Main thread:** all UIKit and SwiftUI work, and **every `UITextDocumentProxy` call**.
- **`SuggestionService` actor:** prediction. Every request carries a generation number; results for older generations are dropped. The language model loads in a background `Task` at utility priority after the first frame is drawn.
- **`UserModel` actor:** personal counts. Writes go to the database asynchronously (write-behind).
- **GRDB writer queue:** database writes. **Never** block the main thread on the database.
- **Budgets:** main-thread work per keystroke ≤ 4 ms. Suggestions ≤ 20 ms p95 (off the main thread).

### 4.5 State model

```swift
@Observable @MainActor final class KeyboardState {
    var mode: Mode = .typing            // .typing | .clipboard | .emoji | .edit | .quickSettings | .resize | .search(SearchTarget)
    var language: LanguageID = .fa
    var page: KeyboardPage = .letters   // .letters | .symbols1 | .symbols2 | .numpad
    var shift: ShiftState = .off        // .off | .oneShot(auto: Bool) | .capsLock   (English only)
    var suggestions: SuggestionResult = .empty
    var clipChip: ClipChip?             // newest clip shown in the suggestion strip
    var fullAccess: Bool = false
    var incognito: Bool = false
    var fieldTraits: FieldTraits = .default
    var sizeProfile: SizeProfile        // resolved for the current orientation
    var theme: ResolvedTheme
    var toast: Toast?
}
```

- `KeyboardState` is the only source of UI state. SwiftUI views observe it.
- `KeyGridView` (UIKit) is updated **imperatively** by `KeyboardController` (`apply(layout:theme:shift:)`), not by observation, to keep typing fast.

### 4.6 Where data lives

| Data | Written by | Location | Without Full Access |
|---|---|---|---|
| Settings | App, keyboard | App Group `UserDefaults` key `settings.v1` + keyboard local mirror | Keyboard local only |
| Clips | Keyboard, app, Share Extension, App Intents | App Group DB `clip` | Not available |
| Snippets | App (keyboard reads, updates use count) | App Group DB `snippet*` | Not available |
| Personal model | Keyboard (app edits and imports) | App Group DB `user_*` | Keyboard local DB, merged into the App Group once Full Access is on |
| Custom themes | App | App Group `Themes/` | Built-in themes only |
| Language models `.klm` | Build | **Keyboard bundle only** (read-only). The app reads them from `Bundle.main.builtInPlugInsURL/KelidKeyboard.appex/LM/`. | ✓ |
| Layouts, emoji data, fonts | Build | Package resources / bundles | ✓ |
| Emoji recents, last language, `lastSeenChangeCount` | Keyboard | Keyboard local `UserDefaults` | ✓ |
| Heartbeat (`kb.heartbeat`, `kb.hasFullAccess`, `kb.version`) | Keyboard | App Group `UserDefaults` | Not available (the app shows "unknown") |

> Large resources (`.klm`) must **not** be Swift-package resources: package resource bundles are copied into both the app and the extension, which would double the app size.

### 4.7 Cross-process sync (Darwin notifications)

The names are prefixed with the App Group ID. Posting process → observers re-read from the shared store.

| Name suffix | Posted when | Observers do |
|---|---|---|
| `.settings.changed` | Settings saved | `SettingsStore.reload()` |
| `.clips.changed` | Clips inserted, updated or deleted | Clipboard lists re-fetch the current page |
| `.snippets.changed` | Snippets edited | Re-fetch |
| `.userdict.changed` | App edited, imported or reset the personal model | `UserModel.reload()` |
| `.themes.changed` | Custom theme saved or deleted | Reload theme list, re-resolve the active theme |

Darwin notifications carry **no payload**. Always re-read from storage.

---

## 5. Engineering conventions

### 5.1 Code rules (the AI must follow these)

1. **Swift 6**, strict concurrency. UI code is `@MainActor`. Engines use value types and `Sendable`. `@unchecked Sendable` only with a comment explaining why (e.g. read-only mmap memory).
2. **No force unwraps** (`!`) or `try!` outside tests. The one exception is loading bundled resources, with a clear `fatalError` message.
3. **No `print`.** Use `Log` (`os.Logger`, subsystem `<bundle prefix>.kelid`, one category per module).
4. **Small files:** aim for ≤ 400 lines per file and ≤ 250 lines per type. Split by responsibility.
5. **Abstractions at the edges:** `UITextDocumentProxy` only through `TextDocument`; `UIPasteboard` only through `PasteboardClient`; time only through `Clock`. This keeps logic testable.
6. **Memory hygiene:** no global caches without a size limit; downsample images with ImageIO; never `UIImage(named:)` for large assets; `[weak self]` in long-lived closures; release panel views when closed.
7. **Main-thread hygiene:** no file I/O, database access or prediction on the main thread. Everything heavy is `async`.
8. **Settings:** every new option goes into `KeyboardSettings` with a default, a clamp, and tolerant decoding (§6.1.1).
9. **Localization:** every user-facing string goes in a String Catalog (`en`, `fa`). Test RTL.
10. **Accessibility:** every control has an accessibility label. Keys use the `.keyboardKey` trait.
11. **Dependencies:** only those in §7. Adding one requires a Decision-log entry first.
12. **Never** hand-edit `Kelid.xcodeproj`. Edit `project.yml`, then `make gen`.
13. **Never** add networking (`URLSession`, `Network.framework`, sockets). `make lint` runs `Tools/scripts/lint-no-network.sh`, which fails on these symbols.
14. **Never** use private APIs or the responder-chain `openURL` trick in release builds.
15. **Package code must be app-extension-safe:** no `UIApplication.shared` and no other extension-unavailable APIs in `KelidKit`. App-only code goes in `App/`.
16. **Tests:** every phase adds unit tests for its logic. Engine modules aim for ≥ 80% line coverage.

### 5.2 Build and test commands

| Command | Does |
|---|---|
| `make gen` | `xcodegen generate` |
| `make build` | Builds app + keyboard for the iOS Simulator (`xcodebuild -scheme Kelid -destination 'generic/platform=iOS Simulator' build`) |
| `make test` | `swift test --package-path Packages/KelidKit` (macOS, fast) **and** `xcodebuild test` for iOS-only tests (snapshots, UI) on `$(SIM)` |
| `make lint` / `make format` | SwiftFormat + SwiftLint + no-network check |
| `make klm` | Builds `fa.klm` / `en.klm` from pipeline outputs (Phase 7+) |
| `make data-quick` / `make data-full` | Language data pipeline (Phase 6) |

`SIM` defaults to a current iPhone simulator. If the name doesn't exist on your Xcode, set it with `make test SIM="platform=iOS Simulator,name=<name from xcrun simctl list devices available>"`.

### 5.3 Definition of Done (every phase)

- [ ] All phase tasks implemented. Anything skipped is written in PROGRESS.md with the reason.
- [ ] `make build`, `make test`, `make lint` pass from a clean checkout (`make gen` first).
- [ ] New logic has unit tests; new visual components have a snapshot or preview.
- [ ] No new Auto Layout warnings, no main-thread I/O, memory within budget (measured on device when the phase says so).
- [ ] New strings are localized in `en` and `fa`.
- [ ] PROGRESS.md updated (checklist, handoff notes, decisions, measurements).
- [ ] Committed with the message `Phase N: <title>`.

### 5.4 Debugging the keyboard extension

- **Run with a debugger:** choose the `KelidKeyboard` scheme → Run → pick **Kelid** as the host app → tap the *Try it* field → switch to Kelid with the globe key. Breakpoints now work. Or use *Debug → Attach to Process → KelidKeyboard*.
- **Logs:** Console.app → select your device → filter by subsystem `<bundle prefix>.kelid`.
- **Simulator:** turn off *I/O → Keyboard → Connect Hardware Keyboard* (⇧⌘K) so the software keyboard shows. The Simulator does **not** enforce the memory limit, and it syncs the Mac pasteboard (confusing for clipboard tests). Verify both on a device.
- **Keyboard vanished or switched back to Apple's keyboard:** it crashed or was killed. Check the Xcode console, then *Settings → Privacy & Security → Analytics & Improvements → Analytics Data* for `KelidKeyboard…` or `JetsamEvent…` entries.
- **Keyboard not listed in Settings:** the extension's bundle ID must start with the app's bundle ID; delete the app and reinstall; restart the Simulator.
- **Debug overlay** (Phase 3+, *Advanced → Debug overlay*): shows memory footprint, last suggestion latency, Full Access, App Group readability, model state and pasteboard `changeCount`.

---
## 6. Specifications

These are reference specs. Phases point to the parts they need.

### 6.1 Settings catalog

#### 6.1.1 Model rules

- One struct, `KeyboardSettings`, with nested groups. `schemaVersion: Int` and `updatedAt: Date` live at the top level.
- Stored as JSON `Data` under the key `settings.v1`: in the App Group suite (shared), and mirrored in the keyboard's `UserDefaults.standard` (local). On load, **the newer `updatedAt` wins**.
- **Tolerant decoding is mandatory.** A missing key or an unknown enum value falls back to the default, so old blobs keep working as settings are added:

```swift
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default d: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? d()
    }
}
// In every settings struct:
public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = Self()
    showNumberRow = c.value(.showNumberRow, default: d.showNumberRow)
    // … one line per property
}
```

- `func clamped() -> KeyboardSettings` enforces every range below. It runs after decoding and before saving.
- **"Edited in"** column: **KB** = in-keyboard Quick Settings panel (works without Full Access), **App** = companion app.

#### 6.1.2 General (`general`)

| Key | Type | Default | Range / options | Edited in | Phase |
|---|---|---|---|---|---|
| `enabledLanguages` | `[LanguageID]` | `[.fa, .en]` | fa, en (at least one) | KB, App | 3 |
| `persianLayout` | enum | `.standard` | `.standard`, `.compact`, `.standard4Row` | KB, App | 2 |
| `englishLayout` | enum | `.qwerty` | `.qwerty` (others optional in Phase 18) | App | 2 |
| `languageSwitch` | enum | `.key` | `.key`, `.spaceSwipe`, `.both` | App | 3 |
| `rememberLastLanguage` | Bool | `true` | | App | 3 |
| `showNumberRow` | Bool | `false` | | KB, App | 2/4 |
| `persianDigits` | enum | `.persian` | `.persian` (۰–۹), `.latin` (0–9) | KB, App | 2 |
| `numpadDigits` | enum | `.latin` | `.latin`, `.persian` (number fields) | App | 3 |
| `longPressDelayMs` | Int | 350 | 200–800 | App | 3 |
| `keyPopups` | Bool | `true` | | KB, App | 3 |
| `keyHints` | Bool | `false` | Show digit/alternate hints on keys | App | 3 |
| `doubleSpacePeriod` | Bool | `true` | | App | 3 |
| `autoCapitalize` | Bool | `true` | English only | App | 3 |
| `smartPunctuationSpacing` | Bool | `true` | | App | 3 |
| `spaceTrackpad` | enum | `.drag` | `.off`, `.drag`, `.longPress` | KB, App | 3 |
| `cursorSpeed` | Double | 1.0 | 0.5–2.0 | App | 3 |
| `rtlVisualCursor` | Bool | `true` | Arrows and trackpad move *visually* in RTL text | App | 3 |
| `backspaceSwipeDeletesWords` | Bool | `true` | | App | 3 |
| `backspaceRepeat` | enum | `.normal` | `.slow`, `.normal`, `.fast` | App | 3 |
| `bottomRowEmojiKey` | Bool | `false` | Emoji key next to space | App | 12 |

#### 6.1.3 Size (`size`), with one `SizeProfile` per orientation

`size.portrait`, `size.landscape` (and later `size.padPortrait`, `size.padLandscape`) are each a `SizeProfile`:

| Key | Type | Default (portrait / landscape) | Range | Edited in | Phase |
|---|---|---|---|---|---|
| `rowHeight` | CGFloat (pt) | device default (§6.3.2) / 40 | portrait 38–80, landscape 30–60 | KB (resize mode, slider), App | 4 |
| `toolbarHeight` | CGFloat | 44 / 36 | 32–56 | App | 4 |
| `bottomLift` | CGFloat | 0 / 0 | 0–80 | KB, App | 4 |
| `sidePadding` | CGFloat | 3 / 3 | 0–24 | App | 4 |
| `keyGapH` | CGFloat | 6 / 6 | 0–14 | App | 4 |
| `keyGapV` | CGFloat | 12 / 8 | 2–20 | App | 4 |
| `oneHanded` | enum | `.off` | `.off`, `.left`, `.right` | KB, App | 4 |
| `oneHandedWidthRatio` | Double | 0.80 | 0.60–0.95 | KB, App | 4 |
| `fontScale` | Double | 1.0 | 0.8–1.4 | KB, App | 4 |

Global clamp: total keyboard height ≤ 60% of screen height in portrait, ≤ 70% in landscape (§6.3.3).

#### 6.1.4 Toolbar (`toolbar`)

| Key | Type | Default | Options | Edited in | Phase |
|---|---|---|---|---|---|
| `mode` | enum | `.auto` | `.auto` (icons when idle, suggestions while typing), `.suggestionsOnly`, `.iconsOnly`, `.hidden` | KB, App | 7 |
| `items` | `[ToolbarItem]` | `[.clipboard, .emoji, .edit, .resize, .oneHanded, .settings]` | also `.incognito`, `.snippets`, `.dismiss`, `.language`; up to 7 | App | 4–12 |

#### 6.1.5 Prediction (`prediction`), per language (`prediction.fa`, `prediction.en`)

| Key | Type | Default (fa / en) | Options | Edited in | Phase |
|---|---|---|---|---|---|
| `enabled` | Bool | `true` / `true` | | KB, App | 7 |
| `source` | enum | `.hybrid` / `.hybrid` | `.off`, `.personalOnly`, `.languageOnly`, `.hybrid` | KB, App | 9 |
| `personalWeight` | Double | 0.6 / 0.5 | 0–1 (hybrid only) | KB, App | 9 |
| `nextWord` | Bool | `true` / `true` | | App | 8 |
| `suggestionCount` | Int | 3 / 3 | 3–5 | App | 7 |
| `autocorrect` | enum | `.suggestOnly` / `.auto` | `.off`, `.suggestOnly`, `.auto` | KB, App | 8 |
| `autocorrectStrength` | Double | 0.5 / 0.5 | 0–1 | App | 8 |
| `emojiSuggestions` | Bool | `true` / `true` | | App | 8 |
| `showVerbatimSlot` | Bool | `true` / `true` | Shows the typed word as the first slot | App | 7 |
| `preferZWNJForms` | Bool | `true` / — | Suggestions use canonical ZWNJ spelling (می‌خوام) | App | 7 |
| `blockOffensive` | Bool | `true` / `true` | | App | 8 |

#### 6.1.6 Learning (`learning`)

| Key | Type | Default | Range | Edited in | Phase |
|---|---|---|---|---|---|
| `enabled` | Bool | `true` | | KB, App | 9 |
| `newWordThreshold` | Int | 2 | 1–5 uses before a new (unknown) word is suggested | App | 9 |
| `learnPhrases` | Bool | `true` | Learn 2- and 3-word sequences | App | 9 |
| `halfLifeDays` | Int | 60 | 7–365 | App | 9 |
| `maxUserWords` | Int | 50 000 | 5 000–200 000 | App | 9 |
| `useTextReplacements` | Bool | `true` | iOS Settings → General → Keyboard → Text Replacement | App | 9 |
| `useContactNames` | Bool | `false` | | App | 9 |
| `incognito` | Bool | `false` | Toolbar toggle | KB, App | 9 |

#### 6.1.7 Clipboard (`clipboard`)

| Key | Type | Default | Range / options | Edited in | Phase |
|---|---|---|---|---|---|
| `enabled` | Bool | `true` | | KB, App | 5 |
| `captureMode` | enum | from the Phase 5 test (`.auto` if no prompt) | `.auto`, `.onTap`, `.off` | KB, App | 5 |
| `pollWhileVisible` | Bool | `true` | Check `changeCount` every 1 s while the keyboard is visible | App | 5 |
| `maxItems` | Int | 200 | 20–2000 (pinned items not counted) | KB, App | 5 |
| `retentionDays` | Int? | 30 | 1, 7, 30, 90, `nil` = forever (pinned and snippets exempt) | KB, App | 5 |
| `showChip` | Bool | `true` | | KB, App | 5 |
| `chipSeconds` | Int | 90 | 15–600 | App | 5 |
| `skipSensitive` | Bool | `true` | Skip password-manager items (§6.5.3) | App | 5 |
| `otpHandling` | enum | `.expire` | `.skip`, `.expire` (2 min), `.keep` | App | 5 |
| `maskPasswordLike` | Bool | `true` | Mask and auto-expire (10 min) password-like tokens | App | 5 |
| `captureImages` | Bool | `true` | | App | 5 |
| `tapAction` | enum | `.insert` | `.insert`, `.insertAndClose`, `.copy` | App | 5 |
| `smartSpacing` | Bool | `true` | Add a space between a word and the pasted text when needed | App | 5 |
| `ignorePatterns` | `[String]` | `[]` | Regular expressions; matching clips are not stored | App | 10 |
| `lockWithFaceID` | Bool | `false` | App's clipboard tab only | App | 10 |

#### 6.1.8 Appearance and feedback (`appearance`)

| Key | Type | Default | Options | Edited in | Phase |
|---|---|---|---|---|---|
| `themeMode` | enum | `.followApp` | `.fixed`, `.followSystem` (trait), `.followApp` (`keyboardAppearance`, falling back to the system trait) | KB, App | 11 |
| `lightThemeID` / `darkThemeID` / `fixedThemeID` | String | `kelid.light` / `kelid.dark` / `kelid.light` | | KB, App | 11 |
| `persianFont` | enum | `.system` | `.system`, `.vazirmatn` | KB, App | 11 |
| `latinFont` | enum | `.system` | `.system`, `.rounded`, `.monospaced` | App | 11 |
| `keyPressAnimation` | enum | `.pop` | `.none`, `.pop`, `.fade` | App | 11 |
| `sound` | enum | `.off` | `.off`, `.system`, `.soft`, `.typewriter` | KB, App | 3/11 |
| `haptics` | enum | `.light` | `.off`, `.light`, `.medium`, `.rigid` | KB, App | 3/11 |
| `reduceHapticsInLowPower` | Bool | `true` | | App | 11 |

#### 6.1.9 Emoji (`emoji`)

| Key | Type | Default | Options | Phase |
|---|---|---|---|---|
| `defaultSkinTone` | enum | `.none` | none + 5 Fitzpatrick tones | 12 |
| `recentsLimit` | Int | 32 | 16–64 | 12 |
| `searchLanguages` | `[LanguageID]` | `[.fa, .en]` | | 12 |

#### 6.1.10 Snippets and text expansion (`snippets`)

| Key | Type | Default | Phase |
|---|---|---|---|
| `expansionEnabled` | Bool | `true`: a snippet's shortcut followed by space is replaced by the snippet text | 10 |

#### 6.1.11 Advanced (`advanced`)

| Key | Type | Default | Phase |
|---|---|---|---|
| `debugOverlay` | Bool | `false` | 3 |
| `pasteboardLab` | Bool | `false` (debug builds only) | 5 |

---

### 6.2 Layouts

#### 6.2.1 Layout file format

Layouts are JSON files bundled as `KeyboardLayout` package resources (`Sources/KeyboardLayout/Layouts/*.json`). **Rows are written in visual left-to-right order**, for Persian too (ض is the leftmost key, same as the Q position).

```json
{
  "id": "fa.standard",
  "language": "fa",
  "direction": "rtl",
  "name": { "en": "Persian", "fa": "فارسی" },
  "spaceLabel": "فارسی",
  "pages": {
    "letters": {
      "rows": [
        ["ض","ص","ث","ق","ف","غ","ع","ه","خ","ح","ج","چ"],
        ["ش","س","ی","ب","ل","ا","ت","ن","م","ک","گ"],
        ["ظ","ط","ژ","ز","ر","ذ","د","پ","و", { "action": "backspace", "width": 1.5 }]
      ]
    }
  },
  "alternates": {
    "ا": ["آ","أ","إ","ء","ٱ"],
    "ی": ["ئ","ي","ى"],
    "ه": ["ۀ","هٔ","ة","ھ"],
    "و": ["ؤ"],
    "ک": ["ك"],
    "ت": ["ة"],
    "ل": ["لا"],
    "ز": ["ژ"],
    "ج": ["چ"],
    ".": ["،","؛","؟","!",":","…"]
  },
  "digitHints": { "ض":"۱","ص":"۲","ث":"۳","ق":"۴","ف":"۵","غ":"۶","ع":"۷","ه":"۸","خ":"۹","ح":"۰" }
}
```

**Key entry forms:**
- A plain string `"ض"` is shorthand for `{ "out": "ض" }`.
- A key object has these fields:

| Field | Type | Meaning |
|---|---|---|
| `out` | String | Text inserted (character keys) |
| `label` | String? | Display label if different from `out` (e.g. `"◌َ"` for a combining mark; `U+25CC` + mark) |
| `action` | String? | `char` (default), `shift`, `backspace`, `space`, `return`, `zwnj`, `page:letters`, `page:symbols1`, `page:symbols2`, `language`, `globe`, `emoji`, `dismiss` |
| `width` | Double | Relative width units (default 1.0) |
| `spacer` | Double | An empty gap of this width (no key) |
| `alternates` | `[String]`? | Overrides the file-level `alternates` table |
| `shifted` | String? | Output with Shift (English letters get uppercase automatically) |
| `hint` | String? | Small corner label |

**Validation** (`LayoutValidator`): every row has ≥ 1 key; widths > 0; actions known; ids unique; every Persian letter appears exactly once in `fa.*` letters pages; no empty `out`.

#### 6.2.2 Persian letters (`fa.standard`, default)

| Row | Keys (visual left → right) |
|---|---|
| 1 (12) | ض ص ث ق ف غ ع ه خ ح ج چ |
| 2 (11) | ش س ی ب ل ا ت ن م ک گ |
| 3 (9 + ⌫) | ظ ط ژ ز ر ذ د پ و ⌫(1.5) |

All 32 Persian letters are visible. Variants:
- **`fa.compact`**: row 1 without چ (11 keys, wider). چ becomes the first long-press alternate of ج.
- **`fa.standard4Row`**: `fa.standard` plus a number row (the same as the `showNumberRow` setting).

**Please confirm the default Persian row layout in Phase 2.** It is data, so changing it later costs nothing.

#### 6.2.3 English letters (`en.qwerty`)

| Row | Keys |
|---|---|
| 1 | q w e r t y u i o p |
| 2 | spacer(0.5) a s d f g h j k l spacer(0.5) |
| 3 | ⇧(1.5) z x c v b n m ⌫(1.5) |

Alternates (iOS-like): a: à á â ä æ ã å ā · c: ç ć č · e: è é ê ë ē ė ę · i: î ï í ī į ì · l: ł · n: ñ ń · o: ô ö ò ó œ ø ō õ · s: ß ś š · u: û ü ù ú ū · y: ÿ · z: ž ź ż. Digit hints: q→1 … p→0.

#### 6.2.4 Symbol pages

**English `symbols1`:** `1 2 3 4 5 6 7 8 9 0` / `- / : ; ( ) $ & @ "` / `#+=(1.5) . , ? ! ' ⌫(1.5)`
**English `symbols2`:** `[ ] { } # % ^ * + =` / `_ \ | ~ < > € £ ¥ •` / `123(1.5) . , ? ! ' ⌫(1.5)`

**Persian `symbols1`:** `۱ ۲ ۳ ۴ ۵ ۶ ۷ ۸ ۹ ۰` / `- / : ؛ ( ) ﷼ @ « »` / `#+=(1.5) . ، ؟ ! ٫ ⌫(1.5)`
**Persian `symbols2`:** `[ ] { } # ٪ ^ * + =` / `_ \ | ~ < > $ € • ـ` / `۱۲۳(1.5) ◌َ ◌ُ ◌ِ ◌ّ ◌ً ◌ْ ◌ٔ ⌫(1.5)`

The diacritic keys output only the combining mark (U+064E, U+064F, U+0650, U+0651, U+064B, U+0652, U+0654) and show a dotted-circle label.

Persian symbol alternates: `۱→1,١` (same pattern for every digit) · `،→,` · `؛→;` · `؟→?` · `٫→, ٬` · `٪→%` · `«→"` · `»→"`.

**Digit substitution:** when `persianDigits == .latin`, Persian pages and the number row use `0–9`, and the Persian digits become the alternates.

#### 6.2.5 Numeric pad (`numpad`)

Used for `.numberPad`, `.decimalPad` and `.asciiCapableNumberPad`:

| Row | Keys |
|---|---|
| 1 | 1 2 3 |
| 2 | 4 5 6 |
| 3 | 7 8 9 |
| 4 | (`.` for decimalPad, globe if needed, else empty) 0 ⌫ |

Digits follow `numpadDigits` (default **Latin**, because many apps reject Persian digits in number fields).

#### 6.2.6 Bottom row (built in code by `BottomRowBuilder`)

The bottom row is not in the JSON. It depends on page, language count, `needsInputModeSwitchKey`, `keyboardType`, `returnKeyType` and settings. Widths are in parentheses; `flex` takes the remaining width.

| Context | Keys |
|---|---|
| Persian letters | `۱۲۳`(1.25) · 🌐(1.25)\* · `EN`(1.25)\*\* · ZWNJ(1.25) · space "فارسی"(flex) · `.`(1.0, alternates ، ؛ ؟ ! : …) · return(1.75) |
| English letters | `123`(1.25) · 🌐\* · `فا`\*\* · space "English"(flex) · `.`(1.0, alternates , ? ! ' ") · return(1.75) |
| Symbols pages | `ابپ` / `ABC`(1.25) · 🌐\* · space(flex) · return(1.75) |
| `.emailAddress` (English forced) | `123` · 🌐\* · space(flex, ≥ 3) · `@`(1) · `.`(1) · return |
| `.URL` (English forced) | `123` · 🌐\* · `.`(1) · `/`(1) · `.com`(1.5, alternates .ir .org .net .edu) · return(2) |
| `.webSearch` | as letters, return label "Search/جستجو" |
| `.twitter` | `123` · 🌐\* · `@` · `#` · space(flex) · return |
| numpad | none (see §6.2.5) |

\* only when `needsInputModeSwitchKey == true`. \*\* only when more than one language is enabled.
With `bottomRowEmojiKey`, an emoji key (1.25) goes after the language key.

---

### 6.3 Geometry and resizing

#### 6.3.1 Height formula

```text
totalHeight = toolbarVisibleHeight            (0 when toolbar.mode == .hidden)
            + topPadding(4) + rows × rowHeight + bottomPadding(4)
            + bottomLift
keyVisualHeight = rowHeight − keyGapV
keyUnitWidth    = (contentWidth − 2·sidePadding − (keysInRow − 1)·keyGapH) / Σ(widthUnits in row)
```

- `rows` = rows on the current page (usually 4: three letter rows + bottom row; 5 with the number row).
- **The same height is used for panels** (clipboard, emoji, edit, settings), so opening a panel doesn't make the host app jump. The search sub-mode is the exception (§6.5.6).
- **Storing `rowHeight`** instead of total height means toggling the number row adds exactly one row.

#### 6.3.2 Defaults per device class (portrait `rowHeight`)

| Device class | Rule | Default `rowHeight` |
|---|---|---|
| Small (screen height ≤ 667 pt, e.g. SE) | | 52 |
| Standard (668–900 pt) | | 54 |
| Large (> 900 pt, Pro Max / Plus) | | 56 |
| Landscape (any iPhone) | | 40 |

With a 44 pt toolbar this gives about 268 pt total in portrait, close to the system keyboard with its suggestion bar.

#### 6.3.3 Clamps

- `rowHeight` within §6.1.3 ranges.
- `totalHeight ≤ 0.60 × screenHeight` (portrait) or `≤ 0.70 × screenHeight` (landscape). If exceeded, reduce `bottomLift` first, then `rowHeight`.
- One-handed content width ≥ 240 pt.

#### 6.3.4 Installing the height (Phase 0 validates, Phase 4 finalizes)

```swift
// KeyboardViewController
private var heightConstraint: NSLayoutConstraint?

override func viewDidLoad() {
    super.viewDidLoad()
    inputView?.allowsSelfSizing = true
    // add KeyboardRootView pinned to all edges …
}

override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    applyHeight(heightCoordinator.currentHeight())
}

func applyHeight(_ h: CGFloat) {
    if let c = heightConstraint { c.constant = h; return }
    let c = view.heightAnchor.constraint(equalToConstant: h)
    c.priority = UILayoutPriority(999)   // below "required" so it never fights UIView-Encapsulated-Layout-Height
    c.isActive = true
    heightConstraint = c
}
```

- Update the height when settings, page (row count), toolbar visibility or orientation change (`viewWillTransition(to:with:)` and `traitCollectionDidChange` / trait registration), and during resize dragging.
- **Orientation:** on iPhone, landscape ⇔ `traitCollection.verticalSizeClass == .compact`.
- **Reference implementation:** the public-domain *Clip* keyboard (`rileytestut/Clip`, `ClipBoard/KeyboardViewController.swift`) uses `allowsSelfSizing` + its own height constraint. If priority 999 causes jumps or conflicts on some iOS version, try Clip's variant and record which one works in the Decision log.

#### 6.3.5 Hit areas

- Each key's **hit rect** is its visual rect expanded to fill half of every adjacent gap. The first and last keys extend to the view edges, and rows extend vertically across gaps. No dead zones.
- A touch outside all hit rects (e.g. in a spacer) maps to the **nearest key center in the same row**.
- Optional `touchYOffset` (hidden, default −2 pt): people tend to hit slightly below the center.

#### 6.3.6 One-handed mode

- The key area width is `oneHandedWidthRatio × viewWidth`, aligned left or right.
- The free side holds a **side panel** (min 44 pt wide) with vertical buttons: ⇆ switch side · ⤢ exit one-handed · 📋 clipboard · ◀ ▶ cursor (hold to repeat).
- `LayoutEngine` receives a `contentRect`; everything else is unchanged.

#### 6.3.7 Resize mode (live drag)

- **Entry:** toolbar resize icon, or the "Resize visually" button in Quick Settings. Typing is disabled while resizing.
- **Overlay:** an outline of the key area with handles:
  - **Top handle** → `rowHeight` = (initialKeysHeight − dy) / rows, clamped.
  - **Bottom handle** → `bottomLift`.
  - **Left/right edges** → dragging an edge inward turns on one-handed mode on the **opposite** side and sets the width ratio.
  - **Center drag** (one-handed only) → switch side (snaps).
- **Controls:** preset chips S (0.88×), M (1.0×), L (1.12×), XL (1.25×) of the device default · live readout ("Row 54 pt · Lift 0 · Width 100%") · **Reset** · **Done**.
- **Live updates** are throttled to 30 Hz (coalesce drag events and apply the latest value on a `CADisplayLink` tick). A light haptic tick fires when crossing the default size (snap zone ± 3 pt).
- **Done** saves to the current orientation's profile. Rotation during resize mode cancels it.
- **Safety:** "Reset size" is always reachable (Quick Settings and the app), in case a user makes the keyboard unusable.

---

### 6.4 Input behavior

#### 6.4.1 Key actions

```swift
public enum KeyAction: Equatable, Sendable {
    case character(String)          // insert text (already case-mapped)
    case zwnj                       // U+200C
    case space
    case backspace                  // one step (touch-down, then repeat)
    case deleteWordBackward
    case returnKey
    case shift, capsLock
    case page(KeyboardPage)
    case nextLanguage
    case nextInputMode              // globe tap (controller calls advanceToNextInputMode)
    case openPanel(Panel)           // .clipboard, .emoji, .edit, .quickSettings, .resize
    case moveCursor(Int)            // logical characters; + = forward
    case moveCursorWord(Direction), moveCursorLine(Direction)
    case insertSuggestion(Suggestion)
    case insertClip(ClipID)
    case copySelection, cutSelection, pasteClipboard
    case undo
    case dismissKeyboard
}
```

#### 6.4.2 `InputProcessor` contract

```swift
@MainActor public final class InputProcessor {
    public init(settings: InputSettings, clock: Clock)
    public func handle(_ action: KeyAction, in doc: TextDocument) -> [InputEffect]
    public func textDidChange(in doc: TextDocument) -> [InputEffect]   // host changed text or cursor
    public var context: TypingContext { get }                          // prefix, previous words, sentence start…
}
public enum InputEffect: Equatable {
    case shiftChanged(ShiftState), pageChanged(KeyboardPage), languageChanged(LanguageID)
    case requestSuggestions, feedback(FeedbackKind)
    case learn(CommitEvent), autocorrected(Autocorrection)
    case openPanel(Panel), nextInputMode, dismissKeyboard, toast(ToastKind)
}
```

`TextDocument` is the only way to reach the host text (§6.4.8). Everything here is unit-tested with `MockTextDocument`.

#### 6.4.3 Shift, caps lock and auto-capitalization (English)

- **States:** `off` → tap → `oneShot` (next letter uppercase, then `off`) → a second tap within 300 ms → `capsLock` → tap → `off`.
- **Auto-cap** sets `oneShot(auto: true)` when `autoCapitalize` is on and the field's `autocapitalizationType` allows it:
  - `.sentences`: at the start of the text, after `. ! ?` + space, after a newline.
  - `.words`: after any space.
  - `.allCharacters`: behaves like caps lock.
  - `.none`: never.
- Auto-cap is recomputed after every action and on `textDidChange`.
- Persian has no case: the shift key is hidden on Persian pages.

#### 6.4.4 Space, double-space period, smart punctuation

- **Space tap:** insert `" "`. If autocorrect mode is `.auto`, first run the autocorrect decision (§6.7.9). Then emit `learn` for the committed word.
- **Double-space period:** if the previous action was a space key tap within 0.6 s, the text before the cursor ends with `<letter or digit>" "`, and `doubleSpacePeriod` is on → replace `" "` with `". "`. Same character for Persian.
- **Smart punctuation spacing:** after the keyboard auto-inserts a space (suggestion accept, clip insert, autocorrect), typing one of `. , ! ? ; : ، ؛ ؟ ) » …` removes that auto space first. The flag `autoSpacePending` is cleared by any other action.
- **Space-bar trackpad** (`spaceTrackpad == .drag`): after > 8 pt horizontal movement, enter cursor mode. Every `8 / cursorSpeed` pt moves the cursor by one character. Key labels fade out while dragging. With `rtlVisualCursor`, if the strong character next to the cursor is RTL (U+0590–U+08FF, U+FB1D–U+FDFF, U+FE70–U+FEFF), invert the direction so dragging left moves the cursor visually left.
  - `.longPress` variant: enter cursor mode after `longPressDelayMs` without moving.
  - With `languageSwitch == .spaceSwipe`, a quick horizontal flick switches language. That only works when the trackpad is `.longPress`; the app enforces this combination.

#### 6.4.5 ZWNJ (نیم‌فاصله) rules

- The ZWNJ key inserts U+200C.
- Ignore it at the start of a word, right after a space, or right after another ZWNJ.
- Space right after a ZWNJ replaces the ZWNJ with a space (the user changed their mind).
- ZWNJ counts as a **word character** (a word like می‌خوام is one word).
- Canonical ZWNJ spelling comes from suggestions (`preferZWNJForms`), not from guessing while typing.

#### 6.4.6 Backspace

- **Tap:** if the previous action was an autocorrection and nothing changed since, **revert** it (restore the typed word and the separator) and emit `learn(.revertedAutocorrect)`. Otherwise `deleteBackward()` once.
- **Hold:** first repeat after 500 ms. Then every 80 ms (normal; slow 120 ms, fast 50 ms). After 2 s, switch to deleting whole words every 200 ms.
- **Swipe left from backspace** (`backspaceSwipeDeletesWords`): every 24 pt of leftward movement deletes one more word. Moving back right re-inserts the most recently deleted words (kept in a local buffer). Lifting the finger commits.
- **Word boundary** for deletion: skip trailing spaces, then delete back to the previous non-word character (§6.6.3).

#### 6.4.7 Globe and language keys

- **Globe** (only if `needsInputModeSwitchKey`): implemented as a `UIControl`/`UIButton` placed over the globe key's frame inside `KeyGridView`, with
  `addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)`.
  This gives the system its tap (next keyboard) and long-press (keyboard list) behavior.
- **Language key** (`فا` / `EN`): tap switches to the next enabled language. It updates `primaryLanguage` (`"fa-IR"` / `"en-US"`), the space label, the prediction language and the page (letters), and saves the last language.
- **Forced English:** in `.asciiCapable`, `.emailAddress` and `.URL` fields. The previous language comes back when the field changes.

#### 6.4.8 `TextDocument`, context and word replacement

```swift
@MainActor public protocol TextDocument: AnyObject {
    var contextBefore: String? { get }        // documentContextBeforeInput
    var contextAfter: String? { get }         // documentContextAfterInput
    var selectedText: String? { get }
    var hasText: Bool { get }
    var traits: FieldTraits { get }           // our own enums, no UIKit
    var documentIdentifier: UUID { get }
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
}
```

- **`ProxyTextDocument`** (keyboard target) wraps `UITextDocumentProxy`.
- **`MockTextDocument`** (tests) models a buffer + cursor + selection, with switches that imitate real hosts:
  - context limited to the current paragraph or N characters;
  - `nil` context;
  - delayed context after cursor moves;
  - grapheme deletion mode (per cluster or per scalar for combining marks).
- **`TypingContext`**, derived after every action and on `textDidChange`:
  - `prefix`: word characters directly before the cursor;
  - `suffix`: word characters directly after the cursor. If it's not empty, suggestions are disabled (v1);
  - `previousWords`: up to 2 words in the same sentence (stop at `. ! ? ؟ … \n`), else `<s>`;
  - `isSentenceStart`, `language`, `traits`.
- **Shadow buffer:** the last 200 characters the keyboard inserted in this document. Used when `contextBefore` is `nil`. Reset on `documentIdentifier` change or when a `textDidChange` shows the text no longer ends with what we expect (external edit or cursor jump).
- **Replacing the current word** (suggestion accept, autocorrect):
  1. `n = prefix.count` (Swift grapheme count).
  2. `deleteBackward()` × n.
  3. Verify that `contextBefore` no longer ends with any part of the prefix. If a combining mark or ZWNJ was left behind (some hosts delete per scalar), delete the leftovers (bounded: at most 4 extra calls).
  4. `insertText(replacement + " ")` and set `autoSpacePending = true`.
- **Device check in Phase 3 (task 3.16):** measure how real hosts delete `می‌خوام`, `بَ`, `👍🏽` and a ZWNJ word, and write the results in PROGRESS.md.

#### 6.4.9 Edit operations (used by the edit panel, Phase 5)

| Operation | Implementation | Notes |
|---|---|---|
| ◀ / ▶ character | `adjustTextPosition(±1)`; inverted when `rtlVisualCursor` and the text around the cursor is RTL | Hold = repeat (same timing as backspace) |
| Word left / right | Compute the distance to the previous/next word boundary from the context, then `adjustTextPosition(±n)` | Uses §6.6.3 word characters |
| Line start / end | Distance to the previous/next `\n` in the context (or its start/end if none) | Limited by the context the host gives |
| Copy | `selectedText` → `PasteboardClient.setString`; update `lastSeenChangeCount`; store the clip with source `.keyboard` | Disabled without Full Access or without a selection |
| Cut | Copy, then `deleteBackward()` once (deletes the selection) | Same |
| Paste | Read the pasteboard string (user-initiated) → `insertText` | Without Full Access: disabled with an explanation |
| Delete word | `deleteWordBackward` | |
| Undo | Keyboard-level undo stack (max 20): the keyboard's own insertions, suggestion accepts, autocorrects, word deletions, clip inserts | Cleared on `documentIdentifier` change or external edit |
| Select All | **Not possible** for third-party keyboards (C5) | Show an info tooltip instead |

#### 6.4.10 Return key

| `returnKeyType` | English label | Persian label | Style |
|---|---|---|---|
| `.default` | return (↵ icon) | ↵ icon | normal |
| `.go` | go | برو | accent |
| `.google`, `.yahoo`, `.search` | search | جستجو | accent |
| `.join` | join | پیوستن | accent |
| `.next` | next | بعدی | normal |
| `.route` | route | مسیر | accent |
| `.send` | send | ارسال | accent |
| `.done` | done | انجام | accent |
| `.emergencyCall` | emergency | اضطراری | accent |
| `.continue` | continue | ادامه | accent |

If `enablesReturnKeyAutomatically` is true and `hasText` is false, the key looks disabled (it still inserts `\n`, like iOS). Labels come from String Catalogs.

#### 6.4.11 Field traits

- Read on `viewWillAppear` and every `textDidChange` / `textWillChange`: `keyboardType`, `returnKeyType`, `keyboardAppearance`, `autocapitalizationType`, `autocorrectionType`, `spellCheckingType`, `textContentType`, `enablesReturnKeyAutomatically`.
- **Page selection:** `.numberPad` / `.decimalPad` / `.asciiCapableNumberPad` → numpad. `.numbersAndPunctuation` → `symbols1`.
- **Sensitive field** (learning off, clip chip shows masked items only):
  - `textContentType ∈ {.password, .newPassword, .oneTimeCode, .creditCardNumber, .username}`;
  - or `autocorrectionType == .no` (URL, email and username fields usually set this).

#### 6.4.12 Touch tracking (`KeyTouchTracker`)

Pure logic, fed with `(touchID, point, timestamp, phase)` so it is unit-testable without UIKit:

```text
            touchDown on key K
                   │
       ┌───────────┴──────────────────────────────────────┐
  K is character/space/return                       K is backspace
       │                                                  │
  state = pressed(K) ── moved > 8pt on space ──► trackpad(accum)   deleteBackward at down,
       │  └─ held ≥ longPressDelay & K has alternates ──► alternates(K, sel)   then repeat/word/swipe
       │
  touchUp ─► commit(K) (or selected alternate, or end trackpad)
  new touchDown on another key while pressed(K) ─► commit(K) immediately (rollover), then track the new key
  touchCancelled ─► discard (no commit)
```

- Character keys commit on **touch up** (like iOS). Backspace and shift act on **touch down**.
- Key highlight and popup appear on touch down. The haptic/sound fires on touch down.
- `isMultipleTouchEnabled = true`. Each `UITouch` has its own tracker.

---
### 6.5 Clipboard

#### 6.5.1 Ways a clip gets in

| Source | When | Needs |
|---|---|---|
| `capture` | Keyboard appears, or while it's visible, and `changeCount` changed (§6.5.2) | Full Access |
| `keyboard` | Copy/Cut in the edit panel | Full Access |
| `app` | Companion app "Paste" button (`UIPasteControl`, no prompt) or manual add | — |
| `share` | Share Extension (Phase 10) | — |
| `intent` | Shortcuts action "Save to Kelid" (Phase 10). With **Back Tap** (Settings → Accessibility → Touch → Back Tap) this becomes a two-tap capture from anywhere. | — |

#### 6.5.2 Monitor algorithm (`ClipboardMonitor`, MainActor)

```text
on viewWillAppear, NSExtensionHostWillEnterForeground, and every 1 s while visible (if pollWhileVisible):
    guard fullAccess && clipboard.enabled && captureMode != .off && !incognito
    let cc = pasteboard.changeCount                      // metadata: no banner, no prompt
    guard cc != lastSeenChangeCount                      // persisted in local UserDefaults
    lastSeenChangeCount = cc                             // any change (also a decrease after reboot) counts
    let types = pasteboard.types                         // metadata
    if skipSensitive && types ∩ SENSITIVE_TYPES ≠ ∅ → return
    switch captureMode:
      .auto  → content = read(types)   // string / url / image; may show the "pasted from" banner
               classify → store → show chip
      .onTap → chip = .pending          // chip says "📋 Paste copied item"; reading happens on tap (user-initiated)
```

- After the keyboard writes to the pasteboard itself (Copy/Cut, image-clip tap), set `lastSeenChangeCount = pasteboard.changeCount` right away, so the same content isn't captured twice.
- The timer is invalidated in `viewWillDisappear`. No timers run while hidden.

#### 6.5.3 Classification (`ClipClassifier`)

1. **Sensitive pasteboard types** (skip when `skipSensitive`): `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`, `com.agilebits.onepassword`, and any type containing `password` (case-insensitive).
2. **Empty or whitespace-only** → skip. Text longer than 100 000 characters → store the first 100 000 and mark it truncated.
3. **OTP** `^\s*[0-9۰-۹٠-٩]{4,8}\s*$` → `otpHandling`: `.skip` → skip; `.expire` → `isSensitive = true`, `expiresAt = now + 120 s`; `.keep` → normal.
4. **Password-like** (`maskPasswordLike`): a single token of 8–64 characters, no spaces, with at least 3 of {lowercase, uppercase, digit, symbol}, and not a URL → `isSensitive = true`, `expiresAt = now + 600 s`. Shown masked (`••••••`); long-press reveals it.
5. **`ignorePatterns`** match → skip.
6. **URL** (`NSDataDetector` link, or `hasURLs`) → `kind = .url`.
7. **Image** (`hasImages` and `captureImages`) → `kind = .image` (§6.5.8).
8. `contentHash` = SHA-256 of `PersianText.canonical(text)` (text/url) or of the downsampled JPEG bytes (image).

#### 6.5.4 Storage rules

- **Dedupe:** a clip with an existing `contentHash` updates `lastCopiedAt = now` and `copyCount += 1` (it moves to the top), instead of inserting a new row.
- **Limits:** after each insert, and on appear (at most once per 10 min), delete: expired rows (`expiresAt < now`), rows older than `retentionDays`, then the oldest non-pinned rows beyond `maxItems`. Pinned rows and snippets are never auto-deleted. Deleting an image clip also deletes its files.
- Every write posts the Darwin notification `.clips.changed`.

#### 6.5.5 Inserting a clip

- `tapAction == .insert` → `insertText(clip.text)`. With `smartSpacing`: if the character before the cursor is a word character and the clip starts with one, insert `" "` first.
- `.insertAndClose` → insert, then return to the keys.
- `.copy` → copy to the system pasteboard only (updates `lastSeenChangeCount`).
- Updates `lastUsedAt` and `useCount`. **Pasted text is never learned** by the personal model.

#### 6.5.6 Clipboard panel (in the keyboard)

```text
┌────────────────────────────────────────────────────────────┐
│ [ABC]  Recent | Pinned | Snippets     🔍   ⏸   🗑          │  ← header (replaces toolbar row)
├────────────────────────────────────────────────────────────┤
│ 📌 Home address: Tehran, Vali-Asr St. …            · 2d    │
│ 🔗 https://github.com/groue/GRDB.swift             · 5m    │
│ سلام، فردا ساعت ۱۰ جلسه داریم …                    · 12m   │
│ 🖼 [thumb] Image 1170×2532                          · 1h    │
│ •••••• (sensitive, tap to paste · long-press to reveal)    │
│ …  (lazy list, pages of 50)                                │
└────────────────────────────────────────────────────────────┘
```

- **Same height as the keyboard** (§6.3.1).
- **Row:** 2-line preview with natural alignment (RTL if the first strong character is RTL), relative time ("5m" / "۵ دقیقه"), and icons for pinned, link, image and sensitive.
- **Tap** → §6.5.5. **Long-press** → menu: Pin/Unpin · Copy · Delete · Reveal (sensitive) · Save as snippet (Phase 10). **Swipe left** → delete, with an "Undo" toast for 4 s.
- **Header:** ⏸ pauses capture (sets `captureMode = .off`, with a visible indicator); 🗑 clears everything except pinned (asks for confirmation).
- **Search sub-mode** (🔍): the keyboard temporarily grows by 88 pt and shows `[search field][✕]`, a horizontal strip of result chips, and the letter keys below. Key presses go to `searchQuery` through `InternalInputRouter` instead of the host app. Matching: `searchKey LIKE %q%` (§6.6.4). ✕ or ABC ends the search and restores the height. Emoji search (Phase 12) reuses the same router.
- **Empty states:**
  - no Full Access → numbered steps (Settings → General → Keyboard → Keyboards → Kelid → Allow Full Access) and the privacy promise;
  - empty history → "Copy something and it appears here";
  - capture paused → a button to resume.
- **Performance:** paged fetches (50 rows), `LazyVStack`, thumbnails loaded asynchronously and cached (≤ 40 thumbnails).

#### 6.5.7 Clip chip

- After a capture (or a pending clip in `.onTap` mode), the suggestion strip shows `📋 <first 24 characters>…` at the leading edge for `chipSeconds`, until the user types, or until ✕ is tapped.
- Tap → insert (or read-then-insert in `.onTap` mode). Sensitive clips show `📋 ••••` and still paste on tap, which makes OTP entry one tap.
- The chip is never shown when clipboard is disabled or in incognito mode.

#### 6.5.8 Image clips

- Downsample with ImageIO (`CGImageSourceCreateThumbnailAtIndex`) to ≤ 1024 px on the longest side: JPEG at quality 0.8, or PNG if the image has alpha. Thumbnail: 160 px. Both are written to `Clips/` in the App Group. Skip if the original is larger than 25 MB.
- All image work runs **off the main thread**. The full-size `UIImage` is never kept.
- **Tap** → write the image to the system pasteboard, then show the toast "Image copied: long-press the text field and choose Paste". Keyboards can't insert images (C4).

---

### 6.6 Persian text processing

Everything here lives in the `PersianText` module (pure Swift, heavily unit-tested). The Python pipeline (Phase 6) must use **the same rules**. Keep a shared test-vector file, `Packages/KelidKit/Tests/PersianTextTests/vectors.json`, and have both Swift and Python tests read it.

#### 6.6.1 Character inventory

- **Persian letters (32):** ا ب پ ت ث ج چ ح خ د ذ ر ز ژ س ش ص ض ط ظ ع غ ف ق ک گ ل م ن و ه ی
- **Variants:** آ أ إ ٱ ء ؤ ئ ۀ ة ي ى ك ھ
- **Diacritics:** U+064B–U+065F, U+0670
- **Tatweel:** U+0640
- **ZWNJ:** U+200C · **ZWJ:** U+200D
- **Persian digits:** U+06F0–U+06F9 · **Arabic-Indic digits:** U+0660–U+0669
- **Punctuation:** ، (U+060C) ؛ (U+061B) ؟ (U+061F) « » ٪ (U+066A) ٫ (U+066B) ٬ (U+066C) ﷼ (U+FDFC)

#### 6.6.2 `canonical(_:)`: used for storage, dedupe and model output

| From | To |
|---|---|
| ي (U+064A), ى (U+0649) | ی (U+06CC) |
| ك (U+0643) | ک (U+06A9) |
| Arabic-Indic digits ٠–٩ | Persian digits ۰–۹ (Persian context only) |
| Tatweel ـ | removed |
| Repeated ZWNJ, ZWNJ at word start or end, ZWNJ next to a space | removed |
| ZWJ between Persian letters | removed |
| NBSP, other spaces | normal space (pipeline only; the keyboard never rewrites user text) |

The keyboard only uses `canonical` on **its own output** (suggestions) and for **keys and hashes**. It never silently rewrites what the user typed.

#### 6.6.3 Word characters and tokenization

- **Word character:** Unicode letters (L\*), marks (M\*), decimal digits (Nd), ZWNJ, ZWJ. Apostrophes `'` `’` count only between letters (English contractions).
- **Sentence boundary:** `. ! ? ؟ … \n`
- **Token classes:** word, number (`<num>` in the pipeline), URL/email (`<url>` in the pipeline), punctuation, emoji.

#### 6.6.4 Match key and search key

`matchKey(_:)` is used for trie lookups and matching. It is **lossy on purpose**:

1. Apply `canonical`.
2. Remove diacritics (U+064B–U+065F, U+0670), ZWNJ and ZWJ.
3. آ أ إ ٱ → ا · ؤ → و · ئ → ی · ۀ / هٔ / ة → ه
4. Latin lowercase; `’` → `'`
5. All digits → ASCII digits

`searchKey(_:)` = `matchKey` + collapse whitespace + (Latin) remove accents (`folding(.diacriticInsensitive)`). It is used for clipboard, snippet and emoji search.

#### 6.6.5 Direction detection

`dominantDirection(_:)` returns the direction of the first strong character: RTL for U+0590–U+08FF, U+FB1D–U+FDFF, U+FE70–U+FEFF; LTR for other letters; neutral otherwise. It is used for clip-row alignment and RTL-aware cursor movement.

#### 6.6.6 Persian confusion groups (typo costs, §6.7.3)

| Group | Substitution cost |
|---|---|
| ا ↔ آ | 0.2 |
| ی ↔ ئ | 0.3 |
| و ↔ ؤ | 0.3 |
| ت ↔ ط | 0.4 |
| س ↔ ص ↔ ث | 0.4 |
| ز ↔ ذ ↔ ض ↔ ظ | 0.4 |
| ه ↔ ح | 0.5 |
| ق ↔ غ | 0.4 |
| ا ↔ ع | 0.6 |

#### 6.6.7 Test vectors (minimum set)

| Input | `canonical` | `matchKey` |
|---|---|---|
| كتاب | کتاب | کتاب |
| يك | یک | یک |
| می‌خواهم | می‌خواهم | میخواهم |
| میخواهم | میخواهم | میخواهم |
| کتاب‌ها | کتاب‌ها | کتابها |
| آب | آب | اب |
| خانهٔ | خانهٔ | خانه |
| خانۀ | خانۀ | خانه |
| سلامـــ | سلام | سلام |
| بِسمِ | بِسمِ | بسم |
| ١٢٣ | ۱۲۳ | 123 |
| Hello | Hello | hello |
| don’t | don’t | don't |
| ‌سلام‌ (ZWNJ on both ends) | سلام | سلام |

---

### 6.7 Prediction and learning

#### 6.7.1 Overview

```text
TypingContext ──► SuggestionService (actor)
                     ├─ LanguageModel[lang]  (KLM file, mmap, read-only, process-wide)
                     │     ├─ Lexicon + trie: completions, fuzzy search
                     │     └─ n-gram tables: next-word, context scores
                     ├─ UserModel[lang] (actor): personal words and n-grams, blocklists
                     ├─ ProximityMap (from the current layout geometry)
                     ├─ EmojiSuggester (keyword → emoji)
                     └─ Ranker(RankerConfig) ─► SuggestionResult { verbatim, items[], autocorrect?, emoji? }
```

#### 6.7.2 KLM binary format (v1)

Little-endian. Every section starts at an 8-byte-aligned offset. The file is opened with `mmap(PROT_READ, MAP_PRIVATE)` and never copied into heap.

```text
Header (64 bytes)
  0  magic          [4]  "KLM1"
  4  formatVersion  u16  1
  6  flags          u16  bit0 hasBigrams, bit1 hasTrigrams
  8  language       [8]  ASCII, zero-padded ("fa", "en")
 16  wordCount      u32
 20  nodeCount      u32
 24  sectionCount   u32
 28  reserved       u32
 32  buildUnixTime  u64
 40  uniMinLog10    f32   dequantization ranges (see below)
 44  biMinLog10     f32
 48  triMinLog10    f32
 52  reserved       [12]
Section directory at offset 64: sectionCount × { tag u32 (FourCC), reserved u32, offset u64, length u64 }

WSTR  UTF-8 surface forms, concatenated
WOFF  u32 × (wordCount+1)  start offset of word i in WSTR (last entry = total length)
WSCR  u8  × wordCount      quantized unigram log10 P (255 = most likely). Word IDs are sorted by
                           descending frequency, so ID 0 is the most frequent word.
WFLG  u8  × wordCount      bit0 offensive, bit1 containsZWNJ
TNOD  12-byte nodes; node 0 = root
        firstChild u32 (0xFFFFFFFF = leaf) · label u16 (UTF-16 unit of the match-key char)
        childCount u8 · maxScore u8 (max WSCR in the subtree) · termList u32 (byte offset in TTRM or 0xFFFFFFFF)
      Children are contiguous and sorted by label.
TTRM  terminal lists: count u8, then count × u32 word IDs (all surface forms sharing this match key,
      best first), e.g. key "میخوام" → [می‌خوام, میخوام]
BIDX  sorted by ctx: { ctx u32, start u32, count u16, pad u16 }           (12 bytes)
BENT  { next u32, score u8, pad[3] }                                      (8 bytes, per context sorted by score)
TIDX  sorted by (ctx1, ctx2): { ctx1 u32, ctx2 u32, start u32, count u16, pad u16 }  (16 bytes)
TENT  same layout as BENT
```

- **Quantization:** `q = round(255 × (log10P − minLog) / (−minLog))`; `log10P = minLog × (1 − q/255)`. Defaults: `uniMinLog10 = −8`, `biMinLog10 = −6`, `triMinLog10 = −6`.
- **Builder caps** (flags of `klm build`): `--max-words 200000` (fa) / `120000` (en), `--max-bigram-entries 1500000`, `--max-trigram-entries 1000000`, per-context top-K = 32 (bigram) / 16 (trigram). Bigram minimum count 3, trigram minimum count 3, trigram contexts only if `c(w1 w2) ≥ 10`.
- **Size targets:** `fa.klm` ≤ 30 MB, `en.klm` ≤ 25 MB.
- **Validation on open:** magic, version, section bounds, and `WOFF` monotonicity (cheap). CRC checks only in debug builds.
- **Surface → word ID:** `matchKey(surface)` → walk the trie → terminal list → the ID whose surface equals `canonical(surface)`, else the first ID.

#### 6.7.3 Lookup algorithms

- **Completions** `completions(prefixKey, limit: 20)`: walk the trie to the prefix node (binary search over children labels), then **best-first search** with a max-heap ordered by `maxScore` (swift-collections `Heap`). Stop when `limit` terminals are collected and the heap top's `maxScore` is below the worst collected score.
- **Fuzzy** `fuzzy(typedKey, maxCost, prefixMode)`: DFS over the trie carrying a **weighted Damerau–Levenshtein** DP row.
  - Substitution cost: 0 if equal; the Persian group cost (§6.6.6); 0.6 if the keys are adjacent in the `ProximityMap`; else 1.0.
  - Insertion/deletion 1.0 (deleting a doubled letter 0.5). Transposition 0.8.
  - Prune when `min(row) > maxCost`. `maxCost` = 1.0 if `|typed| ≤ 3`, else 2.0.
  - `prefixMode`: when `row[|typed|] ≤ maxCost` at a node, also take its best completions at that cost plus a completion penalty.
  - Visit children in `maxScore` order. **Budget: 30 000 node visits.**
- **Next words** `nextWords(w1?, w2)`: candidates = trigram entries (w1, w2) ∪ bigram entries (w2) ∪ top-20 unigrams. **Stupid Backoff:**
  `S(w|w1,w2) = P_tri` if present, else `0.4 × P_bi` if present, else `0.16 × P_uni`. Log domain: `log10 S = log10 P + k·log10(0.4)`.
- **Context-aware completion candidates:** trie completions ∪ fuzzy results ∪ (next-word candidates whose match key starts with the typed key) ∪ user-model candidates. The third set is what makes a rare but contextually likely word appear from its first letter.

#### 6.7.4 `SuggestionService` API

```swift
public actor SuggestionService {
    public func load(languages: [LanguageID], resources: ModelLocator) async throws
    public func suggest(_ request: SuggestionRequest) async -> SuggestionResult?   // nil = superseded
    public func learn(_ event: CommitEvent) async
    public func updateLayout(_ proximity: ProximityMap, for language: LanguageID)
}
public struct SuggestionRequest: Sendable {
    let generation: Int                   // monotonically increasing; stale requests return nil
    let context: TypingContext            // prefix, previousWords, isSentenceStart, language, traits
    let settings: PredictionSettings      // resolved for the language
    let incognito: Bool
}
public struct SuggestionResult: Sendable, Equatable {
    var verbatim: Suggestion?             // the typed word (quoted if unknown)
    var items: [Suggestion]               // ranked, deduplicated, ≤ suggestionCount
    var autocorrect: Suggestion?          // candidate that will replace on space (auto mode)
    var emoji: [String]                   // 0–2 emoji for the compact trailing slot
}
```

The main actor sends a request after each keystroke (no debounce; stale results are dropped). It renders the result only if `generation == latestGeneration`.

#### 6.7.5 Scoring and ranking

For a typed key `t` and a candidate `w`:

```text
S_lang(w|ctx) = Stupid Backoff from the KLM (§6.7.3)
S_user(w|ctx) = Stupid Backoff from the UserModel (§6.7.6)
S(w|ctx)      = λ·S_user + (1 − λ)·S_lang        λ from the source mode (§6.7.7)
channel(t|w)  = 10^(−γ · editCost(t, k(w)))       γ = 1.2; editCost = 0 for exact prefix matches
completion    = 10^(−0.05 · min(|k(w)| − |t|, 6)) mild preference for shorter completions
score(w)      = log10 S + log10 channel + log10 completion + (0.15 if k(w) == t)
```

- **Tie-break:** lower word ID (more frequent). All constants live in `RankerConfig` and are tuned in Phase 8 with the eval harness (§6.7.12).
- **Blocked words** (user blocklist, offensive when `blockOffensive`) are removed from the result.
- **Dedupe** by `canonical(surface)`. With `preferZWNJForms`, the ZWNJ spelling wins over the joined spelling when both appear.
- **Slots** (3 by default; mirrored automatically in RTL because they're laid out by `leading`/`trailing`):
  - leading = **verbatim** (the typed text; in “quotes” if it isn't a known word);
  - center = **best** (bold when it's the autocorrect candidate);
  - trailing = second best.
  - If best == verbatim: [verbatim(bold), 2nd, 3rd].
  - Empty prefix → 3 next-word predictions.
  - Emoji (if any) get a compact 44 pt slot at the far trailing edge.
- **English casing:** if the typed text starts uppercase (or it's a sentence start with auto-cap), capitalize the candidate. If the typed text is all caps (≥ 2 letters), uppercase it.

#### 6.7.6 `UserModel` (personal model)

- **Per language, in memory:**
  - interned surfaces → `UInt32` IDs;
  - `WordStat { count: Float, lastUsed: Float (days since 2020-01-01) }`;
  - a **sorted array of (matchKey, id)** for prefix scans (binary search, scan ≤ 200);
  - bigrams `[UInt64 (id1<<32|id2): NgramStat]`, trigrams `[TripleKey: NgramStat]`;
  - `blockedWords`, `blockedCorrections` (pairs).
- **In-memory caps:** 20 000 words, 30 000 bigrams, 30 000 trigrams (most recent and frequent), for ≤ 6 MB. The database may hold up to `maxUserWords`.
- **Decay:** `eff(count, lastUsed) = count × 0.5^((now − lastUsed) / halfLifeDays)`. On update: `count = eff + increment; lastUsed = now`.
- **Increments:** typed and committed 1.0 · accepted suggestion 1.0 · tapped verbatim 2.0 · original word after an autocorrect revert 2.0 · "learn from text" import 0.5 per occurrence (max 10 per word).
- **Probabilities:**
  - `P_uni(w) = eff(w) / (Σ eff + 50)`
  - `P_bi(w|w1) = eff(w1,w) / (eff(w1) + 5)`
  - `P_tri(w|w1,w2) = eff(w1,w2,w) / (eff(w1,w2) + 3)`
  - `S_user` = Stupid Backoff over these.
- **Persistence (write-behind):** increments collect in a dirty set and flush every 5 s, on `viewWillDisappear`, and on host background, as **one transaction** of UPSERTs (DDL in §6.11.3).
- **Load** asynchronously on first use. Until loaded, run as `.languageOnly`.
- **Reload** on `.userdict.changed`.
- **Prune** when the database row count is above `maxUserWords`: delete the lowest `eff` rows (never user-added words).

#### 6.7.7 Prediction source modes (per language)

| Mode | Candidates from | λ | Learning continues? |
|---|---|---|---|
| **Off** | none (only the clip chip and toolbar are shown) | — | yes (if `learning.enabled`) |
| **Personal only** | UserModel only: words with `eff ≥ newWordThreshold`, plus user n-grams. Fuzzy search runs over user words (small trie built on load). | 1.0 | yes |
| **Language only** | KLM only | 0.0 | yes |
| **Hybrid** (default) | both | `personalWeight` (default 0.6) | yes |

Blocklists apply in every mode. With very little personal data, Personal-only shows a hint ("Kelid is still learning your words").

#### 6.7.8 Learning rules and privacy

- **Commit triggers:** space, punctuation, return, suggestion accept, autocorrect (the final word), verbatim tap.
- **Never learn** when:
  - `learning.enabled == false`, or incognito, or the field is sensitive (§6.4.11);
  - the text was pasted or inserted from a clip or snippet;
  - the token is > 32 graphemes, contains digits, looks like a URL or email, is emoji-only, mixes Persian and Latin letters, or has 3+ identical letters in a row (e.g. خیلیییی).
- **New words** (not in the KLM) are stored right away but only suggested after `eff ≥ newWordThreshold`. This keeps one-off typos out of suggestions.
- **N-grams** are learned only inside one sentence, and only when every word in them is learnable.
- **Negative feedback:** long-press a suggestion → *Don't suggest* (block) or *Forget* (delete the word and its n-grams). Reverting an autocorrect adds the pair `(typed → corrected)` to `blockedCorrections`.
- **Supplementary lexicon** (`requestSupplementaryLexicon`, Phase 9): text replacements (`userInput → documentText`) become high-priority suggestions when the typed word equals the shortcut. Contact names (when enabled) become user words with source `contacts` and no decay.

#### 6.7.9 Autocorrect rules

Evaluated on a separator (space, punctuation, return) **only in `.auto` mode**:

1. The field allows it (`autocorrectionType != .no`, not sensitive), prediction is enabled, and the mode is `.auto`.
2. The typed word `t` has ≥ 2 graphemes, no digits, isn't all caps (English), and isn't URL/email-like. `(t → b)` isn't in `blockedCorrections`.
3. `t` is **not a known word**: its KLM score is below `q_min = 20` and it isn't in the user model with `eff ≥ 1`.
4. The best candidate `b` is a correction (`editCost > 0`, `≤ maxCost`) and `score(b) − score(second) ≥ τ`, where `τ = 1.0 − 0.8 × autocorrectStrength` (log10 units).
5. Replace (§6.4.8), then add the separator. Remember `lastAutocorrection = (t, b, separator)`.
6. **Revert:** a backspace right after deletes `b + separator` and inserts `t` (no separator). The verbatim slot shows `t`; learning records the revert.

In `.suggestOnly` mode the best candidate is shown bold in the center slot, but nothing is replaced automatically.

#### 6.7.10 Emoji suggestions

- Built by the pipeline (Phase 6) from Unicode CLDR annotations for `fa` and `en`: `emoji_suggest_<lang>.tsv` (keyword → up to 3 emoji), compiled into a small sorted binary or JSON and loaded lazily.
- Shown when the current prefix (a complete word) or the last committed word matches a keyword by `matchKey`.

#### 6.7.11 Language data pipeline (runs on the Mac, Phase 6)

```text
download ──► extract ──► normalize+tokenize (hazm + §6.6 rules) ──► parquet shards
         ──► DuckDB n-gram counts ──► vocabulary selection + cleaning ──► TSV + meta.json
         ──► `klm build` (Swift) ──► Keyboard/Resources/LM/<lang>.klm
```

| Step | Persian | English |
|---|---|---|
| Corpus (formal) | Persian Wikipedia dump (`fawiki-latest-pages-articles.xml.bz2`, CC BY-SA 4.0) | English Wikipedia sample, capped at ~300 M tokens |
| Corpus (informal) | hermitdave/FrequencyWords `fa_full.txt` (OpenSubtitles 2018, CC BY-SA 4.0), merged with weight `w_informal = 3.0` after per-million normalization | `en_full.txt` (same source) |
| Optional (personal builds only; licenses unclear) | OPUS OpenSubtitles fa monolingual text for informal bigrams/trigrams, `--with-opensubtitles-text` | same |
| Word validity | Lilak word list (Apache-2.0) boosts known-valid spellings. Also evaluate the HeliBoard/AOSP experimental Persian word list (source lists CC BY 4.0) as an extra frequency source. | — |
| Normalization | hazm `Normalizer` (Persian style, diacritics removed, affix spacing / "می" separation) **plus** §6.6.2 rules. Lines with < 50% Persian letters dropped. Numbers → `<num>`, URLs → `<url>`. | Lowercase copy for keys, original case kept for surfaces |
| Tokenization | hazm `sent_tokenize` / `word_tokenize` (ZWNJ words kept whole) | regex tokenizer |
| Counting | DuckDB over parquet (`sentence_id, pos, token`) with `LEAD()` windows → unigram / bigram / trigram counts, `HAVING count ≥ 3` | same |
| Vocabulary | top 200 k valid tokens; offensive words **flagged** (curated `offensive_fa.txt`), not removed | top 120 k |
| Output | `out/fa.unigrams.tsv`, `fa.bigrams.tsv`, `fa.trigrams.tsv`, `fa.meta.json` (sources, dates, licenses, parameters, counts) | same |

- **Quick path** (`make data-quick`, minutes): unigram TSVs from the frequency lists only. That's enough to start Phase 7.
- **Full path** (`make data-full`, hours): everything above.
- **Attribution:** `meta.json` feeds `docs/ATTRIBUTIONS.md`. Derived models are distributed with attribution; CC BY-SA sources mean the derived statistics are shared under CC BY-SA too.

#### 6.7.12 Evaluation harness (`klm eval`)

- **Held-out sets** (built in Phase 6, never used for training): `eval/fa_formal.txt` (5 000 Wikipedia sentences), `eval/fa_informal.txt` (5 000 subtitle-style sentences, if available), `eval/en.txt`.
- **Metrics:**
  - **KSR** (keystroke savings rate): simulate typing with 3 visible suggestions; the "user" taps a suggestion as soon as the intended word appears.
  - **Next-word top-1 / top-3** accuracy.
  - **Correction accuracy:** synthetic typos (adjacent-key substitution, deletion, insertion, transposition, Persian homophones) → % where the intended word is best / in the top 3.
  - **Latency** p50 / p95 per call (macOS numbers are only for comparison; real budgets are measured on device).
- Results go to `PROGRESS.md → Measurements`. Any later change that lowers KSR by more than 1 point needs a Decision-log entry.

---
### 6.8 Themes, fonts, sounds, haptics

#### 6.8.1 Theme file (`*.json`, schema v1)

```json
{
  "schemaVersion": 1,
  "id": "kelid.dark",
  "name": { "en": "Dark", "fa": "تیره" },
  "isDark": true,
  "background": { "type": "color", "color": "#1C1C1E" },
  "keys": {
    "normal":  { "fill": "#3A3A3C", "text": "#FFFFFF", "pressedFill": "#5A5A5E" },
    "special": { "fill": "#2C2C2E", "text": "#FFFFFF", "pressedFill": "#48484A" },
    "accent":  { "fill": "#0A84FF", "text": "#FFFFFF", "pressedFill": "#409CFF" },
    "cornerRadius": 5.0,
    "borderWidth": 0.0,
    "borderColor": "#00000000",
    "shadow": { "color": "#000000", "opacity": 0.35, "radius": 0.0, "offsetY": 1.0 },
    "hintText": "#9A9A9E"
  },
  "fonts": { "persian": "system", "latin": "system", "weight": "regular", "scale": 1.0 },
  "toolbar": { "background": "#00000000", "icon": "#EBEBF5", "suggestionText": "#FFFFFF",
               "divider": "#48484A", "chipFill": "#3A3A3C" },
  "callout": { "fill": "#6C6C70", "text": "#FFFFFF" },
  "panel": { "background": "#1C1C1E", "rowFill": "#2C2C2E", "text": "#FFFFFF",
             "secondaryText": "#8E8E93", "accent": "#0A84FF" }
}
```

- **`background.type`:**
  - `color`;
  - `gradient` (`colors[2–4]`, `angle`);
  - `image` (`file`, `blur` 0–30, `dim` 0–0.8). Blur and dim are **baked into the saved image by the app**, so the keyboard only displays a ready-made image;
  - `material` (`style`: a `UIBlurEffect.Style` name).
- **Colors** are `#RRGGBB` or `#RRGGBBAA`. The validator checks text/fill contrast ≥ 3:1 (a warning, not an error).
- **Built-in themes** ship in the `ThemeKit` resources. Custom themes live in App Group `Themes/<id>.json`, with images in `Themes/Images/<id>.jpg` (≤ screen width × 2 px, ≤ 1.5 MB).

#### 6.8.2 Built-in themes (at least 12)

| ID | Name | Notes |
|---|---|---|
| `kelid.light` / `kelid.dark` | System Light / Dark | Classic iOS look; the default pair |
| `kelid.glass.light` / `kelid.glass.dark` | Glass | Material background, same-color system keys, bolder labels (approximates the iOS 26+ look) |
| `kelid.amoled` | AMOLED Black | Pure black, borderless keys |
| `kelid.nord` | Nord | |
| `kelid.dracula` | Dracula | |
| `kelid.solarized.light` / `.dark` | Solarized | |
| `kelid.isfahan` | Isfahan | Turquoise and lapis tile colors |
| `kelid.saffron` | Saffron | Warm saffron and cream |
| `kelid.pastel` | Pastel | |
| `kelid.contrast` | High Contrast | Accessibility: thick borders, maximum contrast |

#### 6.8.3 Resolution

- `.fixed` → `fixedThemeID`.
- `.followSystem` → `traitCollection.userInterfaceStyle` picks `lightThemeID` / `darkThemeID`.
- `.followApp` → the host's `keyboardAppearance == .dark` → dark theme; otherwise follow the system.
- A missing custom theme falls back to `kelid.light` / `kelid.dark`.
- Resolved on `viewWillAppear`, on `textDidChange` (appearance can change per field), on trait changes, and on `.themes.changed`.

#### 6.8.4 Fonts

- Bundle **Vazirmatn** (OFL-1.1) Regular and Medium, in both the app and the keyboard. Register at process start with `CTFontManagerRegisterFontsForURL(url, .process, nil)`.
- `persianFont = .system` uses SF Arabic (system font). Latin labels use SF by default.
- Label size = base size × `fontScale` (size setting) × theme `fonts.scale`.

#### 6.8.5 Sounds

- **Full Access only.** Play off the main thread.
- **System sounds** via `AudioServicesPlaySystemSound`: character key **1123**, delete **1155**, modifier **1156** (1104 is the older click). **Verify the IDs on device** and record the working values in the Decision log.
- **Custom packs** (`soft`, `typewriter`): small `.caf` files (CC0 or self-made, ≤ 50 KB each) registered once with `AudioServicesCreateSystemSoundID`.
- System sounds follow the ringer volume and the silent switch automatically. Don't use `AVAudioPlayer` (it needs an audio session and keeps decoded buffers in memory).

#### 6.8.6 Haptics

- **Full Access only.** `UIImpactFeedbackGenerator(style:)`, created once per style. `prepare()` on touch-down, `impactOccurred()` on key-down.
- Off when `haptics == .off`, or in Low Power Mode if `reduceHapticsInLowPower` is on.

#### 6.8.7 Theme editor and sharing (companion app)

- Start from any theme → edit colors (`ColorPicker`), corner radius, border, shadow, background (color, gradient, or photo through `PhotosPicker`; blur and dim sliders), fonts, and key-press animation.
- **Live preview** uses `KeyboardPreview` from `KeyboardUI`, so it looks exactly like the real keyboard.
- **Actions:** Save · Duplicate · Delete · Set as light/dark/fixed.
- **Export/import `.kelidtheme`:** JSON with the background image embedded as base64. Declared as an exported UTType `<prefix>.kelid.theme`; opening the file in the app imports it. Export uses `ShareLink`.

---

### 6.9 Emoji

- **Data:** Unicode `emoji-test.txt` (fully-qualified sequences, groups, emoji version) + CLDR `annotations/{fa,en}.xml` and `annotationsDerived` → compiled by the pipeline into `emoji.json`:

  ```json
  [{ "e": "😀", "g": 0, "v": 1.0, "st": false, "fa": ["خنده","صورت"], "en": ["grinning","face"] }]
  ```

  Target ≤ 600 KB. Bundled in the `EmojiData` module.
- **Version filter:** show only emoji the running iOS can render. Keep a table from iOS version to maximum emoji version, and on first run double-check doubtful ones with a glyph test (`CTFontGetGlyphsForCharacters` with Apple Color Emoji).
- **UI:**
  - category bar (Recents, Smileys, People, Animals, Food, Activities, Travel, Objects, Symbols, Flags);
  - horizontally paged `UICollectionView` (compositional layout, cell reuse; memory-safe);
  - bottom bar with `ABC` / `ابپ` and ⌫;
  - long-press → skin-tone picker (the last choice per emoji is remembered).
- **Search:** the 🔍 search sub-mode (§6.5.6) matches the query's `searchKey` against keyword prefixes in the selected `searchLanguages`.
- **Recents:** up to `recentsLimit`, stored in local `UserDefaults` (shared to the App Group when Full Access is on).
- **Memory:** ≤ +12 MB while the panel is open; back to baseline + ≤ 3 MB after closing. Clear caches in `viewWillDisappear` and on memory warnings.

---

### 6.10 Companion app

SwiftUI, `TabView` with 5 tabs, fully localized (en, fa) and RTL-correct.

| Tab | Screens and features |
|---|---|
| **Home** | Status cards: *Keyboard added?*, *Full Access on?* (from the heartbeat, §6.11.5), *Model loaded*. "Set up" → onboarding. **Try-it text field** (`TextEditor`), which is also the best host app for debugging. Quick toggles: prediction source, incognito, clipboard capture. |
| **Clipboard** | Pinned + Recent lists, search, filter by kind, full-text edit, pin/unpin, reorder pinned, multi-select delete, "Add from clipboard" via **`UIPasteControl`** (no paste prompt), clear history, retention settings. Optional Face ID lock (`LocalAuthentication`). **Snippets** sub-tab: folders, snippets, shortcuts, reorder. |
| **Dictionary** | Per language: learned words (search; sort by count, recent, A–Z), add a word, blocklist management, **Learn from text** (paste or import a `.txt` → tokenize → preview → commit), statistics (word counts), reset personal data. |
| **Themes** | Gallery grid with live mini-previews, apply to the light/dark slot, editor (§6.8.7), import/export. |
| **Settings** | Every setting in §6.1, grouped the same way, with a live `KeyboardPreview` on the Size & Layout and Appearance screens. Advanced: backup/restore, debug overlay toggle, reset all. **About:** version, privacy statement, acknowledgements (from `docs/ATTRIBUTIONS.md`), data-source credits. |

- **Onboarding:**
  1. Welcome.
  2. Add the keyboard: button opens `UIApplication.openSettingsURLString` (the app's own Settings page, which contains *Keyboards* → enable Kelid and **Allow Full Access**), with illustrated steps.
  3. Why Full Access: clipboard, sync with the app, sounds and haptics. The promise: *Kelid never connects to the internet*.
  4. Try it: a text field, and how to switch keyboards with the globe.
  5. Done.
- **Status detection:** the keyboard writes a heartbeat to the App Group on every appear (possible only with Full Access). The app shows: ✓ (heartbeat within 7 days, Full Access on) · "Enabled, Full Access off?" (the user says so, or there's no heartbeat) · "Not detected".
- **Live settings:** every change → save the blob → post `.settings.changed` → a keyboard currently shown in the Try-it field updates within 1 s.

---

### 6.11 Storage

#### 6.11.1 Paths

| What | Path (relative to the App Group container, or to the keyboard's own container as a fallback) |
|---|---|
| Database | `Library/Application Support/Kelid/kelid.sqlite` (+ `-wal`, `-shm`) |
| Custom themes | `Library/Application Support/Kelid/Themes/` |
| Image clips | `Library/Application Support/Kelid/Clips/{images,thumbs}/` |
| Temporary exports | `tmp/` (cleaned on launch) |

#### 6.11.2 Database setup (GRDB, following GRDB's "Sharing a Database" guide)

- **`DatabasePool`** (WAL mode). Open inside `NSFileCoordinator.coordinate(writingItemAt:options: .forMerging)`.
- **Persistent WAL** (`SQLITE_FCNTL_PERSIST_WAL = 1`) in `prepareDatabase`.
- `busyMode = .timeout(2)`, `observesSuspensionNotifications = true`.
- **Keyboard** posts `Database.suspendNotification` in `viewDidDisappear` and on `NSExtensionHostDidEnterBackground`. It posts `Database.resumeNotification` in `viewWillAppear` and on `NSExtensionHostWillEnterForeground`.
- **App** does the same on scene phase `.background` / `.active`. **Share Extension:** resume on start, suspend before completing the request.
- Catch `SQLITE_INTERRUPT` / `SQLITE_ABORT` ("database is suspended") and retry after resume. Never crash.
- **Short transactions only.** Never hold a transaction across `await`. Reads for UI use paged queries.
- **Local fallback:** without Full Access, the keyboard opens a DB at the same relative path in its own container, holding only the personal model. On the first launch **with** Full Access it merges into the shared DB (sum counts, max `lastUsed`, union blocklists) and deletes the local copy.

#### 6.11.3 Schema (GRDB `DatabaseMigrator`)

```sql
-- migration "v1_clips" (Phase 5)
CREATE TABLE clip (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid         TEXT    NOT NULL UNIQUE,
  kind         TEXT    NOT NULL CHECK (kind IN ('text','url','image')),
  text         TEXT,
  searchKey    TEXT    NOT NULL DEFAULT '',
  imageFile    TEXT,
  thumbFile    TEXT,
  contentHash  TEXT    NOT NULL UNIQUE,
  charCount    INTEGER NOT NULL DEFAULT 0,
  isTruncated  INTEGER NOT NULL DEFAULT 0,
  createdAt    REAL    NOT NULL,          -- unix seconds
  lastCopiedAt REAL    NOT NULL,
  lastUsedAt   REAL,
  copyCount    INTEGER NOT NULL DEFAULT 1,
  useCount     INTEGER NOT NULL DEFAULT 0,
  isPinned     INTEGER NOT NULL DEFAULT 0,
  pinnedOrder  REAL,
  isSensitive  INTEGER NOT NULL DEFAULT 0,
  expiresAt    REAL,
  source       TEXT    NOT NULL           -- capture | keyboard | app | share | intent
);
CREATE INDEX clip_recent ON clip(isPinned DESC, lastCopiedAt DESC);
CREATE INDEX clip_expiry ON clip(expiresAt) WHERE expiresAt IS NOT NULL;

-- migration "v1_snippets" (Phase 10; create the tables in Phase 5 if convenient)
CREATE TABLE snippet_folder (
  id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL, icon TEXT, sortOrder REAL NOT NULL
);
CREATE TABLE snippet (
  id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE,
  folderId INTEGER REFERENCES snippet_folder(id) ON DELETE SET NULL,
  title TEXT, text TEXT NOT NULL, searchKey TEXT NOT NULL,
  shortcut TEXT UNIQUE,                  -- text-expansion trigger, e.g. "@@addr"
  sortOrder REAL NOT NULL, createdAt REAL NOT NULL, updatedAt REAL NOT NULL,
  useCount INTEGER NOT NULL DEFAULT 0
);

-- migration "v1_user_model" (Phase 9)
CREATE TABLE user_word (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lang TEXT NOT NULL, surface TEXT NOT NULL, matchKey TEXT NOT NULL,
  count REAL NOT NULL DEFAULT 0, lastUsedAt REAL NOT NULL, firstSeenAt REAL NOT NULL,
  source TEXT NOT NULL DEFAULT 'typed',  -- typed | accepted | manual | import | contacts | replacement
  isBlocked INTEGER NOT NULL DEFAULT 0,
  UNIQUE (lang, surface)
);
CREATE INDEX user_word_key ON user_word(lang, matchKey);
CREATE TABLE user_bigram (
  lang TEXT NOT NULL, w1 TEXT NOT NULL, w2 TEXT NOT NULL,
  count REAL NOT NULL, lastUsedAt REAL NOT NULL,
  PRIMARY KEY (lang, w1, w2)
) WITHOUT ROWID;
CREATE TABLE user_trigram (
  lang TEXT NOT NULL, w1 TEXT NOT NULL, w2 TEXT NOT NULL, w3 TEXT NOT NULL,
  count REAL NOT NULL, lastUsedAt REAL NOT NULL,
  PRIMARY KEY (lang, w1, w2, w3)
) WITHOUT ROWID;
CREATE TABLE user_correction_block (
  lang TEXT NOT NULL, typed TEXT NOT NULL, corrected TEXT NOT NULL, createdAt REAL NOT NULL,
  PRIMARY KEY (lang, typed, corrected)
) WITHOUT ROWID;
```

#### 6.11.4 Migration rules

- Never edit a migration that has shipped. Always add a new one (`v2_…`).
- Both processes run the migrator. A process that finds the schema **newer** than it knows (`hasBeenSuperseded`) opens read-only and shows "Please update Kelid".

#### 6.11.5 `UserDefaults` keys

| Suite | Key | Type | Written by |
|---|---|---|---|
| App Group | `settings.v1` | Data (JSON) | App, keyboard |
| App Group | `kb.heartbeat` | Date | Keyboard |
| App Group | `kb.hasFullAccess` | Bool | Keyboard |
| App Group | `kb.version` | String | Keyboard |
| App Group | `app.probe` | Date (App Group read test for the keyboard) | App |
| Keyboard local | `settings.v1` | Data (mirror) | Keyboard |
| Keyboard local | `clip.lastSeenChangeCount` | Int | Keyboard |
| Keyboard local | `kb.lastLanguage` | String | Keyboard |
| Keyboard local | `emoji.recents`, `emoji.skinTones` | Data | Keyboard |

#### 6.11.6 Fallback if `0xDEAD10CC` still happens

If crash logs show `0xDEAD10CC` after the mitigations: move **keyboard writes** to append-only JSON-lines journals (`Journal/keyboard-<date>.jsonl`, one file per session, written with atomic appends). Whichever process opens the DB next (usually the keyboard itself on the next appear, or the app) merges them. Record the switch in the Decision log. Don't build this unless needed.

#### 6.11.7 Backup format (`.kelidbackup`, Phase 10)

A single UTF-8 JSON file (no zip library needed):

```json
{ "format": 1, "createdAt": "…", "appVersion": "…",
  "settings": { … }, "snippetFolders": [ … ], "snippets": [ … ],
  "pinnedClips": [ { …, "imageBase64": "…" } ],
  "userWords": { "fa": [ … ], "en": [ … ] },          // optional (user choice)
  "themes": [ { "json": { … }, "imageBase64": "…" } ] }
```

Import **merges**: by `uuid` for snippets, clips and themes; by `surface` for user words (sum counts).

#### 6.11.8 File protection

Keep the default class (`completeUntilFirstUserAuthentication`). **Never use `.complete`:** the keyboard can appear while the phone is locked (e.g. replying from a notification), and it would crash. Handle "database not available" (before the first unlock after a reboot) by running without clipboard and personal data.

---

### 6.12 Privacy and security

- **No network in any target** (enforced by the lint script). No analytics or crash SDKs. Crash reports come only from Apple (Xcode Organizer / TestFlight).
- **What's stored:**
  - clipboard items (with the user's retention settings);
  - personal word counts and n-grams up to 3 words. **No full sentences, no keystroke logs;**
  - settings and themes.
- **User controls:** incognito; learning off; delete personal data; clear clipboard; retention; sensitive filtering; "Delete all Kelid data" (App → Settings → Advanced).
- **Sensitive fields:** nothing is learned (§6.4.11). Clipboard items from password managers are skipped; OTPs expire.
- **Full Access text** in the app (en/fa): *"Kelid never connects to the internet. Full Access is needed for the clipboard, for sharing your words and settings between the app and the keyboard, and for sounds and haptics. Everything stays on this iPhone."*
- **Privacy manifests** (`PrivacyInfo.xcprivacy` in the app, keyboard and share targets):
  - `NSPrivacyTracking = false`, no tracking domains, no collected data types;
  - Accessed API reasons:
    - `UserDefaults`: `CA92.1` (own container), `1C8F.1` (App Group);
    - `FileTimestamp`: `C617.1` (files in our containers);
    - `SystemBootTime`: `35F9.1` (only if uptime or mach time is used for measuring intervals).
- **App Store privacy label:** *Data Not Collected*.
- `docs/PRIVACY.md` holds the privacy policy (hosting it is needed for App Store submission).

---

### 6.13 Performance and memory budgets

| Metric | Budget | How to measure |
|---|---|---|
| Cold start → keys drawn | ≤ 150 ms (iPhone XS class), ≤ 250 ms (oldest supported device) | `os_signpost` from `viewDidLoad` to the first `KeyGridView` layout; Instruments *Points of Interest* |
| Touch-down → key highlight | ≤ 1 frame (16 ms) | signpost; Instruments *Animation Hitches* |
| Touch-up → `insertText` returned | ≤ 4 ms on the main thread | signpost |
| Suggestion computation p95 | ≤ 20 ms (completion ≤ 5 ms, fuzzy ≤ 10 ms) | signposts; the debug overlay shows the last value |
| KLM open + validate | ≤ 30 ms | signpost |
| Memory while typing | ≤ 30 MB `phys_footprint` | debug overlay (`MemoryProbe`), Xcode memory gauge on device |
| Memory, panel open (emoji/clipboard) | ≤ 45 MB peak; ≤ +3 MB after closing | same + Instruments *Allocations* / *VM Tracker* |
| Memory growth over 50 show/hide cycles | ≤ +3 MB | debug overlay |
| Database write per commit | Asynchronous, ≤ 5 ms on the writer | signpost |

`MemoryProbe` (in `KelidCore`):

```swift
import Darwin
public enum MemoryProbe {
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
```

On `didReceiveMemoryWarning`: drop the emoji page cache, thumbnails and user-model n-gram caches (reload lazily); close idle panels.

---

## 7. Libraries, data and reference code

Few runtime libraries on purpose: every dependency costs memory in the extension, and license risk if you publish. Tooling and data sources can be as rich as needed.

### 7.1 Runtime dependencies (ship inside the app/keyboard)

| Library | License | Used for | Target |
|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) (7.x, pin exact version) | MIT | SQLite: clips, snippets, personal model; multi-process sharing | KelidStorage |
| [swift-collections](https://github.com/apple/swift-collections) (`HeapModule`, `DequeModule`) | Apache-2.0 | Priority queue for best-first trie search; undo/deque buffers | PredictionEngine, InputEngine |
| [Vazirmatn](https://github.com/rastikerdar/vazirmatn) font | OFL-1.1 | Persian key labels and app UI option | App, keyboard |
| Unicode CLDR annotations + `emoji-test.txt` | Unicode License v3 | Emoji names and keywords (fa/en) → `emoji.json` | EmojiData (data) |

### 7.2 Tooling (never shipped)

| Tool | License | Used for |
|---|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | Generate the Xcode project from `project.yml` |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), [SwiftLint](https://github.com/realm/SwiftLint) | MIT | Formatting and linting |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | MIT | Snapshot tests of layouts, themes and panels (test targets only) |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | `klm` command-line tool |
| [hazm](https://github.com/roshan-research/hazm) | MIT | Persian normalization and tokenization in the pipeline |
| [DuckDB](https://github.com/duckdb/duckdb) (Python package) | MIT | n-gram counting over large corpora |
| pyarrow, regex, tqdm | Apache-2.0 / Python-2.0 / MIT | Pipeline helpers |
| [wikiextractor](https://github.com/attardi/wikiextractor) | Tool only (check its license; it's never shipped) | Wikipedia dump → plain text |
| [KenLM](https://github.com/kpu/kenlm) *(optional)* | LGPL-2.1 (tool only) | Optional Kneser–Ney model experiments; outputs converted to KLM |

### 7.3 Data sources

| Source | License | Use |
|---|---|---|
| Persian and English Wikipedia dumps ([dumps.wikimedia.org](https://dumps.wikimedia.org)) | CC BY-SA 4.0 | Main formal corpora → n-gram counts (attribution required) |
| [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) `fa_full`, `en_full` (OpenSubtitles 2018) | Code MIT, data CC BY-SA 4.0 | Informal/conversational word frequencies |
| [Lilak](https://github.com/b00f/lilak) | Apache-2.0 | Valid Persian spellings (whitelist/boost) |
| [HeliBoard/AOSP dictionaries](https://codeberg.org/Helium314/aosp-dictionaries), experimental Persian list | Source lists CC BY 4.0 (per repo listing; verify) | Optional extra frequency and next-word source to evaluate |
| OPUS OpenSubtitles monolingual text | Unclear for redistribution | **Personal builds only** (`--with-opensubtitles-text`) |
| Unicode CLDR + emoji data | Unicode License v3 | Emoji search and suggestions |

### 7.4 Reference code (read to learn; copy only when the license allows and attribute)

| Project | License | What to learn from it |
|---|---|---|
| [KeyboardKit **9.9.1** tag](https://github.com/KeyboardKit/KeyboardKit/tree/9.9.1) | MIT (≤ 9.9.1; ≥ 10.0 is closed source) | Callouts, gesture handling, autocapitalization, proxy extensions |
| [Clip](https://github.com/rileytestut/Clip) | Unlicense (public domain) | Keyboard + clipboard-history app; `allowsSelfSizing` + height constraint; in-memory store without Full Access |
| [Hamster](https://github.com/imfuxiao/Hamster) | MIT (per GitHub) | A full-featured iOS input method: keyboard extension architecture, layout customization |
| [Tasty Imitation Keyboard](https://github.com/archagon/tasty-imitation-keyboard) | BSD-3-Clause | iOS-like key geometry and rendering |
| [AOSP LatinIME](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/) | Apache-2.0 | Proximity info, suggestion scoring, binary dictionary ideas |
| [FlorisBoard](https://github.com/florisboard/florisboard) | Apache-2.0 | Glide typing classifier (Phase 14), clipboard UX |
| [HeliBoard](https://github.com/HeliBorg/HeliBoard) | GPL-3.0 | UX ideas only. **Do not copy code.** |
| [aosp-persian-dict](https://github.com/mojienjoyment/aosp-persian-dict) | GPL-3.0 repo; data CC BY-SA / LGPL | Ideas for building a Persian dictionary from Wikipedia + Hunspell. **Ideas only.** |
| [SymSpell](https://github.com/wolfgarbe/SymSpell) | MIT | Fuzzy-matching ideas (we use trie + Levenshtein instead) |
| [EmojiKit](https://github.com/danielsaidi/EmojiKit) | MIT | Emoji categories and skin tones (optional reference; we build our own data with Persian keywords) |

### 7.5 Apple frameworks used

UIKit, SwiftUI, Foundation, os (`Logger`, signposts), AudioToolbox (sounds), CoreText (fonts, glyph checks), ImageIO (downsampling), UniformTypeIdentifiers, PhotosUI (theme images), AppIntents (Phase 10), LocalAuthentication (optional Face ID lock), NaturalLanguage (optional: language detection in "learn from text").

### 7.6 Don't use

- KeyboardKit ≥ 10 (closed source) or KeyboardKit Pro.
- Any GPL/AGPL code **inside** the app (HeliBoard, AnySoftKeyboard parts, some dictionaries) if you might publish on the App Store.
- Analytics, crash-reporting or ad SDKs.
- Network-based "AI" or cloud prediction.
- `UITextChecker` as the main engine (no Persian support; at most an English fallback experiment).

---
## 8. Phases

Every phase has the same structure: **Goal · Size · Depends on · You get · Tasks · Tests · Acceptance criteria · Manual test · Pitfalls · Out of scope.** Sizes: **S** ≈ one session, **M** ≈ 1–2 sessions, **L** ≈ 2–3 sessions (split points given).

---

### Phase 0 — Project bootstrap

**Goal:** A buildable repository with the app, the keyboard extension, the Swift package skeleton, App Group wiring, lint/format, a Makefile and the AI working files. The keyboard installs, shows up in iOS Settings, types two test words, has a working globe key, and **proves that height changes work** (the base for resizing).
**Size:** S–M · **Depends on:** nothing · **Read:** §0.3 row 0
**You get:** a "hello world" keyboard on your iPhone.

**Tasks**

0.1 **Tools and repo.** Check `xcodebuild -version`, `xcodegen --version`, `swiftformat --version`, `swiftlint --version`, `git lfs version`. Run `git init` and `git lfs install`. Add:
- `.gitignore`: `*.xcodeproj`, `DerivedData/`, `.build/`, `.swiftpm/`, `Config/Local.xcconfig`, `Tools/data-pipeline/data/`, `Tools/data-pipeline/.venv/`, `*.xcuserstate`, `.DS_Store`
- `.gitattributes`: `*.klm filter=lfs diff=lfs merge=lfs -text`

0.2 **Config files.**

```text
// Config/Base.xcconfig
KELID_BUNDLE_PREFIX = com.example
KELID_APP_GROUP = group.$(KELID_BUNDLE_PREFIX).kelid
KELID_TEAM_ID =
#include? "Local.xcconfig"
```

`Config/Local.xcconfig.example` contains `KELID_BUNDLE_PREFIX = com.yourname` and `KELID_TEAM_ID = XXXXXXXXXX`. Copy it to `Local.xcconfig` with the values from §0.4. (For a free account, the team ID is the "Personal Team" ID shown in Xcode → Settings → Accounts.)

0.3 **`project.yml`** (XcodeGen):

```yaml
name: Kelid
options:
  bundleIdPrefix: com.example            # real IDs come from Config/*.xcconfig
  deploymentTarget: { iOS: "17.0" }
  createIntermediateGroups: true
configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig
settings:
  base:
    SWIFT_VERSION: "6.0"
    DEVELOPMENT_TEAM: $(KELID_TEAM_ID)
    CODE_SIGN_STYLE: Automatic
    TARGETED_DEVICE_FAMILY: "1,2"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
packages:
  KelidKit: { path: Packages/KelidKit }
targets:
  Kelid:
    type: application
    platform: iOS
    sources: [App]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(KELID_BUNDLE_PREFIX).kelid
        SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Kelid
        KelidAppGroupID: $(KELID_APP_GROUP)
        UILaunchScreen: {}
    entitlements:
      path: App/Kelid.entitlements
      properties:
        com.apple.security.application-groups: [$(KELID_APP_GROUP)]
    dependencies:
      - target: KelidKeyboard
      - { package: KelidKit, product: KeyboardUI }
      - { package: KelidKit, product: KelidStorage }
  KelidKeyboard:
    type: app-extension
    platform: iOS
    sources: [Keyboard]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(KELID_BUNDLE_PREFIX).kelid.keyboard
        SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
        APPLICATION_EXTENSION_API_ONLY: YES
    info:
      path: Keyboard/Info.plist
      properties:
        CFBundleDisplayName: Kelid
        KelidAppGroupID: $(KELID_APP_GROUP)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.keyboard-service
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).KeyboardViewController
          NSExtensionAttributes:
            IsASCIICapable: true        # we ship English; ASCII-only fields force the English layout
            PrefersRightToLeft: true    # Persian is primary; verify effect, record in Decision log
            PrimaryLanguage: fa-IR      # changed at runtime via primaryLanguage when switching to English
            RequestsOpenAccess: true
    entitlements:
      path: Keyboard/KelidKeyboard.entitlements
      properties:
        com.apple.security.application-groups: [$(KELID_APP_GROUP)]
    dependencies:
      - { package: KelidKit, product: KeyboardUI }
schemes:
  Kelid:
    build: { targets: { Kelid: all, KelidKeyboard: all } }
  KelidKeyboard:
    build: { targets: { KelidKeyboard: all, Kelid: all } }
    run: { askForAppToLaunch: true }
```

If an XcodeGen key has a different name in the installed version, fix it and note it in the Decision log.

0.4 **Swift package skeleton** `Packages/KelidKit/Package.swift` (`swift-tools-version: 6.2`, platforms `.iOS(.v17), .macOS(.v14)`):
- One library target per module in §4.2 except `KLMTool`.
- One test target per module.
- Dependencies: GRDB (`from: "7.0.0"`), swift-collections (`from: "1.1.0"`), swift-snapshot-testing (test only).
- `KeyboardUI` uses `swiftSettings: [.defaultIsolation(MainActor.self)]`.
- **Every file in `KeyboardUI`** (and the UIKit parts of `ClipboardKit`/`ThemeKit`) is wrapped in `#if canImport(UIKit) … #endif`, so `swift test` still builds on macOS.
- Placeholder resources, so the resource declarations compile: `KeyboardLayout/Layouts/.keep`, `ThemeKit/BuiltInThemes/.keep`, `EmojiData/emoji.json` containing `[]`.
- Each module gets one public placeholder type and one passing test.

0.5 **The `klm` tool package** `Tools/klm/Package.swift` (macOS 14, executable `klm`, depends on `../../Packages/KelidKit` products `PredictionEngine` and `PersianText`, plus swift-argument-parser). It's kept **outside** KelidKit so iOS builds never try to build a macOS executable. A placeholder `klm --version` works.

0.6 **Placeholder keyboard** (`Keyboard/KeyboardViewController.swift`):
- a status line: `FullAccess ✓/✗ · AppGroup read ✓/✗ · iOS <version>`;
- buttons **سلام**, **hello**, **⌫** (via `textDocumentProxy`);
- a **🌐** button, only when `needsInputModeSwitchKey`, wired to `handleInputModeList(from:with:)` for `.allTouchEvents`;
- **Height test:** buttons **−20 / +20** that change the keyboard height using §6.3.4 (priority-999 constraint + `allowsSelfSizing`). Start at 260 pt.

0.7 **Placeholder app** (`App/KelidApp.swift`): a `TabView` with a Home tab showing setup steps, an **Open Settings** button (`UIApplication.openSettingsURLString`), and a **Try it** `TextEditor`. On launch, write `app.probe = Date()` to the App Group `UserDefaults` (the keyboard reads it for the "AppGroup read" check).

0.8 **Makefile** with `gen`, `build`, `test` (= `test-mac` + `test-ios`), `lint`, `format`, `klm` (placeholder), `data-quick` / `data-full` (placeholders), `clean`, and `SIM ?= platform=iOS Simulator,name=iPhone 17` (use a name that exists; see §5.2). `test-ios` runs `xcodebuild test -scheme KelidKit-Package -destination "$(SIM)"` inside `Packages/KelidKit`.

0.9 **`Tools/scripts/lint-no-network.sh`**: fails if `URLSession|NWConnection|NWPathMonitor|import Network|NSURLConnection|CFStream|WKWebView` appears in `App/ Keyboard/ ShareExtension/ Packages/KelidKit/Sources/` (skip folders that don't exist yet). Add `.swiftformat` (Swift version 6, 4-space indent, max width 140) and `.swiftlint.yml` (disable `line_length` warnings under 140, enable `force_unwrapping`, exclude `.build` and `Tools/data-pipeline`).

0.10 **`Log`** in `KelidCore`: `Logger` helpers with one category per module. The subsystem is the app's bundle ID `<prefix>.kelid` (in the extension, drop the trailing `.keyboard` from its bundle ID), so Console.app can filter all Kelid processes at once.

0.11 **AI working files:**
- `CLAUDE.md`: copy Appendix A verbatim, filling in the prefix.
- `PROGRESS.md`: from Appendix B, with the Phase 0 row "in progress".
- `README.md`: prerequisites, `cp Config/Local.xcconfig.example Config/Local.xcconfig`, `make gen && open Kelid.xcodeproj`, signing notes (free vs paid), how to enable the keyboard, how to debug (§5.4).

0.12 **Verify** from a clean state: `make clean gen build test lint`.

**Tests:** one passing test per module; `lint-no-network.sh` passes.

**Acceptance criteria**
- [ ] `make gen && make build && make test && make lint` succeed from a fresh clone (after creating `Local.xcconfig`).
- [ ] On the Simulator **and** your iPhone: the app installs, and *Kelid* appears under Settings → General → Keyboard → Keyboards → Add New Keyboard.
- [ ] In Notes: switching to Kelid works, the buttons insert "سلام" / "hello", ⌫ deletes, 🌐 switches keyboards (long-press shows the list) on devices that need it.
- [ ] −20 / +20 visibly changes the keyboard height, with no Auto Layout errors in the console.
- [ ] The status line shows Full Access ✗ → ✓ after enabling it in Settings, and AppGroup read ✓ once Full Access is on.
- [ ] `CLAUDE.md`, `PROGRESS.md` and `README.md` exist. Committed and tagged `phase-0`.

**Manual test:** follow the checklist above on your iPhone. Also try the keyboard in Safari's address bar and in Messages.

**Pitfalls**
- The extension's bundle ID **must** start with the app's bundle ID.
- Both targets need the **same App Group** in their entitlements.
- Free accounts: if signing fails, let Xcode register the App Group automatically (Signing & Capabilities); installs expire after 7 days.
- The Simulator needs *Connect Hardware Keyboard* turned off to show software keyboards.

**Out of scope:** real layouts, settings, storage.

---

### Phase 1 — Foundation: settings, storage, text abstraction, diagnostics

**Goal:** The shared infrastructure every later phase uses: settings with sync, App Group paths with fallback, Darwin notifications, the `TextDocument` abstraction and its mock, the database skeleton with suspension handling, heartbeat and diagnostics.
**Size:** M · **Depends on:** Phase 0 · **Read:** §0.3 row 1
**You get:** nothing visible yet except a diagnostics line. This phase keeps every later phase reliable.

**Tasks**

1.1 **`KelidCore`:**
- `AppGroup.identifier`, read from the Info.plist key `KelidAppGroupID`;
- `ContainerPaths.resolve(fullAccess:) -> ContainerPaths` (shared vs local, §6.11.1);
- `DarwinNotifier` (post, and observe with closures via a name → handlers registry; safe to call from any thread; callbacks delivered on main);
- `Clock` protocol + `SystemClock` + `TestClock`;
- `MemoryProbe` (§6.13);
- `Signposts` helpers.

1.2 **`KelidSettings`:**
- **All** settings groups from §6.1, including later features (they're just data), with defaults;
- tolerant decoding (§6.1.1) and `clamped()`;
- `SettingsStore` (`@Observable @MainActor`):
  - `load()`: shared blob vs local mirror, newer `updatedAt` wins;
  - `update(_:)`: sets `updatedAt`, clamps, writes shared (if writable) and local, posts `.settings.changed`;
  - observes `.settings.changed` → `reload()`;
  - resolves `SizeProfile` by orientation;
  - `resolvedPrediction(for:)`.

1.3 **`InputEngine`:**
- `TextDocument` protocol and `FieldTraits` (our own enums mirroring `UIKeyboardType`, `UIReturnKeyType`, `UITextAutocapitalizationType`, `UITextAutocorrectionType`, `UITextSpellCheckingType`, `UIKeyboardAppearance`, and `UITextContentType` as a string);
- `MockTextDocument` with the host-imitation switches from §6.4.8, as a test-support type in the test target or a separate `InputEngineTestSupport` target.

1.4 **Keyboard target:** `ProxyTextDocument` (wraps `textDocumentProxy`, maps traits) and `KeyboardServices` (process-level singleton holding `SettingsStore`, a lazy `DatabaseManager`, and later the language models).

1.5 **`KelidStorage`:**
- `DatabaseManager` implementing §6.11.2 exactly: coordinated open, persistent WAL, busy timeout, `observesSuspensionNotifications`;
- `suspend()` / `resume()`;
- a migrator with one migration `v0_meta` (`CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)`);
- read-only open when the schema is superseded;
- all methods `async`.

1.6 **Keyboard lifecycle wiring** in `KeyboardViewController`:
- `viewWillAppear` → resume the DB, `settings.load()`, refresh `fullAccess`, write the heartbeat;
- `viewDidDisappear` → flush, then suspend the DB;
- observe `NSExtensionHostDidEnterBackground` / `NSExtensionHostWillEnterForeground` for the same;
- `textWillChange` / `textDidChange` → refresh traits.

1.7 **Heartbeat and probes:** when Full Access is on, the keyboard writes `kb.heartbeat`, `kb.hasFullAccess`, `kb.version`, and reads `app.probe` → `appGroupReadable`. The app's Home tab shows the heartbeat status (§6.10).

1.8 **Diagnostics line** in the placeholder keyboard: settings `updatedAt`, Full Access, App Group readable, DB state (open / suspended / unavailable), memory MB.

1.9 **Temporary app debug control:** one toggle in the app (e.g. `general.keyPopups`) to prove live sync. Remove it in Phase 10, when real settings screens exist.

**Tests**
- Settings decoding: missing keys, unknown enum values, extra keys; clamping edge values; newest-wins merge; round trip.
- `DarwinNotifier`: post/observe in-process.
- `MockTextDocument`: insert/delete/cursor/selection; limited and nil context; per-scalar deletion mode.
- `DatabaseManager`: open, migrate and suspend/resume in a temporary directory; a write while suspended throws the expected error and succeeds after resume.

**Acceptance criteria**
- [ ] All tests pass on macOS (`make test-mac`) and iOS (`make test-ios`).
- [ ] With the keyboard shown in the app's Try-it field, flipping the debug toggle in the app changes the diagnostics line within 1 second.
- [ ] With Full Access off, the keyboard still shows and works (local settings); the diagnostics line says so.
- [ ] The app's Home tab shows "Keyboard active, Full Access ✓" after using the keyboard once with Full Access on.
- [ ] No `0xDEAD10CC` or other crash after 20 cycles of: show keyboard → home screen → back.

**Manual test:** enable/disable Full Access and check the diagnostics line. Use the keyboard in 3 apps, open the Kelid app, and check the heartbeat status.

**Pitfalls**
- Settings reads must never block: `UserDefaults` is fine; the DB is `async`.
- Don't open the DB in `viewDidLoad` synchronously. Open it lazily in the background.

**Out of scope:** real UI, layouts, clipboard.

---

### Phase 2 — Layout engine and layouts

**Goal:** Data-driven layouts for Persian, English, symbols and the numeric pad, plus geometry (frames and hit areas) and the proximity map. Pure logic, fully tested, no rendering yet.
**Size:** M · **Depends on:** Phase 1 · **Read:** §0.3 row 2
**You get:** nothing visible yet (an ASCII debug render in tests).

**Tasks**

2.1 **Models:** `KeyboardLayoutFile`, `PageDefinition`, `KeyDefinition` (Codable with the shorthand string form, §6.2.1), `KeyKind`, `KeyboardPage`, `LanguageID`, `Direction`.

2.2 **JSON files** in `Sources/KeyboardLayout/Layouts/`:
- `fa.standard.json`, `fa.compact.json`, `en.qwerty.json` (letters + alternates + digit hints);
- `fa.symbols.json`, `en.symbols.json` (`symbols1`, `symbols2`);
- `numpad.json`.
Exact contents are in §6.2.2–§6.2.5.

2.3 **`LayoutValidator`** (§6.2.1 rules). **`LayoutRepository`** loads, validates and caches by id. Invalid files fail tests and log an error at runtime (fall back to `en.qwerty`).

2.4 **`BottomRowBuilder`** implementing the §6.2.6 table from a `BottomRowContext(page, language, languagesCount, needsGlobe, keyboardType, returnKeyType, showEmojiKey)`.

2.5 **Number row and digit substitution:** `showNumberRow` prepends a digits row (Persian or Latin per `persianDigits`); `persianDigits == .latin` swaps digits on Persian pages (§6.2.4).

2.6 **`LayoutEngine.compute(page:, in: CGRect, metrics: KeyboardMetrics, direction:) -> ComputedLayout`:**
- rows, keys, frames and hit frames (§6.3.1, §6.3.5);
- spacers, one-handed `contentRect` (§6.3.6);
- `ComputedLayout.key(at: CGPoint) -> ComputedKey?` (nearest-in-row fallback).

2.7 **`KeyboardMetrics`** from a `SizeProfile` and device class (§6.3.2), including font sizes (`baseFontSize = keyVisualHeight × 0.52 × fontScale`, clamped 14–30 pt).

2.8 **`ProximityMap`** from a computed letters layout: for each character key, the neighbor characters whose centers are within 1.6 × the key width. Serializable for tests.

2.9 **`LayoutDebugRenderer`:** an ASCII rendering of a computed layout (rows of labels with widths). Used in test output so the AI can "see" layouts.

**Tests**
- Every layout loads and validates. Every Persian letter appears exactly once in `fa.standard`.
- Frames lie inside bounds, don't overlap, and have the correct gaps. Hit frames tile each row without holes.
- `key(at:)` for points in gaps and at edges.
- Bottom-row variants for letters (fa/en), symbols, email, URL, webSearch, twitter; with and without the globe; with 1 or 2 languages.
- Number row adds exactly one row. Latin/Persian digit swap.
- Snapshot (JSON) of computed frames at 390×224, 375×216, 430×232 and landscape 844×168, stored as test fixtures.

**Acceptance criteria**
- [ ] All tests pass. The debug renderer output for `fa.standard` at 390 pt matches §6.2.2.
- [ ] **You confirm the Persian key order** (look at the ASCII render in the test log or `PROGRESS.md`). Changes are just JSON edits.

**Manual test:** none on device. Review the ASCII layouts the AI pastes into `PROGRESS.md`.

**Pitfalls:** RTL is **not** reversed in data. Rows are visual left→right; only text direction and slot order are RTL.

**Out of scope:** rendering, touches.

---

### Phase 3 — Typing surface and input engine (Size L)

**Goal:** A real, fast, iOS-quality keyboard for Persian and English, without predictions: key rendering, multi-touch handling, popups, long-press alternates, shift/caps, pages, backspace behaviors, space trackpad, language switching, globe, return key, auto-capitalization, double-space period, ZWNJ rules, number pads, basic light/dark look, sounds and haptics (with Full Access), debug overlay.
**Size:** L · **Depends on:** Phases 1–2 · **Read:** §0.3 row 3
**Session A:** 3.1–3.8 · **Session B:** 3.9–3.18
**You get:** a keyboard you can actually type with every day.

**Tasks**

3.1 **`KeyView` + `KeyGridView`** (UIKit, `KeyboardUI`):
- `KeyGridView.apply(layout: ComputedLayout, style: KeyStyle, shift: ShiftState, returnKey: ReturnKeyDisplay)` builds or reuses `KeyView`s, diffed by key id;
- each `KeyView` has a background layer with `cornerRadius`, a cheap shadow via `shadowPath`, and a label (`UILabel`) or SF Symbol image (shift, backspace, globe, return, emoji);
- Persian labels use the system font at this stage (Vazirmatn comes in Phase 11);
- pressed state changes the fill without animation (animation options in Phase 11).

3.2 **`KeyTouchTracker`** (pure logic in `InputEngine`, §6.4.12) and the UIKit bridge in `KeyGridView`:
- `touchesBegan/Moved/Ended/Cancelled` → tracker events;
- `isMultipleTouchEnabled = true`;
- rollover: a new touch-down commits the previous pressed key.

3.3 **Key popup** (`KeyCalloutView`): shows the character larger, above the key. It lives in the **root view**, so it can overlap the toolbar strip for the top row (C7). If the toolbar is hidden, the top row gets an in-key highlight only. Respects `keyPopups`.

3.4 **Long-press alternates** (`AlternatesCalloutView`):
- appears after `longPressDelayMs`;
- items come from the layout's alternates plus digit hints;
- ordering follows the language direction;
- the finger slides to select, lift commits;
- `keyHints` draws a small hint in the key corner.

3.5 **`InputProcessor`** (§6.4.2): character insertion with shift mapping, page switching, the shift/caps machine and auto-cap (§6.4.3), space and double-space period, smart punctuation spacing (§6.4.4), ZWNJ rules (§6.4.5), backspace tap/hold/word/swipe (§6.4.6), return, `textDidChange` handling and the shadow buffer (§6.4.8), plus `InputEffect` output.

3.6 **Space trackpad** (`.drag` and `.longPress`) with RTL-aware direction (§6.4.4). The key labels fade while in cursor mode.

3.7 **Backspace:** hold-repeat timing and acceleration; swipe-left word deletion with restore-on-return (§6.4.6).

3.8 **`KeyboardController`** (`@MainActor`, in `KeyboardUI`) connects tracker → `InputProcessor` → `ProxyTextDocument` → effects → `KeyGridView` / `KeyboardState`. `KeyboardRootView` (UIKit container) holds a toolbar strip (SwiftUI via `UIHostingController`, `safeAreaRegions = []`, with placeholder icons) and `KeyGridView`. **End of Session A.**

3.9 **Language key and switching** (§6.4.7): `primaryLanguage` update, space label, last-language persistence, forced English for ASCII/email/URL fields.

3.10 **Globe key** (§6.4.7): a `UIControl` overlay forwarding `.allTouchEvents` to `handleInputModeList(from:with:)`. Hidden when `needsInputModeSwitchKey == false`.

3.11 **Return key** labels, icon and style per §6.4.10 (localized). Disabled look per `enablesReturnKeyAutomatically`.

3.12 **Field traits** (§6.4.11): page selection for number pads (`numpadDigits`), `.numbersAndPunctuation` → `symbols1`, `keyboardAppearance` → light/dark built-in style, sensitive-field flag stored in `KeyboardState`.

3.13 **Height:** use `HeightCoordinator` (row count × `rowHeight` + toolbar + paddings) with the §6.3.4 mechanism. Defaults from §6.3.2. (Full resizing UI comes in Phase 4.)

3.14 **`FeedbackService`:** haptics (`UIImpactFeedbackGenerator`, prepared on touch-down) and sounds (`AudioServicesPlaySystemSound` 1123/1155/1156 on a background queue). Both only with Full Access and when the setting is on. The sound IDs are verified on device and recorded.

3.15 **Built-in look:** two hard-coded styles (light/dark) matching iOS closely: key fill, special-key fill, shadow, 5 pt radius, label weights. Resolved from `keyboardAppearance` or the trait. (Real theming comes in Phase 11 and must not require rewriting `KeyView`: take colors from a `KeyStyle` struct now.)

3.16 **Device deletion check (§6.4.8):** in Notes, Messages, Telegram/WhatsApp and Safari, test deleting `می‌خوام`, `بَ`, `👍🏽` and ZWNJ words with single backspaces. Record per-host behavior in PROGRESS.md and adjust `deleteBackward` helpers if needed.

3.17 **Accessibility:** every `KeyView` is an accessibility element with the `.keyboardKey` trait and a localized label (letters: the character; special keys: "delete", "shift", "space", "return", "next keyboard", "نیم‌فاصله"…). VoiceOver lift-to-type works.

3.18 **Debug overlay** (`advanced.debugOverlay`): a small translucent label in the toolbar strip showing memory MB, last `insertText` duration, Full Access, page/language, and `documentIdentifier` changes.

**Tests**
- `InputProcessor` with `MockTextDocument`: shift machine (tap, double-tap, auto-cap sentence/words/allCharacters/none), double-space period (letters, digits, after punctuation → no), smart punctuation removal of the auto space, ZWNJ rules (start of word, double ZWNJ, space after ZWNJ), backspace hold timing (with `TestClock`), word deletion boundaries (Persian with ZWNJ, English with apostrophes), return inserts `\n`, forced English in URL fields, numpad for number pads.
- `KeyTouchTracker`: tap, rollover ordering (A down, B down, A up, B up → "AB"), long-press → alternate selection by x position, trackpad step math (LTR and RTL), backspace swipe accumulate/restore, cancel.
- Snapshot tests (simulator) of `KeyGridView` for fa/en letters and symbols, light and dark.

**Acceptance criteria**
- [ ] Typing a Persian paragraph and an English paragraph works in Notes, Messages, Safari, WhatsApp and Telegram, with no dropped or reordered letters when typing fast (two thumbs).
- [ ] Long-press alternates, shift/caps, symbol pages, Persian digits and punctuation, ZWNJ key, backspace hold and swipe, space trackpad (LTR and RTL text), globe, and language key all work.
- [ ] Return key labels are right in the Safari URL bar (go/برو), search fields (search/جستجو) and Messages (return or send).
- [ ] Number fields show the numeric pad with Latin digits; URL and email fields show English with `/ .com` or `@ .`.
- [ ] Memory while typing ≤ 25 MB on device (debug overlay). No hitches in Instruments *Animation Hitches* while typing.
- [ ] Deletion behavior is recorded (3.16).

**Manual test (your iPhone)**
1. In Notes, type: `سلام، امروز می‌خواهم کتاب‌ها را مرتب کنم.` using the ZWNJ key.
2. Type English: `Hello. This is a test.` and check auto-capitals and the double-space period.
3. Hold ا → pick آ. Hold backspace to delete a line. Swipe left from backspace to delete 3 words, then move back right to restore 1.
4. Drag on the space bar to move the cursor inside Persian text: dragging left should move the cursor visually left.
5. Open Safari → address bar: English layout with `/` and `.com`, return says "go".
6. Open a field that asks for digits only (e.g. a verification-code or PIN field on an app's login screen): the numeric pad appears with Latin digits.
7. With Full Access on, turn on haptics and sounds (temporary debug toggles) and feel them.

**Pitfalls**
- Never call `textDocumentProxy` off the main thread.
- Don't let SwiftUI re-render the key grid per keystroke (it's UIKit on purpose).
- Top-row popups get clipped without the toolbar strip (C7).
- `UIHostingController` inside the keyboard: set `safeAreaRegions = []` and a clear background.

**Out of scope:** suggestions, clipboard, themes beyond light/dark, resize UI.

---

### Phase 4 — ★ Resizing and one-handed mode

**Goal:** You can make the keyboard exactly the size you want, per orientation, by dragging or with sliders, including one-handed mode and bottom lift. Changes persist.
**Size:** M · **Depends on:** Phase 3 · **Read:** §0.3 row 4
**You get:** your #2 priority feature, complete.

**Tasks**

4.1 **`HeightCoordinator`** (finalize): computes the total height (§6.3.1) and clamps (§6.3.3). It updates the constraint on settings change, page row-count change, number-row toggle, toolbar visibility change, orientation change (`viewWillTransition`, trait changes), and panel open/close (panels keep the same height).

4.2 **Size profiles:** portrait and landscape from `size.*`. Device-class defaults (§6.3.2) are computed at first run and stored.

4.3 **Resize mode overlay** (§6.3.7): SwiftUI overlay on top of `KeyboardRootView`:
- top, bottom, left and right handles; center drag in one-handed mode;
- preset chips S/M/L/XL, live readout, Reset, Done;
- 30 Hz throttled live updates through a `CADisplayLink` coalescer;
- haptic tick at the default size;
- typing disabled while resizing; rotation cancels.

4.4 **One-handed mode** (§6.3.6): `LayoutEngine` gets `contentRect`; `SidePanelView` with switch-side, exit, clipboard (disabled until Phase 5) and ◀ ▶ cursor buttons (hold to repeat).

4.5 **Bottom lift:** empty area below the keys, drawn with the keyboard background and a subtle grab-handle line.

4.6 **In-keyboard Quick Settings panel** (SwiftUI, opened from the toolbar ⚙︎). First version:
- **Size:** row-height slider (current orientation), lift, one-handed on/off/side, width ratio, key gaps, font scale, number row;
- **Typing:** key popups, sounds, haptics, space trackpad mode;
- **Language:** enabled languages, digits;
- **Resize visually** button, **Reset size** button, and a footer "More settings in the Kelid app".
- It writes through `SettingsStore` (shared if possible, local always).

4.7 **App → Settings → Size & Layout** screen: the same controls, plus a **live `KeyboardPreview`** (renders the real `KeyGridView` with a mock document and fake suggestions via `UIViewRepresentable`) that updates as sliders move. Portrait/landscape picker.

4.8 **Edge cases:**
- landscape on small phones (clamp so at least 40% of the screen stays visible for the host);
- rotating with a panel open;
- hosts that re-layout slowly (throttling);
- **the reset path always works**, even if a stored value is corrupted (clamp on load).

**Tests**
- Pure: total-height formula, clamps and their order (lift first), preset math, profile selection by traits, one-handed content rect (left/right, ratio limits).
- Snapshot: grid at rowHeight 44/54/70, one-handed left/right, with the number row.
- UI test (app): moving the Size & Layout slider updates the preview.

**Acceptance criteria**
- [ ] Dragging the top handle resizes smoothly in Notes, Messages and WhatsApp. **Done** saves; the size survives dismiss/re-show, app switches and reboots.
- [ ] Portrait and landscape keep separate sizes.
- [ ] One-handed left/right: keys stay accurately tappable; the side-panel buttons work; the width ratio is adjustable by edge-drag and by slider.
- [ ] Bottom lift raises the keys; Reset restores the defaults.
- [ ] No Auto Layout conflict logs. Memory +≤ 2 MB versus Phase 3.
- [ ] The app's Size & Layout preview matches the real keyboard (compare screenshots).

**Manual test**
1. Toolbar → resize icon → drag the top handle up about 1 cm → Done. Type a sentence.
2. Rotate to landscape: default landscape size. Resize it differently, rotate back: the portrait size is intact.
3. Drag the left edge inward → one-handed right. Switch sides with the side panel, then exit.
4. Set lift to about 40 pt and check it's comfortable for your thumb.
5. Quick Settings → Reset size.

**Pitfalls**
- Changing the height constraint on every touch-move floods the host with layout passes. Throttle.
- Don't fight the system's encapsulated height constraint (priority 999, §6.3.4).
- Keep resize-mode views out of the hierarchy when not resizing (memory).

**Out of scope:** iPad profiles (Phase 17), themes.

---

### Phase 5 — ★ Clipboard core and edit tools (Size L)

**Goal:** A complete clipboard experience inside the keyboard: capture, history, pin, delete, search, one-tap paste chip, sensitive filtering, retention, image clips, plus an edit panel (cursor moves, copy/cut/paste, delete word, undo). Works gracefully without Full Access.
**Size:** L · **Depends on:** Phases 1, 3, 4 · **Read:** §0.3 row 5
**Session A:** 5.0–5.4 · **Session B:** 5.5–5.14
**You get:** your #1 priority feature, complete inside the keyboard.

**Tasks**

5.0 **Pasteboard lab (do first, about 1 hour).** Behind `advanced.pasteboardLab` (debug builds only), add a small panel with buttons: read `changeCount`, `types`, `hasStrings`/`hasURLs`/`hasImages`, `string` (automatically on appear vs. on tap), `detectPatterns`. **On your iPhone**, copy text in Safari/Notes/Telegram, open the keyboard in another app, and record for your iOS version: *Does reading `string` show a banner? A prompt? Every time or once?* Write the table in PROGRESS.md and **set the default `clipboard.captureMode`** (`.auto` if no prompt appears, otherwise `.onTap`).

5.1 **Storage:** migration `v1_clips` (§6.11.3) and `ClipRepository`:
- `upsert(ClipDraft) -> Clip` (dedupe by hash, §6.5.4);
- `page(filter: .recent/.pinned, offset:, limit: 50)`;
- `search(query, limit: 50)` (`searchKey LIKE`, pinned first);
- `pin`/`unpin`/`reorderPinned`, `delete(ids)`, `deleteAll(keepPinned:)`;
- `markUsed`, `enforceLimits(settings, now)`, `imageFiles(for:)`.
- Everything `async`. Post `.clips.changed` after writes.

5.2 **`ClipboardKit`:**
- `PasteboardClient` protocol, `LivePasteboardClient` (UIKit, `#if canImport(UIKit)`), `FakePasteboardClient`;
- `ClipClassifier` (§6.5.3);
- `ClipboardMonitor` (§6.5.2) with persisted `lastSeenChangeCount`, the 1 s visible-only timer, and capture modes;
- `ClipboardService` façade used by the UI (capture, insert, copy, delete…).

5.3 **Image clips** (§6.5.8): background downsampling + thumbnail, files under `Clips/`, cleanup on delete.

5.4 **`KeyboardState` integration:** `mode = .clipboard`, `clipChip`, capture on appear/foreground/timer, timer stops on disappear. **End of Session A.**

5.5 **Clipboard panel UI** (§6.5.6): header (tabs Recent/Pinned/Snippets placeholder, 🔍, ⏸, 🗑, ABC), paged `LazyVStack` rows, tap/long-press/swipe actions, undo toast, empty states (no Full Access, empty, paused), RTL-correct rows.

5.6 **Search sub-mode** with `InternalInputRouter` (§6.5.6): temporary +88 pt height, search field, result chips, compact key grid routing to the query, ✕ to exit.

5.7 **Clip chip** in the suggestion strip (§6.5.7), including `.onTap` pending mode and masked sensitive items.

5.8 **Insert logic** in `InputProcessor` (`.insertClip`): smart spacing, `tapAction` variants, no learning from pasted text, undo entry.

5.9 **Edit panel** (§6.4.9):
- ◀ ▶ (hold to repeat), word ◀▶, line start/end;
- Copy/Cut (enabled when `selectedText` isn't empty and Full Access is on);
- Paste (reads the current pasteboard string on tap);
- delete word; Undo (stack of 20);
- an info note on "Select All" not being possible.

5.10 **Toolbar wiring:** clipboard 📋 and edit ⌶ icons open the panels; ABC returns; the side panel's (one-handed) clipboard button works.

5.11 **Quick Settings → Clipboard section:** enabled, capture mode, max items, retention, chip on/off, skip sensitive, images.

5.12 **No-Full-Access behavior:** the clipboard icon shows a small lock; the panel shows setup steps; Copy/Cut/Paste are disabled with an explanation. Everything else keeps working.

5.13 **Retention job:** `enforceLimits` on appear (at most every 10 min) and after inserts.

5.14 **0xDEAD10CC soak:** 30 minutes of switching apps with the clipboard panel used, then check device logs. Record the result.

**Tests**
- Classifier: concealed/transient types skipped; OTP variants (Latin, Persian and Arabic-Indic digits) → expire; password-like → masked; URLs; whitespace; long text truncation.
- Repository: dedupe moves to top and increments `copyCount`; `maxItems` and `retentionDays` enforcement with pinned exempt; expired deletion; search finds `ی` when querying `ي` and `کتابها` when querying `کتاب‌ها`; paging order.
- Monitor with `FakePasteboardClient`: no read when `changeCount` is unchanged; `.onTap` doesn't read contents; own writes don't re-capture; incognito blocks capture.
- Undo stack; edit operation distances (word and line boundaries, RTL inversion).
- Snapshots: panel states (list, empty, no Full Access, search), light and dark.

**Acceptance criteria**
- [ ] Copy text in Safari, Notes and Telegram → open the keyboard anywhere → the chip shows it → tap pastes it.
- [ ] History shows items newest first; pin, unpin, delete (with undo) and clear-all-except-pinned all work; limits and retention apply.
- [ ] Search finds Persian and English clips with normalization (ي/ی, ك/ک, ZWNJ).
- [ ] A password copied from Apple's Passwords app or 1Password is **not** stored (or stored masked and expiring, per setting); an OTP expires after 2 minutes.
- [ ] A copied image shows a thumbnail. Tapping it puts it on the pasteboard and shows the paste instruction.
- [ ] Edit panel: cursor moves correctly in LTR and RTL; Copy/Cut/Paste of a selection works; delete word; undo.
- [ ] Without Full Access the keyboard still types and shows clear instructions in the clipboard panel.
- [ ] Memory with the panel open ≤ +8 MB versus typing. No `0xDEAD10CC` in the 30-minute soak (5.14).

**Manual test**
1. Copy 5 different texts (Persian and English), a link and a photo from different apps.
2. Open Kelid in Messages → 📋: all 7 items, newest first. Pin one. Search "کتاب".
3. Copy an OTP-like `123456` → it appears masked; wait 2 minutes → gone.
4. Select a word in Notes → ⌶ → Copy → the new clip appears → Paste elsewhere.
5. Turn off Full Access → the keyboard still types; the clipboard panel explains how to enable it.

**Pitfalls**
- Read pasteboard **contents** only when `changeCount` changed, or on a user tap (C3).
- After the keyboard writes to the pasteboard itself, update `lastSeenChangeCount` immediately.
- Never decode full-size images on the main thread.
- Short DB transactions. Suspend on disappear.

**Out of scope:** snippets UI (Phase 10), app-side clipboard manager (Phase 10), Share Extension and Shortcuts (Phase 10).

---
### Phase 6 — Language data pipeline (Python, runs on your Mac)

**Goal:** A reproducible pipeline that produces clean Persian and English unigram/bigram/trigram counts, emoji data, held-out evaluation sets, and attribution metadata. The quick path comes first, so Phase 7 can start early.
**Size:** M–L · **Depends on:** Phase 1 (for the shared `vectors.json`) · **Read:** §0.3 row 6
**Session A:** 6.1–6.3 (quick path; then Phase 7 can start) · **Session B:** 6.4–6.14 (full path; runs for hours, so leave it running)
**You get:** the "brain" data for Persian prediction.

**Tasks**

6.1 **Project:** `Tools/data-pipeline/pyproject.toml` (Python ≥ 3.11; deps `hazm`, `duckdb`, `pyarrow`, `regex`, `tqdm`, `requests`; dev `pytest`), managed with `uv` (or `venv`). `README.md` with commands, disk needs (~30 GB) and expected run times. `data/` and `out/*.tsv` are gitignored; `out/*.meta.json` and `reports/` are committed.

6.2 **Normalization module** `pipeline/normalize.py`: implement §6.6.2 and §6.6.4 on top of hazm's `Normalizer`. pytest runs the shared `Packages/KelidKit/Tests/PersianTextTests/vectors.json`, so Swift and Python stay identical.

6.3 **Quick path** `pipeline/quick.py` (`make data-quick`): download hermitdave `fa_full.txt` and `en_full.txt` → normalize → keep valid tokens (Persian letters and ZWNJ only for fa; letters and apostrophes for en) → merge variants that share a canonical form → `out/fa.unigrams.tsv`, `out/en.unigrams.tsv` (`word<TAB>count`), plus `meta.json`. **End of Session A.**

6.4 **Downloads** `pipeline/download.py`: `fawiki-latest-pages-articles.xml.bz2` and an English Wikipedia dump (or a subset), resumable, verified against Wikimedia's published checksums; Lilak word list; Unicode `emoji-test.txt`; CLDR annotations (fa, en, derived).

6.5 **Extraction:** `wikiextractor` → JSON lines → `pipeline/wiki_text.py` → plain paragraphs (drop tables, references, lists shorter than 3 words).

6.6 **Normalize and tokenize** in parallel (multiprocessing) → parquet shards `(sentence_id, pos, token)`:
- insert the special token `<s>` at every sentence start;
- replace numbers with `<num>` and URLs/emails with `<url>`;
- drop lines with < 50% Persian letters (fa).
- **Hold out** every article whose ID hash mod 100 == 0 for evaluation (never counted).

6.7 **Counting** with DuckDB:
- unigram, bigram and trigram counts using `LEAD(token, 1/2) OVER (PARTITION BY sentence_id ORDER BY pos)`, with `HAVING count >= 3` for n ≥ 2;
- set `PRAGMA memory_limit` and a temp directory on a disk with enough space.

6.8 **Informal merge:** add hermitdave frequencies (per-million normalized, × `w_informal = 3.0`) to the unigram counts. Optional flag `--with-opensubtitles-text` (personal builds only) adds informal n-grams from OPUS OpenSubtitles text.

6.9 **Vocabulary selection:**
- valid-token regex;
- Lilak whitelist boost;
- cap at 200 k (fa) / 120 k (en);
- flag offensive words from curated `offensive_{fa,en}.txt`;
- drop n-grams that contain out-of-vocabulary words, `<num>` or `<url>`. `<s>` stays as a context-only token.

6.10 **Export:** `out/<lang>.unigrams.tsv` (`word, count, flags`), `<lang>.bigrams.tsv` (`w1, w2, count`), `<lang>.trigrams.tsv` (`w1, w2, w3, count`), `<lang>.meta.json` (sources, dump dates, licenses, parameters, counts). Append the attribution text to `docs/ATTRIBUTIONS.md`.

6.11 **English:** the same pipeline with `--lang en` (English tokenizer; keep the original case and add a lowercase key).

6.12 **Emoji data** `pipeline/emoji.py` → `Packages/KelidKit/Sources/EmojiData/emoji.json` (§6.9) and `out/emoji_suggest_{fa,en}.tsv` (keyword → up to 3 emoji, most common first).

6.13 **Evaluation sets** from the held-out articles and subtitles: `eval/fa_formal.txt`, `eval/fa_informal.txt` (if available), `eval/en.txt`, 5 000 sentences each.

6.14 **Reports** `reports/<lang>.md`: top 200 words; the top 10 continuations for probe contexts (`<s>`, `من`, `می‌خواهم`, `در`, `به`, `the`, `I`); coverage and OOV rate on the eval sets; run time and sizes.

**Tests (pytest):** normalization vectors; tokenization keeps ZWNJ words whole; `<s>` insertion; the DuckDB counting SQL on a 20-sentence fixture gives exact expected counts; vocabulary filter rules.

**Acceptance criteria**
- [ ] `make data-quick` finishes in under 5 minutes and produces both unigram TSVs.
- [ ] `make data-full` finishes (hours are OK) and produces all outputs within the size caps.
- [ ] **You** read `reports/fa.md`: the top words and continuations look like natural Persian (formal and colloquial).
- [ ] `docs/ATTRIBUTIONS.md` lists every source with its license.

**Pitfalls**
- Wikipedia is formal Persian: without the informal merge, colloquial forms (میخوام، اینجوری) rank too low.
- Keep normalization identical in Swift and Python (shared vectors).
- Process in streams and shards; don't load whole dumps into RAM.

**Out of scope:** Swift binary building (Phase 7/8).

---

### Phase 7 — Prediction I: lexicon, completions, suggestion bar (Size L)

**Goal:** Word completion from the first letter in Persian and English, shown in a real suggestion bar, using the memory-mapped KLM model.
**Size:** L · **Depends on:** Phases 3 and 6 (Session A) · **Read:** §0.3 row 7
**Session A:** 7.1–7.5 · **Session B:** 7.6–7.12
**You get:** Persian word suggestions while typing.

**Tasks**

7.1 **`PersianText`**, full implementation of §6.6 (canonical, matchKey, searchKey, word characters, tokenization, direction), passing the shared `vectors.json`.

7.2 **KLM writer and reader** in `PredictionEngine` (§6.7.2):
- `KLMWriter` (used by the `klm` tool);
- `KLMFile`: `open()` + `mmap(PROT_READ, MAP_PRIVATE)`, `munmap` in `deinit`, header/section validation, bounds-checked accessors in debug builds;
- mark it `@unchecked Sendable` with a comment (read-only memory).

7.3 **`Lexicon`:** `surface(id)`, `score(id)`, `flags(id)`, trie child search (binary search on labels), `completions(prefixKey, limit)` with best-first search (`Heap`), `wordID(forSurface:)`.

7.4 **`klm` tool** (`Tools/klm`):
- `klm build --lang fa --unigrams out/fa.unigrams.tsv [--bigrams …] [--trigrams …] --out Keyboard/Resources/LM/fa.klm` (n-gram flags accepted but only implemented in Phase 8);
- `klm inspect --model … --stats | --prefix میخ --top 10`.
- `make klm` builds both languages.

7.5 **Resources and locator:** add `Keyboard/Resources/LM/*.klm` to the keyboard target (not the package). `ModelLocator` finds models in the extension bundle, and from the app through `Bundle.main.builtInPlugInsURL`. **End of Session A.**

7.6 **`SuggestionService`** actor (§6.7.4), completion-only for now:
- loads models in a background `Task` (utility priority) after the first frame;
- generation handling; results only for the current language.

7.7 **`TypingContext`** extraction wired from `InputProcessor` (§6.4.8). A request is sent after every action that changes text or cursor.

7.8 **Suggestion bar** (SwiftUI) and toolbar `.auto` mode (§6.1.4, §6.7.5):
- verbatim/best/second slots, mirrored in RTL, bold best;
- tap → `.insertSuggestion` → word replacement (§6.4.8) + space + `autoSpacePending`;
- long-press shows a placeholder menu ("Don't suggest" arrives in Phase 9);
- the clip chip (Phase 5) keeps its leading position when present.

7.9 **Persian specifics:** loose matching through `matchKey`; canonical ZWNJ surfaces when `preferZWNJForms`; dedupe by canonical form. For example, typing `میخ` should offer `می‌خوام` / `می‌خواهم` / `میخ`.

7.10 **English casing** (§6.7.5).

7.11 **Settings wiring:** `prediction.<lang>.enabled`, `suggestionCount`, `showVerbatimSlot`, `preferZWNJForms`, `toolbar.mode` (Quick Settings + app placeholders).

7.12 **Benchmarks:** XCTest `measure` for 1-character and 3-character prefixes (simulator), plus on-device numbers from the debug overlay, recorded in PROGRESS.md.

**Tests**
- Writer → reader round trip on a 60-word fixture (ZWNJ variants, آ/ا variants, English).
- Best-first completions equal brute-force top-K on random prefixes (property test).
- `wordID(forSurface:)`; surface choice with `preferZWNJForms`.
- Suggestion accept with `MockTextDocument` (plain, ZWNJ word, diacritics, English apostrophe); stale generations dropped; casing; RTL slot order (snapshot).

**Acceptance criteria**
- [ ] Persian completions appear from the first letter and are sensible; tapping inserts the word plus a space.
- [ ] Typing feel is unchanged. Suggestion p95 ≤ 20 ms on device. Memory +≤ 3 MB dirty (the mapped file doesn't count).
- [ ] English completions and casing work.

**Manual test:** type `سلا`, `کتا`, `میخ`, `دان`, `خوا` and check the suggestions. In English: `hel`, `The`, `GRE`. Tap suggestions, then check spacing before punctuation (`سلام` + tap + `.` → `سلام.`).

**Pitfalls:** don't load the `.klm` into `Data` (heap). Use `mmap`. Keep the actor free of UIKit.

**Out of scope:** next-word, typos, autocorrect, learning.

---

### Phase 8 — Prediction II: next word, typo tolerance, autocorrect (Size L)

**Goal:** Context-aware predictions (next word after a space, context-ranked completions), proximity- and homophone-aware typo correction, autocorrect modes with revert, emoji suggestions, and measured quality baselines.
**Size:** L · **Depends on:** Phases 6 (full) and 7 · **Read:** §0.3 row 8
**Session A:** 8.1–8.4 · **Session B:** 8.5–8.11
**You get:** smart Persian and English prediction.

**Tasks**

8.1 **n-gram sections:** implement `BIDX/BENT/TIDX/TENT` in the writer and reader, with builder caps and top-K (§6.7.2). `<s>` is a hidden vocabulary entry (never suggested). Add `klm inspect --next "<s>" | "من" | "می‌خواهم"`.

8.2 **Stupid Backoff scorer** and **next-word predictions** when the prefix is empty (after space or at sentence start) (§6.7.3).

8.3 **Context-aware completion candidates** (§6.7.3, last bullet).

8.4 **Fuzzy search:** `ProximityMap` from the current layout (Phase 2) sent to the service on layout or size change; weighted Damerau–Levenshtein trie search with Persian groups (§6.6.6), prefix mode and the visit budget. **End of Session A.**

8.5 **`Ranker`** + `RankerConfig` (§6.7.5): blending hook (λ = 0 until Phase 9), dedupe, offensive filter, slots.

8.6 **Autocorrect** (§6.7.9): `.off` / `.suggestOnly` / `.auto`, per-language defaults, field-trait checks, `lastAutocorrection`, revert on backspace (§6.4.6).

8.7 **Emoji suggestions** (§6.7.10): compact resource built from the TSVs by `klm build-emoji`, loaded lazily, trailing compact slot.

8.8 **Expanded suggestions** (optional): a chevron in the bar opens a panel with up to 12 candidates.

8.9 **Eval harness** `klm eval` (§6.7.12): run the baselines for fa formal, fa informal and en; tune the `RankerConfig` constants; write the metrics table to PROGRESS.md.

8.10 **Performance:** fuzzy budget tests; on-device p95 check for 8-character words.

8.11 **Settings wiring:** `nextWord`, `autocorrect`, `autocorrectStrength`, `emojiSuggestions`, `blockOffensive`.

**Tests**
- Backoff math on fixtures; `<s>` handling; next-word ordering.
- Fuzzy: adjacent-key substitution (`سلان` → `سلام`), homophones (`صلام` → `سلام`, `طهران`/`تهران`), transposition (`teh` → `the`), insertion/deletion, budget cut-off.
- Autocorrect decision table: known word → no change; URL field → no change; blocked pair → no change; margin rule; revert restores the exact text.
- Eval harness on a tiny fixture gives the expected KSR.

**Acceptance criteria**
- [ ] After `من ` the bar shows plausible next words. After `<s>` (a new sentence) it shows common sentence starters.
- [ ] `سلان` → best is `سلام`. English `teh ` → auto-corrects to `the `, and backspace reverts it.
- [ ] No autocorrect in URL, email or password-like fields.
- [ ] KSR and next-word baselines recorded. p95 ≤ 20 ms on device.

**Manual test:** write a real message in Persian (colloquial) and one in English, using only suggestions where possible. Note bad suggestions in PROGRESS.md; they become tuning input.

**Out of scope:** personal learning (Phase 9).

---

### Phase 9 — Personal learning and prediction source modes (Size L)

**Goal:** The keyboard learns your words and phrases, and you choose where predictions come from: **Off / Personal only / Language only / Hybrid**, with a personal-weight slider, per language. Includes privacy rules, incognito, block/forget, text replacements and contact names, and a local-to-shared data merge.
**Size:** L · **Depends on:** Phase 8 · **Read:** §0.3 row 9
**Session A:** 9.1–9.5 · **Session B:** 9.6–9.12
**You get:** predictions that sound like you.

**Tasks**

9.1 **Migration `v1_user_model`** (§6.11.3) and `UserModelRepository`: batch UPSERT of stats, load capped sets, block/unblock, forget (word + its n-grams), prune, merge (local → shared).

9.2 **`UserModel`** actor (§6.7.6): interning, prefix index, decay math, probability functions, dirty-set write-behind (5 s / disappear / background), reload on `.userdict.changed`, in-memory caps.

9.3 **Commit detection → `CommitEvent`** in `InputProcessor` (§6.7.8):
- triggers, previous words within the sentence, learnability filters;
- sensitive-field and incognito checks;
- no learning from clips or snippets;
- source tags (`typed` / `accepted` / `verbatim` / `revert`).

9.4 **Blending** in `Ranker` (§6.7.5, §6.7.7):
- the four modes and the `personalWeight` λ;
- Personal-only uses user candidates only, with fuzzy search over a small trie built from user words at load time;
- new-word threshold;
- blocklists in every mode.

9.5 **Suggestion long-press menu:** *Don't suggest "…"* (block), *Forget "…"* (delete personal data for the word), with a toast confirmation. Autocorrect revert → `blockedCorrections`. **End of Session A.**

9.6 **Supplementary lexicon:** `requestSupplementaryLexicon` on appear (cached for 1 hour). Text replacements appear as the best suggestion when the typed word equals the shortcut (`useTextReplacements`); contact names become no-decay user words (`useContactNames`).

9.7 **Incognito:** a toolbar toggle (eye-slash icon), a tinted toolbar while active, no learning, no clipboard capture, no chip.

9.8 **Quick Settings → Prediction:** per current language: source picker, personal-weight slider (hybrid only), learning on/off, incognito, "Clear my learned words for this language" (confirm).

9.9 **No-Full-Access path:** local user DB (§6.11.2) and merge on the first run with Full Access; the merge result is logged in the debug overlay.

9.10 **"Still learning" hint** in Personal-only mode when the user model has fewer than 200 words.

9.11 **Eval with personalization:** simulate learning from half of `fa_informal` and measure KSR on the other half, hybrid vs language-only. Record the result.

9.12 **Memory check:** UserModel ≤ 6 MB with 20 k words (measure with a synthetic load).

**Tests**
- Decay math (`TestClock`), thresholds, increments by source.
- Blending per mode on fixtures (Personal-only returns only user words; Language-only ignores the user model; λ extremes).
- Block/forget; correction block; commit detection sequences (type → space; type → suggestion; type → backspace edits → space; punctuation; newline; cursor jump resets context).
- Privacy filters (sensitive fields, incognito, digits, URLs, mixed script, repeated letters); local→shared merge.

**Acceptance criteria**
- [ ] A new slang word typed twice (e.g. `خفنه`) is suggested afterwards in Hybrid and Personal-only, and not in Language-only.
- [ ] Your frequent phrases rise to the top in Hybrid after some use.
- [ ] Blocked words never appear; Forget removes a word.
- [ ] Incognito and sensitive fields learn nothing (verify DB counts before and after).
- [ ] Text replacements from iOS Settings appear as suggestions.
- [ ] Personalized KSR ≥ language-only KSR on the eval split (9.11).

**Manual test:** use Kelid as your main keyboard for 2 days in Hybrid mode, then switch to Personal-only for a while and compare. Check that nothing was learned in a password manager's search field (a sensitive field).

**Out of scope:** the app dictionary manager (Phase 10).

---

### Phase 10 — Companion app: settings, managers, capture helpers (Size L)

**Goal:** A polished app: onboarding, status, every setting, a full clipboard and snippet manager, a dictionary manager with "learn from text", Share Extension capture, Shortcuts/App Intents (Back Tap), backup/restore, about/licenses. Text expansion from snippets works in the keyboard.
**Size:** L · **Depends on:** Phases 5 and 9 · **Read:** §0.3 row 10
**Session A:** 10.1–10.5 · **Session B:** 10.6–10.12
**You get:** everything manageable from a real app.

**Tasks**

10.1 **App shell:** 5 tabs (§6.10); `NavigationStack`s; shared services (`SettingsStore`, `DatabaseManager`, repositories); String Catalogs en/fa; RTL check; remove the Phase 1 debug toggle.

10.2 **Onboarding** (§6.10): 5 steps, a Settings deep link, illustrations (SF Symbols or simple drawings), heartbeat-based status.

10.3 **Settings screens** for **every** key in §6.1, grouped as in §6.1, with a live `KeyboardPreview` on Size & Layout and Appearance. Changes post `.settings.changed`.

10.4 **Clipboard manager:** lists, search, filters, full-text edit, pin/reorder pinned, multi-select delete, "Add from clipboard" with `UIPasteControl`, clear, retention, `ignorePatterns` editor with a live test field, optional Face ID lock.

10.5 **Snippets:** migration `v1_snippets` (if not done), folder and snippet CRUD, reorder, shortcut field with uniqueness validation. Keyboard: the Snippets tab in the clipboard panel; **text expansion** in `InputProcessor` (a shortcut followed by space is replaced by the snippet; `snippets.expansionEnabled`; undo-able). **End of Session A.**

10.6 **Dictionary manager:** per-language learned words (search, sort, delete, block/unblock), add a word manually, **Learn from text** (paste or `.txt` import → `PersianText` tokenization → preview of top new words and counts → commit), reset personal data.

10.7 **Share Extension `KelidShare`:** accepts text, URLs and images → saves a clip (`source = share`) → small confirmation UI → completes. Handle database suspend/resume. Add it to `project.yml` with the App Group entitlement.

10.8 **App Intents:**
- `SaveTextToKelidIntent(text:)` and `ClearKelidHistoryIntent`;
- an `AppShortcutsProvider` with English and Persian phrases;
- an in-app guide for building **Get Clipboard → Save to Kelid** in Shortcuts, and assigning it to **Back Tap** (Settings → Accessibility → Touch → Back Tap).

10.9 **Backup and restore** `.kelidbackup` (§6.11.7): export with `ShareLink`; import with `fileImporter` and merge; the user chooses whether to include personal words.

10.10 **About:** version, privacy statement (from `docs/PRIVACY.md`), acknowledgements (from `docs/ATTRIBUTIONS.md`), data-source credits, "Delete all Kelid data".

10.11 **App icon and accent color** (simple placeholder design).

10.12 **Tests:** view-model unit tests (settings binding, clipboard filters, learn-from-text tokenization and preview); a UI test for onboarding navigation and clipboard CRUD; manual test for the Share Extension.

**Acceptance criteria**
- [ ] Every setting can be changed in the app and reaches the keyboard within 1 s (Full Access on, keyboard visible in the Try-it field) or on the next appearance.
- [ ] Clipboard and snippets are fully manageable; snippet expansion works while typing.
- [ ] Sharing text, a URL or an image from Safari/Photos into Kelid creates a clip.
- [ ] The Shortcut + Back Tap flow saves the current clipboard.
- [ ] Backup → delete all data → restore brings everything back.
- [ ] The app is fully usable in Persian (RTL) and English.

**Manual test:** go through onboarding again from scratch (delete and reinstall the app); set up Back Tap; create 3 snippets with shortcuts and use them; share an image from Photos; back up and restore.

**Out of scope:** the theme editor (Phase 11), emoji (Phase 12).

---

### Phase 11 — Themes, fonts, sounds, haptics

**Goal:** Full theming (§6.8): 12+ built-in themes, automatic light/dark, custom themes with photo backgrounds, Vazirmatn, sound packs, haptic strength, key animations, and a theme editor with live preview and import/export.
**Size:** M–L · **Depends on:** Phases 3 and 10 · **Read:** §0.3 row 11
**You get:** a keyboard that looks the way you want.

**Tasks**

11.1 **`ThemeKit`:** theme model, JSON coding, validation (contrast warnings), the built-in themes (§6.8.2) as resources, the resolver (§6.8.3), custom theme storage in the App Group, `.themes.changed`.

11.2 **Apply themes** to `KeyView`/`KeyGridView` (`KeyStyle` from the theme), the toolbar, suggestion bar, popups, panels (a SwiftUI environment value `KelidTheme`), and the side panel.

11.3 **Backgrounds:** color, gradient (`CAGradientLayer`), image (pre-baked blur and dim, loaded downsampled, one instance), material (`UIVisualEffectView`).

11.4 **Fonts:** bundle Vazirmatn (Regular, Medium) in the app and keyboard, register at startup, `persianFont` / `latinFont` / weight / scale.

11.5 **Sounds:** system sounds plus 2 custom packs (§6.8.5).

11.6 **Haptics:** strength setting and the Low Power Mode rule (§6.8.6).

11.7 **Key-press animations:** `.none`, `.pop` (scale 1.0 → 1.08 → 1.0 on the popup only), `.fade`. Respect Reduce Motion.

11.8 **App theme gallery and editor** (§6.8.7) with `KeyboardPreview`, photo picking with baked blur/dim (≤ 1.5 MB JPEG), duplicate/delete, set light/dark/fixed, import/export `.kelidtheme` (UTType declaration + document handling).

11.9 **Quick Settings → Appearance:** theme pickers (built-in + custom thumbnails), theme mode, sounds, haptics.

**Tests:** decoding/validation of all built-ins; resolver matrix (mode × appearance × trait); snapshot of every built-in theme for fa and en letters pages (light and dark); export → import round trip.

**Acceptance criteria**
- [ ] Theme switches are instant. Photo backgrounds look right and cost ≤ +5 MB.
- [ ] Automatic dark/light follows the host (`keyboardAppearance`) and the system.
- [ ] An exported theme imports on another device or after reinstalling.
- [ ] With Vazirmatn selected, Persian labels render in Vazirmatn; digits render correctly.

**Manual test:** make a theme from a photo; switch the phone between dark and light mode; try the Contrast theme outdoors in sunlight.

---

### Phase 12 — Emoji panel and search

**Goal:** A fast, memory-safe emoji panel with categories, recents, skin tones, and Persian/English search (§6.9).
**Size:** M · **Depends on:** Phases 5 (search router) and 6.12 (data) · **Read:** §0.3 row 12

**Tasks**

12.1 **`EmojiData`:** load `emoji.json` lazily; version filtering (§6.9); a search index (keyword `searchKey` prefix → emoji list); recents; skin-tone preferences.

12.2 **Emoji panel:**
- category bar;
- horizontally paged `UICollectionView` (compositional layout; cells with a single `UILabel`);
- `ABC` and ⌫;
- tap inserts (as an `.character` action, so undo works);
- long-press → skin tones.

12.3 **Search** through the `InternalInputRouter` sub-mode (§6.5.6) with Persian and English keywords.

12.4 **Bottom-row emoji key** option (§6.2.6) and a toolbar emoji icon.

12.5 **Memory hygiene:** release the collection view when the panel closes; purge caches on memory warnings; measure (§6.13).

12.6 **Optional quick-symbols page** (→ ✓ ★ ♥ ☺ ✔ « » ﷼ ٪) as a tab in the emoji panel.

**Tests:** search (`قلب` → ❤️-family, `خنده` → 😀/😂, `heart`); version filtering; recents ordering; skin-tone persistence.

**Acceptance criteria**
- [ ] Scrolling is smooth (no hitches) on an iPhone XS/11-class device.
- [ ] Search works in Persian and English.
- [ ] Peak memory ≤ 45 MB with the panel open; baseline + ≤ 3 MB after closing, over 20 open/close cycles.

---

### Phase 13 — Hardening, polish, release prep

**Goal:** Meet every budget in §6.13 on real devices; fix robustness issues across host apps; accessibility; localization; privacy manifests; App Store readiness.
**Size:** M–L · **Depends on:** Phases 0–12 · **Read:** §0.3 row 13

**Tasks**

13.1 **Performance pass:** Instruments Time Profiler while typing and while suggesting; remove main-thread hot spots; cold-start profiling (lazy services, fewer allocations at launch).

13.2 **Memory pass:** Allocations, Leaks, VM Tracker; 50 show/hide cycles; old `UIInputViewController` instances; panel release; image caches.

13.3 **Robustness across hosts** (§9 matrix): `nil` contexts, weird deletion behavior, very long documents, rapid rotation, apps that reload input views often, low-memory warnings (drop caches), the database unavailable before first unlock.

13.4 **Accessibility:** VoiceOver typing and panels; Dynamic Type in the app; Reduce Motion; Increase Contrast (auto-select the Contrast theme option); an optional **larger key labels** setting.

13.5 **Localization audit:** en/fa completeness, plurals, RTL layout of every screen and panel, Persian digits in the app where appropriate.

13.6 **Privacy manifests** for all targets (§6.12); verify with Xcode's privacy report; `docs/PRIVACY.md` final.

13.7 **App Store prep** (if publishing):
- icons, screenshots checklist, descriptions (en/fa), keywords;
- review notes explaining Full Access usage and that there is no network access;
- a Guideline 4.4.1 checklist (next-keyboard key, works without Full Access, no app launching, no repurposed keys);
- TestFlight build.

13.8 **Bug bash:** run the full §9 matrix; fix all P0/P1 bugs.

13.9 **Docs:** README final; `docs/ARCHITECTURE.md` (a short summary of §4 as built); `docs/ATTRIBUTIONS.md` complete.

**Acceptance criteria**
- [ ] Every §6.13 budget is met on the oldest supported device you have.
- [ ] The §9 matrix passes; no known crashes; a 1-week daily-use test has no jetsam kills.
- [ ] Privacy report clean. The 4.4.1 checklist passes.

---

### Phase 14 — (Optional) Glide / swipe typing

**Goal:** Type words by sliding across letters (Persian and English).
**Size:** L · **Depends on:** Phase 8

**Tasks**

14.1 **Gesture detection:** a touch that starts on a letter key and moves more than 1.5 key widths across other letter keys (and isn't the space trackpad) becomes a glide. Record points (x, y, t); draw a fading trail (`CAShapeLayer`, theme color).

14.2 **Candidates:** words whose first/last letters are near the path's start/end keys, and whose key sequence is a subsequence of the keys the path passed (with neighbor tolerance), via trie traversal with pruning.

14.3 **Scoring (SHARK²-style):**
- *shape* distance: resample both the user path and the word's ideal path (lines through key centers) to 64 points, normalize scale and translation, take the mean distance;
- *location* distance: alignment-weighted;
- combined with the LM context score.
- Reference: FlorisBoard's statistical glide classifier (Apache-2.0); port with attribution.

14.4 **UI:** the best word is inserted with a space; alternatives in the suggestion bar replace it on tap. The first glide after a glide word inserts the space automatically.

14.5 **Performance:** ≤ 50 ms decode on a background actor. **Settings:** enable, show trail.

**Acceptance:** common words (and your frequent words) glide correctly more than 85% of the time in a 100-word test.

---

### Phase 15 — (Optional) Finglish → Persian

**Goal:** Type Persian with Latin letters ("salam khoobi?") and get Persian suggestions ("سلام خوبی؟").
**Size:** M · **Depends on:** Phase 8

**Tasks**

15.1 **Mapping table** `finglish.json`:
- multi-letter units first: kh→خ, gh→ق/غ, sh→ش, ch→چ, zh→ژ, ou/oo→و;
- vowels: a→ا/َ(omit)/آ, e→(omit)/ه/ع, o→و/ُ(omit), i/ee→ی, u→و;
- consonant alternatives: s→س/ص/ث, z→ز/ذ/ض/ظ, t→ت/ط, h→ه/ح;
- each option has a cost.

15.2 **Beam search** over the Persian trie: state = (input position, trie node, cost). Short vowels may be omitted. Width 64; score = LM context log-probability − mapping cost.

15.3 **UI:** in the English layout with "Finglish suggestions" on (or a third language state `Fin`): the Latin verbatim goes in the leading slot and Persian candidates in the others. Tapping a Persian candidate replaces the Latin word.

15.4 **Learning:** chosen pairs (Latin → Persian) are boosted in the user model.

15.5 **Eval:** a hand-made set of 300 Finglish→Persian pairs (you can help write it). Target: top-3 ≥ 80%.

---

### Phase 16 — (Optional, experimental) On-device neural re-ranker

**Goal:** Better next-word ranking with a tiny neural model, **only if** it measurably helps within the memory budget.
**Size:** L · **Depends on:** Phase 13

**Tasks**

16.1 Train offline (PyTorch) a small LSTM or transformer (≤ 5 M parameters) on the Phase 6 corpus. Quantize (int8, ≤ 6 MB). Convert with coremltools.

16.2 Use it only to **re-rank the top 20** n-gram candidates. Run asynchronously, with a 15 ms timeout (fallback: the n-gram ranking).

16.3 Measure memory (model weights count against the limit!), latency and KSR.

16.4 **Ship only if** KSR improves by ≥ 2 points and peak memory stays ≤ 45 MB. Otherwise document the result and drop it.

---

### Phase 17 — (Optional) iCloud sync and iPad

**Goal:** Sync snippets, pinned clips (opt-in), personal words (opt-in), themes and settings across your devices; proper iPad layouts.
**Size:** L · **Depends on:** Phase 13 · **Needs:** a paid developer account (CloudKit)

**Tasks**

17.1 **CloudKit** private database, used **only by the app** (the keyboard reads the local DB). Records per entity; last-writer-wins, except user-word counts, which merge (sum per device ID).

17.2 **Sync triggers:** app launch/foreground, `BGAppRefreshTask`, and manual "Sync now".

17.3 **iPad:** `padPortrait` / `padLandscape` size profiles; iPad layouts with extra keys (tab, caps, return in row 2); test Stage Manager and external keyboards (only the toolbar shows).

---

### Phase 18 — (Optional) More layouts and a custom layout editor

**Tasks**
- 18.1 More built-in layouts: English Colemak, Dvorak, AZERTY, QWERTZ; Persian "legacy/Windows" arrangement.
- 18.2 Import a custom layout JSON in the app (validator + live preview), share layouts.
- 18.3 Optional: Arabic or Kurdish (Sorani) layouts. **Note:** prediction needs a new KLM for each new language (rerun Phase 6 for it).

---

## 9. QA matrix

**Devices** (use what you have; at least two): the oldest supported iPhone you can get (XS / 11 / SE 2-3) · a modern standard iPhone · a Pro Max if available · one iPad (basic check).
**iOS versions:** the minimum (17.x) if possible, plus the latest.

**Host apps:** Notes · Messages · Mail · Safari (address bar + a web form) · WhatsApp · Telegram · Instagram (comments, DM) · X · Chrome · Gmail · Google Docs · Microsoft Word or Pages · a banking app (expect a refusal: verify graceful fallback) · Kelid's own Try-it field.

**Scenarios (tick per device × iOS):**

| # | Scenario | Expected |
|---|---|---|
| 1 | Fast two-thumb typing, Persian and English | No dropped or reordered letters |
| 2 | Mixed RTL/LTR text, cursor trackpad and arrow keys | Cursor moves visually as expected |
| 3 | Suggestion accept, then punctuation | Correct spacing (`word.`) |
| 4 | Autocorrect + immediate backspace | Revert to the typed word |
| 5 | Copy in app A → keyboard in app B | Chip appears, one tap pastes |
| 6 | Password / OTP copy | Skipped or masked + expiring |
| 7 | 1000 clips, search | Instant results (< 100 ms), smooth scrolling |
| 8 | Resize, rotate, one-handed, lift | Persisted per orientation; no layout warnings |
| 9 | Full Access off | Keyboard works; clear explanations |
| 10 | Dark/light switch, keyboardAppearance dark hosts | Correct theme |
| 11 | Emoji panel open/close ×20 | Memory back to baseline |
| 12 | Low Power Mode | Haptics reduced per setting; no other change |
| 13 | Reboot → before first unlock (reply from a notification) | Keyboard works without clipboard/personal data; no crash |
| 14 | Storage almost full | DB errors handled; no crash |
| 15 | Switch keyboards rapidly (globe) ×30 | No crash, no memory growth |
| 16 | VoiceOver typing | Keys announced; lift-to-type works |
| 17 | Incognito | Nothing learned or captured |
| 18 | 1 week daily use | No jetsam kills (check Analytics Data) |

Record results in `docs/QA-CHECKLIST.md` with the date, device and iOS.

---

## 10. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Paste banners/prompts on some iOS versions | Clipboard feels noisy | `changeCount` gating, `.onTap` capture mode, on-device lab (5.0), Share/Shortcut capture paths |
| Memory-limit kills | Keyboard disappears | Budgets, mmap models, lazy panels, per-phase device measurement, memory-warning cache purge |
| `0xDEAD10CC` from the shared DB | Random kills | GRDB suspension + short transactions; JSONL-journal fallback (§6.11.6) |
| Weak Persian data | Bad suggestions | Formal + informal sources, eval harness, personal learning, native-speaker review (you) |
| Host app quirks | Wrong deletions or context | `TextDocument` verification, shadow buffer, the §9 host matrix |
| AI-generated code drifts from the architecture | Messy, fragile code | CLAUDE.md rules, one phase per session, acceptance checklists, review prompt, PROGRESS decision log |
| Swift 6 concurrency friction | Slow progress | MainActor default isolation in UI targets, clear actor boundaries, pure-logic engines |
| App Store rejection | Can't publish | Guideline 4.4.1 compliance from day one, degraded mode, privacy manifests, honest review notes |
| Apple Developer Program not available in your country | No App Store / TestFlight | Free-account personal builds (7-day re-sign); the plan works fully for personal use |
| Licensing mistakes | Legal risk when publishing | §7 license table, no GPL code in the app, `docs/ATTRIBUTIONS.md` |

---

## Appendix A — CLAUDE.md (created in Phase 0)

Copy this into `CLAUDE.md` at the repo root (fill in `<prefix>`):

````markdown
# Kelid — rules for AI coding sessions

Kelid is a custom iOS keyboard (Persian + English): clipboard manager, resizing, prediction + personal learning, themes.
**PLAN.md is the source of truth. PROGRESS.md holds status, handoff notes and the decision log.**

## Session protocol
1. Read this file, then PROGRESS.md.
2. In PLAN.md read ONLY §0.3's sections for the current phase plus that phase's section
   (search for "### Phase N"). Never read the whole PLAN.md.
3. Work task by task. After each task: `make build && make test`. Fix failures before continuing.
4. Never tick a checklist item you haven't verified.
5. At the end: update PROGRESS.md (checklist, handoff notes, decision log, measurements), then commit
   `Phase N: <title>` (or `Phase N (tasks a–b): …` for split sessions).

## Hard rules
- No networking anywhere (URLSession, Network.framework, sockets, web views). No analytics/crash/ads SDKs.
- No private APIs. No responder-chain openURL tricks.
- Never hand-edit Kelid.xcodeproj: edit project.yml, then `make gen`.
- Engine modules (KelidCore, KelidSettings, PersianText, KeyboardLayout, InputEngine, PredictionEngine,
  KelidStorage, ClipboardKit core, ThemeKit model, EmojiData) must not import UIKit/SwiftUI.
  UIKit code is wrapped in `#if canImport(UIKit)`. `swift test` must pass on macOS.
- UITextDocumentProxy only via TextDocument. UIPasteboard only via PasteboardClient. Time only via Clock.
- Keyboard memory: ≤ 30 MB typing, ≤ 45 MB with panels. Language models are mmapped, never loaded into Data.
  Downsample images with ImageIO. Release panels on close.
- Nothing heavy on the main thread (I/O, DB, prediction). DB transactions are short; never across `await`.
- Every new setting: add it to KeyboardSettings with a default, a clamp and tolerant decoding.
- All user-facing strings in String Catalogs (en + fa). Support RTL.
- Dependencies only from PLAN.md §7. Anything else needs a decision-log entry first.
- Swift 6. UI is @MainActor. No force unwraps outside tests. Use Log, not print.
- Package code must be app-extension-safe (no UIApplication.shared).

## Commands
make gen · make build · make test (test-mac + test-ios) · make lint · make format · make klm · make data-quick
Debug the keyboard: scheme "KelidKeyboard" → Run → choose "Kelid" → tap the Try-it field → switch with 🌐.

## Identifiers
Bundle prefix: <prefix> · App: <prefix>.kelid · Keyboard: <prefix>.kelid.keyboard · App Group: group.<prefix>.kelid
````

---

## Appendix B — PROGRESS.md template

````markdown
# Kelid — Progress

## Status
| Phase | Title | Status | Date | Notes |
|---|---|---|---|---|
| 0 | Project bootstrap | ☐ | | |
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

## Current phase checklist
(Copy the acceptance criteria of the current phase here and tick them as they are verified.)

## Handoff notes (newest first)
### YYYY-MM-DD — Phase N (tasks a–b)
- Done:
- Not done / known issues:
- How to test:
- Next step:

## Decision log
| # | Date | Decision | Why | Affects |
|---|---|---|---|---|

## Measurements
| Date | Device | iOS | Metric | Value | Notes |
|---|---|---|---|---|---|

## Device findings
(Pasteboard lab results, deletion behavior per host, sound IDs, height-constraint variant, etc.)
````

---

## Appendix C — Glossary

| Term | Meaning |
|---|---|
| **ZWNJ (نیم‌فاصله)** | Zero-width non-joiner, U+200C. Keeps letters from joining inside one word (می‌خواهم, کتاب‌ها). |
| **Full Access** | The user-granted permission (`RequestsOpenAccess`) that allows pasteboard access, the shared container, sounds, etc. |
| **App Group** | A shared container that the app and its extensions can all use (with Full Access for the keyboard). |
| **`textDocumentProxy`** | The keyboard's only channel to the host text field (insert, delete, move cursor, read nearby text). |
| **Jetsam** | The iOS mechanism that kills processes exceeding memory limits. |
| **mmap** | Mapping a file into memory without copying it. Clean mapped pages barely count against the limit. |
| **KLM** | Kelid Language Model, our binary file format (§6.7.2). |
| **n-gram** | A sequence of n words; bigram = 2, trigram = 3. |
| **Stupid Backoff** | A simple, fast way to score the next word from n-gram counts (Brants et al., 2007). |
| **Noisy channel** | Scoring a candidate by P(word) × P(what was typed \| word). |
| **KSR** | Keystroke savings rate: % of key taps saved by using suggestions. |
| **Darwin notification** | A system-wide, payload-free notification used to signal between our processes. |
| **Heartbeat** | A timestamp the keyboard writes so the app knows it's installed and has Full Access. |
| **Verbatim slot** | The suggestion slot showing exactly what you typed. |

---

## Appendix D — Links

**Apple**
- Creating a custom keyboard: https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- Configuring open access: https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- App Extension Programming Guide, Custom Keyboard (archive, still the most detailed): https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- `UIInputViewController`: https://developer.apple.com/documentation/uikit/uiinputviewcontroller
- App Review Guidelines (4.4.1 Keyboards): https://developer.apple.com/app-store/review/guidelines/
- Supported capabilities by membership: https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Privacy manifest files: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files

**Libraries and references**
- GRDB, *Sharing a Database*: https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/DatabaseSharing.md
- KeyboardKit 9.9.1 (last MIT): https://github.com/KeyboardKit/KeyboardKit/tree/9.9.1
- Clip (public domain keyboard + clipboard): https://github.com/rileytestut/Clip
- Hamster: https://github.com/imfuxiao/Hamster
- FlorisBoard: https://github.com/florisboard/florisboard
- AOSP LatinIME: https://android.googlesource.com/platform/packages/inputmethods/LatinIME/
- XcodeGen: https://github.com/yonaskolb/XcodeGen

**Persian data and tools**
- hazm: https://github.com/roshan-research/hazm
- Lilak: https://github.com/b00f/lilak
- FrequencyWords: https://github.com/hermitdave/FrequencyWords
- HeliBoard/AOSP dictionaries: https://codeberg.org/Helium314/aosp-dictionaries
- Vazirmatn: https://github.com/rastikerdar/vazirmatn
- Wikimedia dumps: https://dumps.wikimedia.org/fawiki/
- Unicode CLDR: https://cldr.unicode.org · Emoji data: https://unicode.org/Public/emoji/

---

*End of plan. Start with §0.4, then Phase 0.*
