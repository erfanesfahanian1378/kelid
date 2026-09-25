@testable import KelidSettings
import Testing

@Suite("KeyboardSettings clamping")
struct SettingsClampingTests {
    @Test("general: longPressDelayMs and cursorSpeed clamp to their ranges")
    func generalClamps() {
        var settings = KeyboardSettings()
        settings.general.longPressDelayMs = 5000
        settings.general.cursorSpeed = 99
        settings.general.enabledLanguages = []
        let clamped = settings.clamped()
        #expect(clamped.general.longPressDelayMs == 800)
        #expect(clamped.general.cursorSpeed == 2.0)
        #expect(clamped.general.enabledLanguages == [.fa])
    }

    @Test("size: portrait and landscape rowHeight clamp to their own, different ranges")
    func sizeClamps() {
        var settings = KeyboardSettings()
        settings.size.portrait.rowHeight = 1000
        settings.size.landscape.rowHeight = 1000
        settings.size.portrait.keyGapV = 0
        settings.size.landscape.oneHandedWidthRatio = 0.1
        let clamped = settings.clamped()
        #expect(clamped.size.portrait.rowHeight == 80)
        #expect(clamped.size.landscape.rowHeight == 60)
        #expect(clamped.size.portrait.keyGapV == 2)
        #expect(clamped.size.landscape.oneHandedWidthRatio == 0.60)
    }

    @Test("prediction: personalWeight, suggestionCount and autocorrectStrength clamp per language")
    func predictionClamps() {
        var settings = KeyboardSettings()
        settings.prediction.fa.personalWeight = 5
        settings.prediction.en.suggestionCount = 100
        settings.prediction.en.autocorrectStrength = -1
        let clamped = settings.clamped()
        #expect(clamped.prediction.fa.personalWeight == 1)
        #expect(clamped.prediction.en.suggestionCount == 5)
        #expect(clamped.prediction.en.autocorrectStrength == 0)
    }

    @Test("learning: newWordThreshold, halfLifeDays and maxUserWords clamp")
    func learningClamps() {
        var settings = KeyboardSettings()
        settings.learning.newWordThreshold = 0
        settings.learning.halfLifeDays = 1
        settings.learning.maxUserWords = 1
        let clamped = settings.clamped()
        #expect(clamped.learning.newWordThreshold == 1)
        #expect(clamped.learning.halfLifeDays == 7)
        #expect(clamped.learning.maxUserWords == 5000)
    }

    @Test("clipboard: maxItems, chipSeconds clamp and an invalid retentionDays snaps to 30")
    func clipboardClamps() {
        var settings = KeyboardSettings()
        settings.clipboard.maxItems = 1
        settings.clipboard.chipSeconds = 1
        settings.clipboard.retentionDays = 42
        let clamped = settings.clamped()
        #expect(clamped.clipboard.maxItems == 20)
        #expect(clamped.clipboard.chipSeconds == 15)
        #expect(clamped.clipboard.retentionDays == 30)
    }

    @Test("clipboard: a nil retentionDays (forever) is left alone")
    func clipboardNilRetentionIsUntouched() {
        var settings = KeyboardSettings()
        settings.clipboard.retentionDays = nil
        let clamped = settings.clamped()
        #expect(clamped.clipboard.retentionDays == nil)
    }

    @Test("emoji: recentsLimit clamps")
    func emojiClamps() {
        var settings = KeyboardSettings()
        settings.emoji.recentsLimit = 1
        let clamped = settings.clamped()
        #expect(clamped.emoji.recentsLimit == 16)
    }

    @Test("toolbar: more than 7 items is truncated to 7")
    func toolbarClamps() {
        var settings = KeyboardSettings()
        settings.toolbar.items = [
            .clipboard, .emoji, .edit, .resize, .oneHanded, .settings, .incognito, .snippets, .dismiss, .language,
        ]
        let clamped = settings.clamped()
        #expect(clamped.toolbar.items.count == 7)
        #expect(clamped.toolbar.items == [.clipboard, .emoji, .edit, .resize, .oneHanded, .settings, .incognito])
    }
}
