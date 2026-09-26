import KelidCore
@testable import KelidSettings
import Testing

/// Task 7.11: `QuickSettingsSnapshot`'s prediction fields round-trip
/// through the correct per-language side of `KeyboardSettings.prediction`.
@Suite("QuickSettingsSnapshot prediction fields")
struct QuickSettingsSnapshotPredictionTests {
    @Test("snapshot reads the requested language's prediction settings, not always fa")
    func snapshotReadsRequestedLanguage() {
        var settings = KeyboardSettings()
        settings.prediction.en.suggestionCount = 5
        settings.prediction.fa.suggestionCount = 3

        let enSnapshot = QuickSettingsSnapshot(settings: settings, orientation: .portrait, language: .en)
        #expect(enSnapshot.predictionSuggestionCount == 5)
        #expect(enSnapshot.predictionLanguage == .en)

        let faSnapshot = QuickSettingsSnapshot(settings: settings, orientation: .portrait, language: .fa)
        #expect(faSnapshot.predictionSuggestionCount == 3)
        #expect(faSnapshot.predictionLanguage == .fa)
    }

    @Test("applying a snapshot writes back to the correct language's PredictionSettings only")
    func applyWritesOnlyTheRequestedLanguage() {
        var settings = KeyboardSettings()
        var snapshot = QuickSettingsSnapshot(settings: settings, orientation: .portrait, language: .en)
        snapshot.predictionEnabled = false
        snapshot.predictionSuggestionCount = 4
        snapshot.predictionShowVerbatimSlot = false
        snapshot.predictionPreferZWNJForms = false

        snapshot.apply(to: &settings, orientation: .portrait)

        #expect(settings.prediction.en.enabled == false)
        #expect(settings.prediction.en.suggestionCount == 4)
        #expect(settings.prediction.en.showVerbatimSlot == false)
        // fa side must be untouched.
        #expect(settings.prediction.fa.enabled == true)
        #expect(settings.prediction.fa == PredictionSettings.faDefault)
    }

    @Test("applying a snapshot writes the (language-agnostic) toolbar mode")
    func applyWritesToolbarMode() {
        var settings = KeyboardSettings()
        var snapshot = QuickSettingsSnapshot(settings: settings, orientation: .portrait, language: .fa)
        snapshot.toolbarMode = .iconsOnly
        snapshot.apply(to: &settings, orientation: .portrait)
        #expect(settings.toolbar.mode == .iconsOnly)
    }
}
