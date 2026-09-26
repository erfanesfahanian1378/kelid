#if canImport(UIKit)
    @testable import KeyboardUI
    import PredictionEngine
    import Testing
    import UIKit

    /// Task 7.8's required test: "RTL slot order." A full rendered-view
    /// snapshot test (image comparison via `swift-snapshot-testing`, already
    /// a dependency) is left for a future pass — no `KeyboardUITests` in
    /// this project render real views yet (a pre-existing gap since Phase 3,
    /// not introduced here; see that phase's own handoff notes). This tests
    /// `ToolbarStripView.slots(for:)`, the pure §6.7.5 slot-assembly logic
    /// `applySuggestions(_:isRTL:)` renders — the part that's actually
    /// language-direction-sensitive — without needing a rendered view.
    @Suite("ToolbarStripView suggestion slots (task 7.8, §6.7.5)")
    @MainActor
    struct ToolbarStripSuggestionSlotsTests {
        @Test("best == verbatim collapses to [verbatim(bold), 2nd, 3rd]")
        func collapsesWhenBestEqualsVerbatim() {
            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "کتاب"),
                items: [
                    SuggestionCandidate(text: "کتاب"),
                    SuggestionCandidate(text: "کتابخانه"),
                    SuggestionCandidate(text: "کتابچه"),
                ],
                autocorrect: nil,
                emoji: []
            )
            let slots = ToolbarStripView.slots(for: result)
            #expect(slots.map(\.text) == ["کتاب", "کتابخانه", "کتابچه"])
            #expect(slots[0].isBold)
            #expect(!slots[1].isBold)
            #expect(!slots[2].isBold)
            #expect(slots.map(\.isVerbatim) == [true, false, false]) // task 9.3
        }

        @Test("verbatim distinct from best keeps all three slots, none bold")
        func keepsAllThreeWhenDistinct() {
            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "میخ"),
                items: [
                    SuggestionCandidate(text: "میخواهم"),
                    SuggestionCandidate(text: "میخواستم"),
                ],
                autocorrect: nil,
                emoji: []
            )
            let slots = ToolbarStripView.slots(for: result)
            #expect(slots.map(\.text) == ["میخ", "میخواهم", "میخواستم"])
            #expect(slots.allSatisfy { !$0.isBold })
            #expect(slots.map(\.isVerbatim) == [true, false, false]) // task 9.3: leading slot is still verbatim
        }

        @Test("the center slot is bold when it matches the autocorrect candidate (task 8.6, §6.7.5)")
        func centerSlotBoldWhenAutocorrectCandidate() {
            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "teh"),
                items: [SuggestionCandidate(text: "the"), SuggestionCandidate(text: "then")],
                autocorrect: SuggestionCandidate(text: "the"),
                emoji: []
            )
            let slots = ToolbarStripView.slots(for: result)
            #expect(slots.map(\.text) == ["teh", "the", "then"])
            #expect(!slots[0].isBold) // verbatim itself is never bold here (best != verbatim)
            #expect(slots[1].isBold) // center = best = the autocorrect candidate
            #expect(!slots[2].isBold)
        }

        @Test("the center slot is not bold when there's no autocorrect candidate")
        func centerSlotNotBoldWithoutAutocorrect() {
            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "teh"),
                items: [SuggestionCandidate(text: "the"), SuggestionCandidate(text: "then")],
                autocorrect: nil,
                emoji: []
            )
            let slots = ToolbarStripView.slots(for: result)
            #expect(slots.allSatisfy { !$0.isBold })
        }

        @Test("no verbatim slot (showVerbatimSlot off) just shows up to 3 items plain")
        func noVerbatimShowsItemsOnly() {
            let result = SuggestionResult(
                verbatim: nil,
                items: [
                    SuggestionCandidate(text: "a"),
                    SuggestionCandidate(text: "b"),
                    SuggestionCandidate(text: "c"),
                    SuggestionCandidate(text: "d"),
                ],
                autocorrect: nil,
                emoji: []
            )
            let slots = ToolbarStripView.slots(for: result)
            #expect(slots.map(\.text) == ["a", "b", "c"]) // capped at 3
            #expect(slots.allSatisfy { !$0.isVerbatim }) // no verbatim slot at all when showVerbatimSlot is off
        }

        @Test(
            "applySuggestions with isRTL: true renders slots right-to-left while tap callbacks still report leading-to-trailing slot indices"
        )
        @MainActor
        func rtlMirrorsVisualOrderButNotSlotIndices() {
            let toolbar = ToolbarStripView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
            var tappedSlotIndices: [Int] = []
            toolbar.onTapSuggestionSlot = { tappedSlotIndices.append($0) }

            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "میخ"),
                items: [SuggestionCandidate(text: "میخواهم"), SuggestionCandidate(text: "میخواستم")],
                autocorrect: nil,
                emoji: []
            )
            toolbar.applySuggestions(result, isRTL: true)

            let buttons = toolbar.suggestionStackArrangedButtons
            #expect(buttons.map { $0.title(for: .normal) } == ["میخواستم", "میخواهم", "میخ"]) // visually reversed

            // The *first visual* (rightmost, for RTL) button is slot 2
            // ("میخواستم"), not slot 0 — tapping it must still report 2.
            buttons.first?.sendActions(for: .touchUpInside)
            #expect(tappedSlotIndices == [2])
        }

        @Test("applySuggestions with isRTL: false keeps visual order matching slot order")
        @MainActor
        func ltrKeepsVisualOrderMatchingSlotOrder() {
            let toolbar = ToolbarStripView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
            var tappedSlotIndices: [Int] = []
            toolbar.onTapSuggestionSlot = { tappedSlotIndices.append($0) }

            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "hel"),
                items: [SuggestionCandidate(text: "hello"), SuggestionCandidate(text: "help")],
                autocorrect: nil,
                emoji: []
            )
            toolbar.applySuggestions(result, isRTL: false)

            let buttons = toolbar.suggestionStackArrangedButtons
            #expect(buttons.map { $0.title(for: .normal) } == ["hel", "hello", "help"])
            buttons.first?.sendActions(for: .touchUpInside)
            #expect(tappedSlotIndices == [0])
        }

        @Test(
            "a non-empty emoji list shows the trailing compact slot with the first (best) emoji, and tapping it fires onTapEmoji (task 8.7)"
        )
        @MainActor
        func emojiSlotShowsBestEmojiAndFiresCallback() {
            let toolbar = ToolbarStripView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
            var tappedEmoji: String?
            toolbar.onTapEmoji = { tappedEmoji = $0 }

            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "hap"),
                items: [SuggestionCandidate(text: "happy")],
                autocorrect: nil,
                emoji: ["😀", "😃"]
            )
            toolbar.applySuggestions(result, isRTL: false)
            toolbar.layoutIfNeeded()

            #expect(!toolbar.emojiSlotButton.isHidden)
            #expect(toolbar.emojiSlotButton.title(for: .normal) == "😀") // best (first) of the up-to-3 candidates
            toolbar.emojiSlotButton.sendActions(for: .touchUpInside)
            #expect(tappedEmoji == "😀")
        }

        @Test("an empty emoji list shows no emoji slot")
        @MainActor
        func emptyEmojiListShowsNoSlot() {
            let toolbar = ToolbarStripView(frame: CGRect(x: 0, y: 0, width: 300, height: 40))
            let result = SuggestionResult(
                verbatim: SuggestionCandidate(text: "hap"),
                items: [SuggestionCandidate(text: "happy")],
                autocorrect: nil,
                emoji: []
            )
            toolbar.applySuggestions(result, isRTL: false)
            toolbar.layoutIfNeeded()
            #expect(toolbar.emojiSlotButton.isHidden)
        }
    }
#endif
