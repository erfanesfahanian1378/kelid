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
    }
#endif
