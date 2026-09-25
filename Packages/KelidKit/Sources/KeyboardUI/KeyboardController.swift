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

        // `internal` (not `private`): `KeyboardController+ResizeMode.swift`,
        // `+QuickSettings.swift` and `+BackspaceRepeat.swift` (separate
        // files, split out to keep this type's body under SwiftLint's
        // `type_body_length`) need these — `private` is file-scoped in
        // Swift, even across extensions of the same type.
        let inputProcessor: InputProcessor
        private let layoutRepository: LayoutRepository
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
        /// the key geometry, so the two never disagree.
        private var clampedMetrics: KeyboardMetrics
        var composedPage = PageDefinition(rows: [])
        private var currentLayoutFile: KeyboardLayoutFile?
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

        public var onPresentQuickSettings: ((_ current: QuickSettingsSnapshot, _ resetDefaults: QuickSettingsSnapshot) -> Void)?
        public var onDismissQuickSettings: (() -> Void)?

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
        /// `KeyboardController` only ever sees a `KeyboardSettings` *snapshot*
        /// (`updateSettings(_:)`), not a live `SettingsStore` — only the host
        /// owns that. One-handed mode toggling/switching-side (task 4.4) and
        /// the Quick Settings panel (task 4.6) both need to *persist* a
        /// change, so they call this instead, and the host applies it via
        /// its own `SettingsStore.update(_:)`; the mutated settings flow
        /// back the usual way (`.settingsChanged` → `updateSettings(_:)`).
        public var onRequestSettingsChange: (((inout KeyboardSettings) -> Void) -> Void)?

        public init(
            settings: KeyboardSettings,
            metrics: KeyboardMetrics,
            orientation: SizeOrientation = .portrait,
            screenHeight: CGFloat = 844,
            layoutRepository: LayoutRepository = .shared,
            documentProvider: @escaping () -> TextDocument
        ) {
            self.settings = settings
            currentMetrics = metrics
            currentOrientation = orientation
            self.screenHeight = screenHeight
            clampedMetrics = metrics
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
            rootView.toolbarStrip.onTapResize = { [weak self] in self?.startResizeMode() }
            rootView.toolbarStrip.onTapSettings = { [weak self] in self?.toggleQuickSettings() }
            rebuild()
        }

        // MARK: - Settings / metrics / geometry updates

        public func updateSettings(_ settings: KeyboardSettings) {
            self.settings = settings
            inputProcessor.updateSettings(InputSettings(settings.general))
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

        // MARK: - Page/layout composition

        /// `internal`, not `private` — `+ResizeMode.swift`/`+QuickSettings.swift`
        /// (separate files) call this too.
        func rebuild() {
            let requirements = FieldRequirements.resolve(for: state.traits)
            state.language = requirements.forcedLanguage ?? state.language
            state.page = requirements.forcedPage ?? state.page

            let layoutFile = layoutRepository.layout(id: layoutID(for: state.page, language: state.language))
            currentLayoutFile = layoutFile
            composedPage = composePage(state.page, from: layoutFile)

            // §6.3.3: clamp against the *real* screen before this feeds
            // either the height constraint or the key geometry, so the two
            // never disagree about what "clamped" means.
            clampedMetrics = HeightCoordinator.clampedMetrics(
                currentMetrics,
                rowCount: composedPage.rows.count,
                toolbarVisible: toolbarVisible,
                screenHeight: screenHeight,
                orientation: currentOrientation
            )

            rootView.toolbarHeight = clampedMetrics.toolbarHeight
            rootView.toolbarVisible = toolbarVisible
            rootView.keyGridView.keyPopupsEnabled = settings.general.keyPopups
            restyle()

            let height = HeightCoordinator.totalHeight(
                rowCount: composedPage.rows.count,
                metrics: clampedMetrics,
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
                metrics: clampedMetrics,
                direction: direction
            )
            rootView.keyGridView.apply(
                layout: computed,
                layoutFile: layoutFile,
                style: currentStyle(),
                fontSize: clampedMetrics.baseFontSize,
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

        /// §6.3.7: "typing disabled while resizing."
        private func perform(_ action: InputAction) {
            guard state.mode != .resize else { return }
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
