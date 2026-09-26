#if canImport(UIKit)
    import Foundation
    import InputEngine
    import KelidCore
    import KelidSettings
    import KeyboardLayout
    import UIKit

    /// Page/layout composition — `rebuild()`'s pipeline (field-requirement
    /// forcing, `.json` selection, dynamic row composition, height/geometry,
    /// styling) and the bottom-row/return-key resolution it depends on —
    /// split out of `KeyboardController.swift` itself purely to keep that
    /// type's body under SwiftLint's `type_body_length`; behaviorally this is
    /// still part of `KeyboardController`, just declared in a second file.
    extension KeyboardController {
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
        var toolbarVisible: Bool {
            true
        }

        /// `internal`, not `private` — `viewDidLayoutSubviews()` in the main
        /// file calls this too.
        func applyGeometry() {
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
            updateFuzzyProximity(from: computed)
        }

        /// `internal`, not `private` — `systemAppearance`'s `didSet` in the
        /// main file calls this too.
        func restyle() {
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
    }
#endif
