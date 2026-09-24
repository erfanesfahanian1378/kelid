# Kelid (کلید)

A custom iPhone keyboard: clipboard manager, live resizing, Persian word prediction with personal
learning, and themes — 100% on-device, no network access. See [PLAN.md](PLAN.md) for the full design
and phase-by-phase build plan, and [PROGRESS.md](PROGRESS.md) for current status.

## Prerequisites

- A Mac with the latest stable **Xcode** (26 or newer) and its Command Line Tools.
- An iPhone on **iOS 17+**. The Simulator is fine for most work, but memory limits, haptics, sounds and
  real clipboard behavior must be tested on a physical device.
- An **Apple ID**:
  - *Free account* — enough to build and run on your own iPhone. Installs expire after 7 days, so you
    re-run from Xcode.
  - *Paid Apple Developer Program ($99/year)* — needed for TestFlight, the App Store, and installs that
    don't expire weekly.
- Homebrew tools: `brew install xcodegen swiftformat swiftlint git-lfs`
- Python 3.11+ (only needed later, for the Phase 6 language-data pipeline).
- ~30 GB free disk (only needed later, for Phase 6).

## Getting started

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# edit Config/Local.xcconfig: set KELID_BUNDLE_PREFIX to something like com.yourname,
# and KELID_TEAM_ID to your Apple Developer Team ID (Xcode → Settings → Accounts).

make gen && open Kelid.xcodeproj
```

`Config/Local.xcconfig` is gitignored — it holds your personal bundle prefix and Team ID. Everything
checked into the repo uses the placeholder prefix `com.example`, which is enough to build for the
Simulator without any Apple account configured.

`Kelid.xcodeproj` itself is generated and gitignored. Run `make gen` again any time you edit
`project.yml`. **Never hand-edit `Kelid.xcodeproj`.**

## Signing notes

- **Free account:** in Xcode → Signing & Capabilities, let Xcode register the App Group automatically if
  signing fails the first time. Installs on your iPhone expire after 7 days — just re-run from Xcode to
  renew.
- **Paid account:** set `KELID_TEAM_ID` in `Local.xcconfig` to your real Team ID for installs that don't
  expire weekly, TestFlight, and eventual App Store distribution.
- Both the `Kelid` and `KelidKeyboard` targets must use the **same App Group**
  (`group.<prefix>.kelid`) in their entitlements — `project.yml` already wires this up from
  `KELID_APP_GROUP`.

## Enabling the keyboard on your iPhone

1. Build and run the `Kelid` scheme on your device (or the Simulator, with
   *I/O → Keyboard → Connect Hardware Keyboard* turned **off** so the software keyboard shows).
2. On the device: **Settings → General → Keyboard → Keyboards → Add New Keyboard… → Kelid**.
3. Tap **Kelid** in that list and turn on **Allow Full Access** (needed for the clipboard, sounds,
   haptics and the shared App Group — see PLAN.md §2.2).
4. In any text field (Notes, Safari's address bar, Messages…), press and hold the globe key 🌐 and pick
   **Kelid**, or tap it directly if Kelid is the next keyboard in the cycle.

## Debugging the keyboard extension

- **Run with a debugger:** choose the `KelidKeyboard` scheme → Run → pick **Kelid** as the host app →
  tap the *Try it* field in the app → switch to Kelid with the globe key. Breakpoints now work. Or use
  *Debug → Attach to Process → KelidKeyboard* from an already-running session.
- **Logs:** Console.app → select your device → filter by subsystem `<prefix>.kelid` (see `CLAUDE.md`
  for your configured prefix).
- **Simulator quirks:** turn off *I/O → Keyboard → Connect Hardware Keyboard* (⇧⌘K) so the software
  keyboard shows. The Simulator does **not** enforce the ~48–60 MB keyboard-extension memory limit, and
  it syncs the Mac's pasteboard — confusing for clipboard tests. Always verify memory and clipboard
  behavior on a real device before calling a phase done.
- **Keyboard vanished / switched back to Apple's keyboard:** it crashed or was killed (likely hit the
  memory limit). Check the Xcode console, then *Settings → Privacy & Security → Analytics & Improvements
  → Analytics Data* for `KelidKeyboard…` or `JetsamEvent…` entries.
- **Keyboard not listed in Settings:** the extension's bundle ID must start with the app's bundle ID;
  try deleting the app and reinstalling, or restarting the Simulator.

## Development commands

| Command | Does |
|---|---|
| `make gen` | `xcodegen generate` |
| `make build` | Builds the app + keyboard extension for the iOS Simulator |
| `make test` | `swift test` for `Packages/KelidKit` (fast, macOS) plus `xcodebuild test` for iOS-only tests |
| `make lint` / `make format` | SwiftFormat + SwiftLint + the no-networking check |
| `make klm` | Builds the `klm` command-line tool (Phase 6+ language data pipeline) |

`make test-ios` needs a Simulator device to run against — set `SIM` if the default name
(`platform=iOS Simulator,name=iPhone 17`) doesn't exist on your machine:

```sh
xcrun simctl list devices available   # find a name
make test SIM="platform=iOS Simulator,name=<name>"
```

## For AI coding sessions

See [CLAUDE.md](CLAUDE.md) for the working rules, and PLAN.md §0.2–§0.5 for the one-phase-per-session
workflow and prompt templates.
