import Foundation
import KelidCore
import Testing
@testable import ThemeKit

@Suite("ThemeStore (task 11.1)")
struct ThemeStoreTests {
    private func tempStore() -> ThemeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ThemeStore(paths: ContainerPaths(baseURL: dir))
    }

    @Test("save then load round-trips a custom theme exactly")
    func saveThenLoadRoundTrips() throws {
        let store = tempStore()
        var theme = Theme.fallbackDark
        theme.id = "my.custom.theme"
        theme.name = ThemeName(en: "My Theme", fa: "تم من")
        try store.saveCustomTheme(theme)
        #expect(store.loadCustomTheme(id: "my.custom.theme") == theme)
    }

    @Test("listCustomThemeIDs reflects saved and deleted themes")
    func listReflectsSaveAndDelete() throws {
        let store = tempStore()
        var a = Theme.fallbackLight
        a.id = "theme.a"
        var b = Theme.fallbackDark
        b.id = "theme.b"
        try store.saveCustomTheme(a)
        try store.saveCustomTheme(b)
        #expect(store.listCustomThemeIDs() == ["theme.a", "theme.b"])
        try store.deleteCustomTheme(id: "theme.a")
        #expect(store.listCustomThemeIDs() == ["theme.b"])
    }

    @Test("loadCustomTheme returns nil for a theme that was never saved")
    func loadMissingReturnsNil() {
        #expect(tempStore().loadCustomTheme(id: "nope") == nil)
    }

    @Test("deleting a theme with an image background also removes its image file")
    func deleteRemovesImageFile() throws {
        let store = tempStore()
        var theme = Theme.fallbackLight
        theme.id = "photo.theme"
        theme.background = .image(file: "photo.jpg", blur: 5, dim: 0.2)
        try store.saveCustomTheme(theme)
        try store.saveImage(Data([0x01, 0x02, 0x03]), filename: "photo.jpg")
        #expect(FileManager.default.fileExists(atPath: store.imageURL(filename: "photo.jpg").path))
        try store.deleteCustomTheme(id: "photo.theme")
        #expect(!FileManager.default.fileExists(atPath: store.imageURL(filename: "photo.jpg").path))
    }
}
