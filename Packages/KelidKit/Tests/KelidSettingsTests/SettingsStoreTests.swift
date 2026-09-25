import Foundation
import KelidCore
@testable import KelidSettings
import Testing

/// Every test uses its own uniquely-named `UserDefaults` suites (instead of
/// `.standard` or a shared fixed name) so tests can run concurrently without
/// stepping on each other's persisted state, and cleans them up afterward.
@Suite("SettingsStore")
@MainActor
struct SettingsStoreTests {
    private func makeSuite() -> (defaults: UserDefaults, name: String) {
        let name = "kelid.test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func cleanUp(_ name: String) {
        UserDefaults().removePersistentDomain(forName: name)
    }

    @Test("update() stamps updatedAt from the injected clock, clamps, and is reflected immediately")
    func updateStampsAndClampsImmediately() {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1000))
        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults, clock: clock)

        store.update { $0.general.longPressDelayMs = 9999 }

        #expect(store.settings.updatedAt == Date(timeIntervalSince1970: 1000))
        #expect(store.settings.general.longPressDelayMs == 800) // clamped
    }

    @Test("update() persists to the local mirror, readable by a fresh store")
    func updatePersistsLocally() {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        let clock = TestClock(now: Date(timeIntervalSince1970: 2000))
        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults, clock: clock)
        store.update { $0.general.showNumberRow = true }

        let reloaded = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults, clock: clock)
        #expect(reloaded.settings.general.showNumberRow == true)
    }

    @Test("load(): the newer of shared vs. local wins, whichever it is")
    func loadPicksNewerOfSharedAndLocal() throws {
        let shared = makeSuite()
        let local = makeSuite()
        defer { cleanUp(shared.name); cleanUp(local.name) }

        var olderSettings = KeyboardSettings()
        olderSettings.updatedAt = Date(timeIntervalSince1970: 1000)
        olderSettings.general.showNumberRow = false

        var newerSettings = KeyboardSettings()
        newerSettings.updatedAt = Date(timeIntervalSince1970: 2000)
        newerSettings.general.showNumberRow = true

        // Case 1: shared is newer.
        try shared.defaults.set(JSONEncoder().encode(newerSettings), forKey: "settings.v1")
        try local.defaults.set(JSONEncoder().encode(olderSettings), forKey: "settings.v1")
        let store1 = SettingsStore(appGroupIdentifier: shared.name, localDefaults: local.defaults)
        #expect(store1.settings.general.showNumberRow == true)

        // Case 2: local is newer.
        try shared.defaults.set(JSONEncoder().encode(olderSettings), forKey: "settings.v1")
        try local.defaults.set(JSONEncoder().encode(newerSettings), forKey: "settings.v1")
        let store2 = SettingsStore(appGroupIdentifier: shared.name, localDefaults: local.defaults)
        #expect(store2.settings.general.showNumberRow == true)
    }

    @Test("load(): only one side present is used directly")
    func loadWithOnlyOneSidePresent() throws {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        var settings = KeyboardSettings()
        settings.general.showNumberRow = true
        try local.defaults.set(JSONEncoder().encode(settings), forKey: "settings.v1")

        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults)
        #expect(store.settings.general.showNumberRow == true)
    }

    @Test("load(): neither side present falls back to plain defaults")
    func loadWithNeitherSidePresent() {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults)
        #expect(store.settings == KeyboardSettings(updatedAt: store.settings.updatedAt))
    }

    @Test("sizeProfile(for:) resolves the right orientation")
    func sizeProfileResolvesOrientation() {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults)
        store.update { $0.size.portrait.rowHeight = 61; $0.size.landscape.rowHeight = 41 }
        #expect(store.sizeProfile(for: .portrait).rowHeight == 61)
        #expect(store.sizeProfile(for: .landscape).rowHeight == 41)
    }

    @Test("resolvedPrediction(for:) resolves the right language")
    func resolvedPredictionResolvesLanguage() {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults)
        store.update { $0.prediction.fa.personalWeight = 0.9; $0.prediction.en.personalWeight = 0.1 }
        #expect(store.resolvedPrediction(for: .fa).personalWeight == 0.9)
        #expect(store.resolvedPrediction(for: .en).personalWeight == 0.1)
    }

    // MARK: - Device-class size defaults (task 4.2)

    @Test("applyDeviceSizeDefaultsIfNeeded sets the portrait rowHeight from screen height, once")
    func appliesDeviceSizeDefaultsOnce() {
        let local = makeSuite()
        defer { cleanUp(local.name) }
        let store = SettingsStore(appGroupIdentifier: nil, localDefaults: local.defaults)

        store.applyDeviceSizeDefaultsIfNeeded(portraitScreenHeight: 926) // large device class (Pro Max/Plus)
        #expect(store.settings.size.portrait.rowHeight == 56)
        #expect(store.settings.advanced.deviceSizeDefaultsApplied == true)

        // A later call (e.g. the other process, or the same one again) must
        // not override a resize the user made in between.
        store.update { $0.size.portrait.rowHeight = 70 }
        store.applyDeviceSizeDefaultsIfNeeded(portraitScreenHeight: 568) // would otherwise mean "small" (52)
        #expect(store.settings.size.portrait.rowHeight == 70)
    }

    @Test("DeviceSizeClass.portraitRowHeightDefault classifies by §6.3.2's screen-height bands")
    func deviceSizeClassBands() {
        #expect(DeviceSizeClass.portraitRowHeightDefault(screenHeight: 568) == 52) // SE-class, ≤ 667
        #expect(DeviceSizeClass.portraitRowHeightDefault(screenHeight: 667) == 52)
        #expect(DeviceSizeClass.portraitRowHeightDefault(screenHeight: 844) == 54) // standard, 668–900
        #expect(DeviceSizeClass.portraitRowHeightDefault(screenHeight: 926) == 56) // Pro Max/Plus, > 900
    }
}
