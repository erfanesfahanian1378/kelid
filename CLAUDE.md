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
Bundle prefix: com.example · App: com.example.kelid · Keyboard: com.example.kelid.keyboard · App Group: group.com.example.kelid

Note: `com.example` is the checked-in default (works for anyone who clones the repo and builds for the
Simulator). Your real, personal prefix lives only in the gitignored `Config/Local.xcconfig` — see README.md.
