#if canImport(UIKit)
    import Foundation
    import InputEngine
    import KelidCore
    import KelidSettings
    import KeyboardLayout
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

        private let inputProcessor: InputProcessor
        private let layoutRepository: LayoutRepository
        private let feedbackService = FeedbackService()
        private let documentProvider: () -> TextDocument

        private var settings: KeyboardSettings
        private var currentMetrics: KeyboardMetrics
        private var composedPage = PageDefinition(rows: [])
        private var currentLayoutFile: KeyboardLayoutFile?
        private var backspaceRepeatTimer: Timer?
        private var backspaceSwipeDeletedWords: [String] = []

        /// `UIInputViewController.needsInputModeSwitchKey` — only the host can
        /// compute this; set on every `viewWillAppear`/change (task 3.10).
        public var needsGlobeKey = false {
            didSet { rebuild() }
        }

        /// `UIInputViewController.hasFullAccess` — gates sound/haptics (task
        /// 3.14, §2.1 C2).
        public var hasFullAccess = false
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

        public init(
            settings: KeyboardSettings,
            metrics: KeyboardMetrics,
            layoutRepository: LayoutRepository = .shared,
            documentProvider: @escaping () -> TextDocument
        ) {
            self.settings = settings
            currentMetrics = metrics
            self.layoutRepository = layoutRepository
            self.documentProvider = documentProvider
            inputProcessor = InputProcessor(
                settings: InputSettings(settings.general),
                clock: SystemClock(),
                initialLanguage: settings.general.enabledLanguages.first ?? .fa
            )
            super.init()
            state.language = settings.general.enabledLanguages.first ?? .fa
            rootView.keyGridView.delegate = self
            rebuild()
        }

        // MARK: - Settings / metrics / geometry updates

        public func updateSettings(_ settings: KeyboardSettings) {
            self.settings = settings
            inputProcessor.updateSettings(InputSettings(settings.general))
            rebuild()
        }

        public func updateMetrics(_ metrics: KeyboardMetrics) {
            currentMetrics = metrics
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

        // MARK: - Page/layout composition

        private func rebuild() {
            let requirements = FieldRequirements.resolve(for: state.traits)
            state.language = requirements.forcedLanguage ?? state.language
            state.page = requirements.forcedPage ?? state.page

            let layoutFile = layoutRepository.layout(id: layoutID(for: state.page, language: state.language))
            currentLayoutFile = layoutFile
            composedPage = composePage(state.page, from: layoutFile)

            rootView.toolbarHeight = currentMetrics.toolbarHeight
            rootView.toolbarVisible = toolbarVisible
            rootView.keyGridView.keyPopupsEnabled = settings.general.keyPopups
            restyle()

            let height = HeightCoordinator.totalHeight(
                rowCount: composedPage.rows.count,
                metrics: currentMetrics,
                toolbarVisible: toolbarVisible
            )
            onHeightChanged?(height)
            applyGeometry()
        }

        /// §6.3.1's toolbar is always present in Phase 3 — hiding it (e.g. a
        /// full-screen clipboard/emoji panel) is Phase 5/12's concern.
        private var toolbarVisible: Bool {
            true
        }

        private func applyGeometry() {
            guard let layoutFile = currentLayoutFile, rootView.keyGridView.bounds.width > 0 else { return }
            let direction: Direction = state.language == .fa ? .rtl : .ltr
            let computed = LayoutEngine.compute(
                page: composedPage,
                in: rootView.keyGridView.bounds,
                metrics: currentMetrics,
                direction: direction
            )
            rootView.keyGridView.apply(
                layout: computed,
                layoutFile: layoutFile,
                style: currentStyle(),
                fontSize: currentMetrics.baseFontSize,
                direction: direction,
                isLanguageRTL: state.language == .fa
            )
        }

        private func restyle() {
            let style = currentStyle()
            rootView.apply(style: style)
        }

        private func currentStyle() -> KeyStyle {
            KeyStyle.resolve(traitAppearance: systemAppearance, fieldAppearance: mapAppearance(state.traits.keyboardAppearance))
        }

        private func mapAppearance(_ trait: KeyboardAppearanceTrait) -> UIKeyboardAppearance? {
            switch trait {
            case .dark: .dark
            case .light: .light
            case .default: nil
            }
        }

        /// Task 2.3/2.4/2.5's file naming, task 3.9/3.12's language/page
        /// selection: which bundled `.json` backs a given page+language.
        private func layoutID(for page: KeyboardPage, language: LanguageID) -> String {
            switch page {
            case .numpad:
                "numpad"
            case .letters:
                language == .fa ? (settings.general.persianLayout == .compact ? "fa.compact" : "fa.standard") : "en.qwerty"
            case .symbols1, .symbols2:
                language == .fa ? "fa.symbols" : "en.symbols"
            }
        }

        /// Composes a page's rows from the bundled JSON plus the dynamic bits
        /// §6.2.1 deliberately keeps out of the files: digit substitution
        /// (§6.2.4), the optional number row (§6.1.2), the numpad's conditional
        /// row 4 (task 2.5's own note), and the bottom row (§6.2.6).
        private func composePage(_ page: KeyboardPage, from layoutFile: KeyboardLayoutFile) -> PageDefinition {
            switch page {
            case .numpad:
                let base = DigitSubstitution.apply(to: layoutFile[.numpad] ?? PageDefinition(rows: []), mode: numpadDigitsMode())
                var rows = base.rows
                rows.append(NumpadBuilder.row4(showDecimalPoint: state.traits.keyboardType == .decimalPad, showGlobe: needsGlobeKey))
                return PageDefinition(rows: rows)

            case .letters:
                var base = DigitSubstitution.apply(
                    to: layoutFile[.letters] ?? PageDefinition(rows: []),
                    mode: settings.general.persianDigits
                )
                base = NumberRowBuilder.prepending(
                    base,
                    mode: settings.general.persianDigits,
                    showNumberRow: settings.general.showNumberRow
                )
                var rows = base.rows
                rows.append(bottomRow(for: .letters))
                return PageDefinition(rows: rows)

            case .symbols1, .symbols2:
                let base = DigitSubstitution.apply(to: layoutFile[page] ?? PageDefinition(rows: []), mode: settings.general.persianDigits)
                var rows = base.rows
                rows.append(bottomRow(for: page))
                return PageDefinition(rows: rows)
            }
        }

        /// `NumpadDigitsMode` and `PersianDigitsMode` are separate settings
        /// (§6.1.2 — the numpad's digit script is independent of the letters
        /// page's), but share `DigitSubstitution`'s logic, which only knows
        /// `PersianDigitsMode`.
        private func numpadDigitsMode() -> PersianDigitsMode {
            settings.general.numpadDigits == .persian ? .persian : .latin
        }

        private func bottomRow(for page: KeyboardPage) -> [KeyDefinition] {
            let context = BottomRowContext(
                page: page,
                language: state.language,
                languagesCount: settings.general.enabledLanguages.count,
                needsGlobe: needsGlobeKey,
                keyboardType: bottomRowKeyboardType(state.traits.keyboardType),
                showEmojiKey: settings.general.bottomRowEmojiKey
            )
            var row = BottomRowBuilder.build(context)
            if let index = row.firstIndex(where: { $0.action == .return }) {
                row[index].label = returnKeyLabel(for: state.traits.returnKeyType, language: state.language)
            }
            return row
        }

        private func bottomRowKeyboardType(_ trait: KeyboardTypeTrait) -> BottomRowKeyboardType {
            switch trait {
            case .emailAddress: .emailAddress
            case .url: .url
            case .webSearch: .webSearch
            case .twitter: .twitter
            default: .default
            }
        }

        /// Task 3.11: localized return-key label from `ReturnKeyTypeTrait`.
        private func returnKeyLabel(for type: ReturnKeyTypeTrait, language: LanguageID) -> String {
            let isFa = language == .fa
            return switch type {
            case .go: isFa ? "برو" : "Go"
            case .google, .yahoo, .search: isFa ? "جستجو" : "Search"
            case .join: isFa ? "پیوستن" : "Join"
            case .next: isFa ? "بعدی" : "Next"
            case .route: isFa ? "مسیر" : "Route"
            case .send: isFa ? "ارسال" : "Send"
            case .done: isFa ? "پایان" : "Done"
            case .emergencyCall: isFa ? "تماس اضطراری" : "SOS"
            case .continue: isFa ? "ادامه" : "Continue"
            case .default: "⏎"
            }
        }

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
            if let soundID = soundID(for: kind) {
                feedbackService.playSound(soundID)
            }
        }

        private func hapticStyle() -> UIImpactFeedbackGenerator.FeedbackStyle? {
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

        /// `.soft`/`.typewriter` custom sound sets need real audio assets
        /// (Phase 11 theming); until then any non-`.off` choice plays the
        /// standard system click.
        private func soundID(for kind: FeedbackKind) -> FeedbackService.SoundID? {
            guard settings.appearance.sound != .off else { return nil }
            return switch kind {
            case .keyPress: .standardKeyPress
            case .specialKeyPress: .modifierKeyPress
            case .error: nil
            }
        }

        // MARK: - Effect application

        private func perform(_ action: InputAction) {
            apply(inputProcessor.handle(action, in: documentProvider()))
        }

        private func apply(_ effects: [InputEffect]) {
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
                    break // Phase 7+
                case .feedback:
                    break // driven directly by touch events (see KeyGridViewDelegate conformance), not this effect
                case .learn:
                    break // Phase 9
                case .autocorrected:
                    break // Phase 8
                case let .openPanel(panel):
                    state.mode = mode(for: panel)
                case .nextInputMode:
                    onNextInputMode?()
                case .dismissKeyboard:
                    onDismissKeyboard?()
                case let .toast(.info(message)):
                    state.toast = message
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

        // MARK: - Backspace hold-repeat (task 3.2/3.14, §6.4.6/§6.4.12)

        /// Selector-based, not the closure-based `Timer` API: a `block:` closure
        /// crossing into `@Sendable`/actor-isolation territory is exactly the
        /// kind of friction `KeyboardController: NSObject` doesn't need to
        /// invite — `#selector` dispatch on the run loop that scheduled it (the
        /// main thread, here) is unambiguous under this module's default
        /// `MainActor` isolation.
        ///
        /// Note `handleBackspaceRepeatTick` below: `tickBackspaceHold` doesn't
        /// recompute `context` or auto-capitalization on every fired delete
        /// (only `handle(_:in:)` does) — a real but minor gap: `state.shift` can
        /// lag by one character's worth of staleness while the hold is active,
        /// self-correcting the moment any other action calls `handle(_:in:)`.
        /// Fixing it properly means `tickBackspaceHold` returning
        /// `[InputEffect]` instead of `Bool`, which several
        /// `InputProcessorTests` assert on directly — left as a follow-up (see
        /// PROGRESS.md decision log) rather than reshaping tested API mid-phase.
        private func startBackspaceRepeatTimer() {
            backspaceRepeatTimer?.invalidate()
            backspaceRepeatTimer = Timer.scheduledTimer(
                timeInterval: 1.0 / 60.0, target: self, selector: #selector(handleBackspaceRepeatTick), userInfo: nil, repeats: true
            )
        }

        private func stopBackspaceRepeatTimer() {
            backspaceRepeatTimer?.invalidate()
            backspaceRepeatTimer = nil
            inputProcessor.endBackspaceHold()
        }

        @objc private func handleBackspaceRepeatTick() {
            guard inputProcessor.tickBackspaceHold(in: documentProvider()) else { return }
            guard hasFullAccess, let style = hapticStyle() else { return }
            feedbackService.prepareHaptic(style: style)
            feedbackService.fireHaptic()
        }
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
    }
#endif
