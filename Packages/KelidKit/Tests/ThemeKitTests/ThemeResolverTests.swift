import Foundation
import KelidCore
import Testing
@testable import ThemeKit

@Suite("ThemeResolver matrix (task 11.1, §6.8.3)")
struct ThemeResolverTests {
    private func tempStore() -> ThemeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ThemeStore(paths: ContainerPaths(baseURL: dir))
    }

    @Test(".fixed always resolves to the same theme regardless of isDark")
    func fixedIgnoresAppearance() {
        let catalog = BuiltInThemeCatalog()
        let store = tempStore()
        let mode = ThemeResolutionMode.fixed(themeID: "kelid.nord")
        #expect(ThemeResolver.resolve(mode: mode, isDark: true, builtIns: catalog, customStore: store).id == "kelid.nord")
        #expect(ThemeResolver.resolve(mode: mode, isDark: false, builtIns: catalog, customStore: store).id == "kelid.nord")
    }

    @Test(".followSystem picks the dark or light theme id by the isDark flag")
    func followSystemPicksByAppearance() {
        let catalog = BuiltInThemeCatalog()
        let store = tempStore()
        let mode = ThemeResolutionMode.followSystem(lightThemeID: "kelid.saffron", darkThemeID: "kelid.dracula")
        #expect(ThemeResolver.resolve(mode: mode, isDark: false, builtIns: catalog, customStore: store).id == "kelid.saffron")
        #expect(ThemeResolver.resolve(mode: mode, isDark: true, builtIns: catalog, customStore: store).id == "kelid.dracula")
    }

    @Test(".followApp behaves the same shape as .followSystem — the caller already decided which trait `isDark` reflects")
    func followAppPicksByAppearance() {
        let catalog = BuiltInThemeCatalog()
        let store = tempStore()
        let mode = ThemeResolutionMode.followApp(lightThemeID: "kelid.pastel", darkThemeID: "kelid.amoled")
        #expect(ThemeResolver.resolve(mode: mode, isDark: false, builtIns: catalog, customStore: store).id == "kelid.pastel")
        #expect(ThemeResolver.resolve(mode: mode, isDark: true, builtIns: catalog, customStore: store).id == "kelid.amoled")
    }

    @Test("a custom theme with the resolved id wins over a built-in of the same id")
    func customThemeWinsOverBuiltIn() throws {
        let catalog = BuiltInThemeCatalog()
        let store = tempStore()
        var custom = Theme.fallbackDark
        custom.id = "kelid.dark"
        custom.panel.accent = "#FF00FF"
        try store.saveCustomTheme(custom)
        let resolved = ThemeResolver.resolve(mode: .fixed(themeID: "kelid.dark"), isDark: true, builtIns: catalog, customStore: store)
        #expect(resolved.panel.accent == "#FF00FF")
    }

    @Test("§6.8.3: a missing custom theme id falls back to kelid.light / kelid.dark")
    func missingThemeFallsBackToBuiltInLightOrDark() {
        let catalog = BuiltInThemeCatalog()
        let store = tempStore()
        let mode = ThemeResolutionMode.fixed(themeID: "does.not.exist")
        #expect(ThemeResolver.resolve(mode: mode, isDark: false, builtIns: catalog, customStore: store).id == "kelid.light")
        #expect(ThemeResolver.resolve(mode: mode, isDark: true, builtIns: catalog, customStore: store).id == "kelid.dark")
    }
}
