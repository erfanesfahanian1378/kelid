#if canImport(UIKit)
    import ClipboardKit
    import EmojiData
    import Foundation
    import InputEngine
    import KelidCore
    import KelidSettings
    import KelidStorage
    import KeyboardLayout
    import PredictionEngine
    import ThemeKit
    import UIKit

    /// Wires touch → `InputProcessor` → `TextDocument` → effects → UI (task 3.8).
    /// Owns `KeyboardState`, the layout composition pipeline
    /// (`LayoutRepository`/`NumberRowBuilder`/`BottomRowBuilder`/`LayoutEngine`),
    /// and the `KeyGridView`/`KeyboardRootView` it drives.
    ///
    /// `KeyboardViewController` (extension target) owns *this* — it's the only
    /// thing that can touch `UITextDocumentProxy`, call
    /// `advanceToNextInputMode()`, or read `hasFullAccess`/trait collection —
    /// and feeds those in through the small surface below.
    @MainActor
    public final class KeyboardController: NSObject {
        public let state = KeyboardState()
        public let rootView = KeyboardRootView(frame: .zero)

        /// `internal` (not `private`): `KeyboardController+ResizeMode.swift`,
        /// `+QuickSettings.swift` and `+BackspaceRepeat.swift` (separate
        /// files, split out to keep this type's body under SwiftLint's
        /// `type_body_length`) need these — `private` is file-scoped in
        /// Swift, even across extensions of the same type.
        let inputProcessor: InputProcessor
        /// Also `internal`, not `private`: `KeyboardController+Layout.swift`
        /// (a separate file, split out to keep this type's body under
        /// SwiftLint's `type_body_length`) needs it.
        let layoutRepository: LayoutRepository
        let feedbackService = FeedbackService()
        let documentProvider: () -> TextDocument

        var settings: KeyboardSettings
        var currentMetrics: KeyboardMetrics
        var currentOrientation: SizeOrientation
        /// Real device screen height (portrait long-side), for §6.3.3's
        /// total-height clamp (task 4.1) — only the host knows this.
        var screenHeight: CGFloat
        /// `currentMetrics` after `HeightCoordinator.clampedMetrics` —
        /// what's actually used for both the height sent to the host and
        /// the key geometry, so the two never disagree. `internal`, not
        /// `private` — `KeyboardController+Layout.swift` needs it too.
        var clampedMetrics: KeyboardMetrics
        var composedPage = PageDefinition(rows: [])
        // Also `internal`, not `private`, for the same cross-file reason.
        var currentLayoutFile: KeyboardLayoutFile?
        // `internal`, not `private` — `KeyboardController+BackspaceRepeat.swift`
        // (a separate file, split out to keep this type's body under
        // SwiftLint's `type_body_length`) needs it.
        var backspaceRepeatTimer: Timer?
        private var backspaceSwipeDeletedWords: [String] = []

        // MARK: - Resize mode (task 4.3, implementation in +ResizeMode.swift)

        var resizeSession: ResizeSession?
        let resizeCoalescer = ThrottledUpdateCoalescer()
        /// Restored on cancel/reset — `previewSizeProfile` overwrites
        /// `currentMetrics` continuously while dragging, without ever
        /// touching `settings`, so this is the only place the pre-resize
        /// value is remembered.
        var preResizeMetrics: KeyboardMetrics?
        var lastSnapHapticFlag = false
        /// Presents the SwiftUI resize overlay — only the host can host a
        /// `UIHostingController` as a proper child view controller.
        public var onPresentResizeOverlay: ((ResizeSession) -> Void)?
        public var onDismissResizeOverlay: (() -> Void)?

        // MARK: - Quick Settings (task 4.6)

        public var onPresentQuickSettings: (
            (
                _ current: QuickSettingsSnapshot, _ resetDefaults: QuickSettingsSnapshot, _ incognito: Bool,
                _ personalWordCount: Int, _ availableThemes: [Theme]
            ) -> Void
        )?
        public var onDismissQuickSettings: (() -> Void)?

        /// `UIInputViewController.needsInputModeSwitchKey` — only the host can
        /// compute this; set on every `viewWillAppear`/change (task 3.10).
        public var needsGlobeKey = false {
            didSet { rebuild() }
        }

        /// `UIInputViewController.hasFullAccess` — gates sound/haptics (task
        /// 3.14, §2.1 C2) and shows a lock on the clipboard icon (task 5.12).
        public var hasFullAccess = false {
            didSet { rootView.toolbarStrip.setClipboardLocked(!hasFullAccess) }
        }

        /// `UITraitCollection.userInterfaceStyle`, mapped down — the *system*
        /// half of task 3.15's appearance resolution; the field-trait half
        /// comes from `fieldTraitsDidChange()`.
        public var systemAppearance: UIKeyboardAppearance = .light {
            didSet { restyle() }
        }

        /// Calls `UIInputViewController.advanceToNextInputMode()` (task 3.10).
        public var onNextInputMode: (() -> Void)?
        public var onDismissKeyboard: (() -> Void)?
        /// Fires whenever the row count or toolbar visibility changes; the host
        /// applies this via its own height constraint (§6.3.4).
        public var onHeightChanged: ((CGFloat) -> Void)?
        /// `KeyboardController` only ever sees a `KeyboardSettings` *snapshot*
        /// (`updateSettings(_:)`), not a live `SettingsStore` — only the host
        /// owns that. One-handed mode toggling/switching-side (task 4.4) and
        /// the Quick Settings panel (task 4.6) both need to *persist* a
        /// change, so they call this instead, and the host applies it via
        /// its own `SettingsStore.update(_:)`; the mutated settings flow
        /// back the usual way (`.settingsChanged` → `updateSettings(_:)`).
        public var onRequestSettingsChange: (((inout KeyboardSettings) -> Void) -> Void)?

        // MARK: - Clipboard (Phase 5, implementation in +Clipboard.swift)

        let clipboardService: ClipboardService
        /// The 1s "while visible" poll (§6.5.2) — started/stopped by the
        /// host from `viewWillAppear`/`viewDidDisappear`, since only the
        /// host knows when the keyboard is actually on screen.
        var clipboardPollTimer: Timer?
        var lastCapturedClip: Clip?
        var lastEnforceLimitsAt: Date?
        /// Presents the SwiftUI clipboard/edit panels — same
        /// `UIHostingController`-via-host pattern as resize/Quick Settings.
        public var onPresentClipboardPanel: ((ClipboardPanelModel) -> Void)?
        public var onDismissClipboardPanel: (() -> Void)?
        public var onPresentEditPanel: ((EditPanelModel) -> Void)?
        public var onDismissEditPanel: (() -> Void)?

        // MARK: - Suggestion long-press menu (task 9.5)

        public var onPresentSuggestionMenu: (
            (_ word: String, _ onDontSuggest: @escaping () -> Void, _ onForget: @escaping () -> Void, _ onCancel: @escaping () -> Void)
                -> Void
        )?
        public var onDismissSuggestionMenu: (() -> Void)?

        // MARK: - Prediction (Phase 7, implementation in +Suggestions.swift)

        let suggestionService: SuggestionService
        /// §6.7.4's `generation`: incremented once per `.requestSuggestions`
        /// effect, so a `suggest(_:)` result that comes back after a newer
        /// request already superseded it is dropped instead of overwriting
        /// `state.suggestions` with stale content.
        var suggestionGeneration = 0
        /// Task 8.7: `EmojiData`'s lazy keyword → emoji lookup. Kept
        /// separate from `SuggestionService` (§4.2: `PredictionEngine`
        /// doesn't depend on `EmojiData`) — `requestSuggestions()` merges
        /// its result into `SuggestionResult.emoji` itself.
        let emojiSuggester = EmojiSuggester()
        /// Task 9.1/9.2: the same `DatabaseManager` `makeClipboardService()`'s
        /// `ClipRepository` uses — one `UserModelRepository` per language is
        /// built from it in `loadPredictionModels()`.
        let userModelDatabase: DatabaseManager
        /// Task 10.5: the clipboard panel's Snippets tab (browse/insert
        /// only) reads from this — the same `userModelDatabase` every other
        /// personal-data repository here shares.
        let snippetRepository: SnippetRepository
        /// Task 10.5's text-expansion lookup — an in-memory mirror of every
        /// shortcut → snippet text pair, refreshed on load and on
        /// `.snippetsChanged` (implementation in `+Snippets.swift`) so
        /// `expandedAction(for:)` never needs an async round trip on every
        /// single keystroke.
        var shortcutToSnippetText: [String: String] = [:]
        var snippetsObservationToken: DarwinObservationToken?
        /// Task 9.2's write-behind flush (5s) — started in `init`, stopped
        /// never (this controller's whole lifetime is one typing session);
        /// `internal`, not `private`, so `KeyboardController+Suggestions.swift`
        /// can invalidate/reference it if a future phase needs to.
        var userModelFlushTimer: Timer?

        /// Task 11.1/11.2: resolved once per `restyle()` call from
        /// `settings.appearance` + these two — `builtInThemeCatalog` caches
        /// its parsed JSON internally, `themeStore` is a thin, stateless
        /// wrapper over `containerPaths`.
        let containerPaths: ContainerPaths
        let builtInThemeCatalog = BuiltInThemeCatalog()
        var themeStore: ThemeStore
        /// `.themesChanged` — the app's theme editor (task 11.8) can save or
        /// delete a custom theme while this keyboard is already on screen.
        var themesObservationToken: DarwinObservationToken?

        public init(
            settings: KeyboardSettings,
            metrics: KeyboardMetrics,
            orientation: SizeOrientation = .portrait,
            screenHeight: CGFloat = 844,
            layoutRepository: LayoutRepository = .shared,
            clipboardService: ClipboardService,
            suggestionService: SuggestionService,
            userModelDatabase: DatabaseManager,
            containerPaths: ContainerPaths,
            documentProvider: @escaping () -> TextDocument
        ) {
            self.settings = settings
            currentMetrics = metrics
            currentOrientation = orientation
            self.screenHeight = screenHeight
            clampedMetrics = metrics
            self.layoutRepository = layoutRepository
            self.clipboardService = clipboardService
            self.suggestionService = suggestionService
            self.userModelDatabase = userModelDatabase
            snippetRepository = SnippetRepository(database: userModelDatabase)
            self.containerPaths = containerPaths
            themeStore = ThemeStore(paths: containerPaths)
            self.documentProvider = documentProvider
            inputProcessor = InputProcessor(
                settings: InputSettings(settings.general, clipSmartSpacing: settings.clipboard.smartSpacing),
                clock: SystemClock(),
                initialLanguage: settings.general.enabledLanguages.first ?? .fa
            )
            super.init()
            state.language = settings.general.enabledLanguages.first ?? .fa
            state.incognito = settings.learning.incognito
            rootView.keyGridView.delegate = self
            rootView.toolbarStrip.onTapResize = { [weak self] in self?.startResizeMode() }
            rootView.toolbarStrip.onTapSettings = { [weak self] in self?.toggleQuickSettings() }
            rootView.toolbarStrip.onTapClipboard = { [weak self] in self?.toggleClipboardPanel() }
            rootView.toolbarStrip.onTapEdit = { [weak self] in self?.toggleEditPanel() }
            rootView.toolbarStrip.onTapLabel = { [weak self] in self?.tapClipChip() }
            rootView.toolbarStrip.onTapIncognito = { [weak self] in self?.toggleIncognito() }
            observeToolbarText()
            observeSuggestions()
            wireSuggestionBar()
            rebuild()
            loadPredictionModels()
            loadSnippetShortcuts()
            observeSnippetChanges()
            observeThemeChanges()
        }

        /// Called once from `init` — §6.8.3: "Resolved on ... `.themes.changed`."
        private func observeThemeChanges() {
            themesObservationToken = DarwinNotifier.shared.observe(.themesChanged) { [weak self] in
                MainActor.assumeIsolated {
                    self?.restyle()
                }
            }
        }

        // MARK: - Settings / metrics / geometry updates

        public func updateSettings(_ settings: KeyboardSettings) {
            self.settings = settings
            inputProcessor.updateSettings(InputSettings(settings.general, clipSmartSpacing: settings.clipboard.smartSpacing))
            // §6.10's Home-tab "incognito" quick toggle (task 10.1) writes
            // straight to `settings.learning.incognito` — this is what
            // actually reflects that into a keyboard already on screen.
            // Idempotent either way: the keyboard's own toolbar toggle
            // (`toggleIncognito()`) already set both the setting and
            // `state.incognito` together before this round-trips back here.
            if state.incognito != settings.learning.incognito {
                state.incognito = settings.learning.incognito
                rootView.toolbarStrip.setIncognito(state.incognito)
                restyle()
            }
            rebuild()
        }

        /// `screenHeight` is the device's screen height *as currently
        /// oriented* (task 4.1's §6.3.3 clamp: "≤ 60%/70% of screen
        /// height" means the height available in whichever orientation is
        /// active right now, not always the portrait long side).
        public func updateMetrics(_ metrics: KeyboardMetrics, orientation: SizeOrientation, screenHeight: CGFloat) {
            // §6.3.7: "rotation during resize mode cancels it."
            if let resizeSession, resizeSession.orientation != orientation {
                endResizeMode(save: false)
            }
            currentMetrics = metrics
            currentOrientation = orientation
            self.screenHeight = screenHeight
            rebuild()
        }

        /// Call from `viewDidLayoutSubviews` — recomputes key frames for the
        /// grid's current bounds without rebuilding the page composition itself.
        public func viewDidLayoutSubviews() {
            applyGeometry()
        }

        // MARK: - Host lifecycle hooks

        public func textDidChange() {
            apply(inputProcessor.textDidChange(in: documentProvider()))
        }

        /// Field traits page/language forcing (task 3.12, §6.4.11) — call
        /// whenever the focused field might have changed (`viewWillAppear` at
        /// minimum; UIKit gives no more precise "field changed" hook than that
        /// — see `ProxyTextDocument`'s own note on document-identity tracking).
        public func fieldTraitsDidChange() {
            state.traits = documentProvider().traits
            rebuild()
        }

        // Page/layout composition (rebuild, geometry, styling, bottom-row/
        // return-key resolution) is implemented in
        // `KeyboardController+Layout.swift`, split out to keep this type's
        // body under SwiftLint's `type_body_length`.

        // MARK: - Action mapping (KeyDefinition → InputAction)

        private func inputAction(for key: KeyDefinition) -> InputAction {
            switch key.action {
            case .char: .character(resolvedText(for: key))
            case .shift: .shift
            case .backspace: .backspace
            case .space: .space
            case .return: .returnKey
            case .zwnj: .zwnj
            case .pageLetters: .page(.letters)
            case .pageSymbols1: .page(.symbols1)
            case .pageSymbols2: .page(.symbols2)
            case .language: .nextLanguage
            case .globe: .nextInputMode
            case .emoji: .openPanel(.emoji)
            case .dismiss: .dismissKeyboard
            }
        }

        /// §6.4.1: `.character(text)` arrives already case-mapped — shift is a
        /// *state*, not something `InputProcessor` reapplies. `shifted`
        /// overrides for keys where simple `.uppercased()` isn't right (Persian
        /// has no case, but a few punctuation/digit keys use `shifted` for
        /// their alternate form); plain English letters just uppercase.
        private func resolvedText(for key: KeyDefinition) -> String {
            guard let out = key.out else { return "" }
            let isUppercaseActive = switch state.shift {
            case .off: false
            case .oneShot, .capsLock: true
            }
            guard isUppercaseActive else { return out }
            return key.shifted ?? out.uppercased()
        }

        private func feedbackKind(for key: KeyDefinition) -> FeedbackKind {
            switch key.action {
            case .char, .space, .zwnj, .return: .keyPress
            default: .specialKeyPress
            }
        }

        // MARK: - Feedback (task 3.14)

        private func fireFeedback(_ kind: FeedbackKind) {
            guard hasFullAccess else { return }
            if let style = hapticStyle() {
                feedbackService.prepareHaptic(style: style)
                feedbackService.fireHaptic()
            }
            playFeedbackSound(for: kind)
        }

        /// `internal`, not `private` — `+ResizeMode.swift` (a separate file)
        /// calls this too.
        func hapticStyle() -> UIImpactFeedbackGenerator.FeedbackStyle? {
            if settings.appearance.reduceHapticsInLowPower, ProcessInfo.processInfo.isLowPowerModeEnabled {
                return nil
            }
            return switch settings.appearance.haptics {
            case .off: nil
            case .light: .light
            case .medium: .medium
            case .rigid: .rigid
            }
        }

        /// Task 11.5: `.system` plays the standard iOS click IDs;
        /// `.soft`/`.typewriter` play the bundled custom `.caf` packs.
        private func playFeedbackSound(for kind: FeedbackKind) {
            switch settings.appearance.sound {
            case .off:
                break
            case .system:
                let soundID: FeedbackService.SoundID? = switch kind {
                case .keyPress: .standardKeyPress
                case .specialKeyPress: .modifierKeyPress
                case .error: nil
                }
                if let soundID {
                    feedbackService.playSound(soundID)
                }
            case .soft, .typewriter:
                feedbackService.playCustomSound(pack: settings.appearance.sound, kind: kind)
            }
        }

        // MARK: - Effect application

        /// §6.3.7: "typing disabled while resizing."
        /// `internal`, not `private` — `KeyboardController+Clipboard.swift`
        /// (a separate file) calls these for the edit panel's Copy/Cut/Paste
        /// buttons.
        func perform(_ action: InputAction) {
            guard state.mode != .resize else { return }
            let resolvedAction = autocorrectedAction(for: expandedAction(for: action))
            apply(inputProcessor.handle(resolvedAction, in: documentProvider()))
        }

        func apply(_ effects: [InputEffect]) {
            var needsRebuild = false
            for effect in effects {
                switch effect {
                case let .shiftChanged(shift):
                    state.shift = shift
                case let .pageChanged(page):
                    state.page = page
                    needsRebuild = true
                case let .languageChanged(language):
                    state.language = language
                    needsRebuild = true
                case .requestSuggestions:
                    requestSuggestions()
                case .feedback:
                    break // driven directly by touch events (see KeyGridViewDelegate conformance), not this effect
                case let .learn(event):
                    handleLearn(event)
                case .autocorrected:
                    // No UI reaction needed yet: `.requestSuggestions` (also
                    // emitted by `applyAutocorrect`) already refreshes the
                    // suggestion bar, and the revert itself is entirely
                    // `InputProcessor`'s own state (§6.4.6) — a visual
                    // "flash the corrected word" cue is Phase 11 polish
                    // (deferred per this project's own guidance).
                    break
                case let .openPanel(panel):
                    state.mode = mode(for: panel)
                case .nextInputMode:
                    onNextInputMode?()
                case .dismissKeyboard:
                    onDismissKeyboard?()
                case let .toast(.info(message)):
                    state.toast = message
                case let .requestCopyToPasteboard(text):
                    Task { [weak self] in await self?.clipboardService.copyToPasteboard(text) }
                case .requestPasteFromPasteboard:
                    if let text = clipboardService.pasteboardString() {
                        perform(.insertClip(text))
                    }
                }
            }
            if needsRebuild {
                rebuild()
            }
        }

        private func mode(for panel: Panel) -> KeyboardState.Mode {
            switch panel {
            case .clipboard: .clipboard
            case .emoji: .emoji
            case .edit: .edit
            case .quickSettings: .quickSettings
            case .resize: .resize
            }
        }

        // MARK: - Size settings requests (tasks 4.3/4.4/4.6)

        /// Routes a mutation to whichever orientation's `SizeProfile` is
        /// actually showing right now (`currentOrientation`) through
        /// `onRequestSettingsChange` — the host applies it and the result
        /// flows back the normal way (`updateSettings(_:)`).
        private func requestSizeProfileChange(_ transform: @escaping (inout SizeProfile) -> Void) {
            let orientation = currentOrientation
            onRequestSettingsChange? { settings in
                switch orientation {
                case .portrait: transform(&settings.size.portrait)
                case .landscape: transform(&settings.size.landscape)
                }
            }
        }

        // Resize mode (task 4.3) and Quick Settings (task 4.6) are
        // implemented in `KeyboardController+ResizeMode.swift` and
        // `+QuickSettings.swift` — split out purely to keep this type's
        // body under SwiftLint's `type_body_length`.

        // Backspace hold-repeat timing (task 3.2/3.14, §6.4.6/§6.4.12) is
        // implemented in `KeyboardController+BackspaceRepeat.swift`.
    }

    // MARK: - KeyGridViewDelegate (task 3.2/3.8)

    extension KeyboardController: KeyGridViewDelegate {
        func keyGridView(_: KeyGridView, didCommit key: KeyDefinition) {
            fireFeedback(feedbackKind(for: key))
            perform(inputAction(for: key))
        }

        func keyGridView(_: KeyGridView, didCommitAlternate alternate: String, for _: KeyDefinition) {
            fireFeedback(.keyPress)
            perform(.character(alternate))
        }

        func keyGridView(_: KeyGridView, didPerformImmediateAction key: KeyDefinition) {
            switch key.action {
            case .backspace:
                backspaceSwipeDeletedWords.removeAll()
                fireFeedback(.specialKeyPress)
                perform(.backspace)
                inputProcessor.beginBackspaceHold()
                startBackspaceRepeatTimer()
            case .shift:
                fireFeedback(.specialKeyPress)
                perform(.shift)
            default:
                break
            }
        }

        func keyGridView(_: KeyGridView, didEndPress key: KeyDefinition?) {
            if key?.action == .backspace {
                stopBackspaceRepeatTimer()
            }
        }

        func keyGridView(_: KeyGridView, didStepTrackpad characters: Int) {
            perform(.moveCursor(characters))
        }

        /// §6.4.6: positive deletes one more word; negative restores one
        /// previously swipe-deleted word. `InputProcessor.deleteWordBackward`
        /// has no undo of its own, so this captures exactly what left the
        /// document (via `contextBefore`'s before/after diff) and replays it on
        /// the way back — cleared whenever a fresh backspace touch begins.
        func keyGridView(_: KeyGridView, didChangeBackspaceSwipeWordDelta delta: Int) {
            guard state.mode != .resize else { return } // §6.3.7: typing disabled while resizing
            let doc = documentProvider()
            if delta > 0 {
                for _ in 0 ..< delta {
                    let before = doc.contextBefore ?? ""
                    apply(inputProcessor.handle(.deleteWordBackward, in: doc))
                    let after = doc.contextBefore ?? ""
                    backspaceSwipeDeletedWords
                        .append(before.hasPrefix(after) && before.count > after.count ? String(before.dropFirst(after.count)) : "")
                }
            } else if delta < 0 {
                for _ in 0 ..< -delta {
                    guard let word = backspaceSwipeDeletedWords.popLast(), !word.isEmpty else { continue }
                    doc.insertText(word)
                }
            }
            fireFeedback(.specialKeyPress)
        }

        func keyGridView(_: KeyGridView, didShowAlternates _: [String], for _: KeyDefinition) {
            fireFeedback(.specialKeyPress)
        }

        func keyGridView(_: KeyGridView, didChangeAlternateSelection _: Int?) {}

        func keyGridViewDidHideAlternates(_: KeyGridView) {}

        // MARK: - One-handed side panel (task 4.4)

        func keyGridViewDidTapSwitchOneHandedSide(_: KeyGridView) {
            requestSizeProfileChange { profile in
                switch profile.oneHanded {
                case .left: profile.oneHanded = .right
                case .right: profile.oneHanded = .left
                case .off: break // the panel only shows once already one-handed
                }
            }
        }

        func keyGridViewDidTapExitOneHanded(_: KeyGridView) {
            requestSizeProfileChange { profile in
                profile.oneHanded = .off
            }
        }

        func keyGridView(_: KeyGridView, didStepCursorFromSidePanel direction: MoveDirection) {
            perform(.moveCursor(direction == .forward ? 1 : -1))
        }
    }
#endif
