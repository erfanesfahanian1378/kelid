import Foundation
import KelidCore

/// Custom theme storage in the App Group (§6.8.1: `Themes/<id>.json`,
/// images in `Themes/Images/<id>.jpg`). Plain synchronous file I/O — each
/// theme file is a couple of KB, so there's no async-queue machinery here
/// the way `KelidStorage`'s SQLite-backed repositories need; callers on the
/// app side already call from a background `Task` where it matters (theme
/// editor saves), and the keyboard's own resolve-on-`viewWillAppear` read
/// is a single small file read.
///
/// Always uses `FileManager.default` (not an injected instance) — `FileManager`
/// isn't `Sendable` in this SDK, and every other file-backed type in this
/// project (`DatabaseManager`, `ClipboardService`) follows the same
/// call-`.default`-at-each-site pattern rather than storing one.
public struct ThemeStore: Sendable {
    private let paths: ContainerPaths
    private let darwinNotifier: DarwinNotifier

    public init(paths: ContainerPaths, darwinNotifier: DarwinNotifier = .shared) {
        self.paths = paths
        self.darwinNotifier = darwinNotifier
    }

    private var imagesDirectoryURL: URL {
        paths.themesDirectoryURL.appendingPathComponent("Images", isDirectory: true)
    }

    public func listCustomThemeIDs() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: paths.themesDirectoryURL, includingPropertiesForKeys: nil)
        else {
            return []
        }
        return entries.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public func listCustomThemes() -> [Theme] {
        listCustomThemeIDs().compactMap { loadCustomTheme(id: $0) }
    }

    public func loadCustomTheme(id: String) -> Theme? {
        let url = paths.themesDirectoryURL.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Theme.self, from: data)
    }

    /// Overwrites any existing file with the same `theme.id` — a theme
    /// "save" in the editor (task 11.8) is always a full replace, never a
    /// partial merge.
    public func saveCustomTheme(_ theme: Theme) throws {
        try FileManager.default.createDirectory(at: paths.themesDirectoryURL, withIntermediateDirectories: true)
        let url = paths.themesDirectoryURL.appendingPathComponent("\(theme.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(theme)
        try data.write(to: url, options: .atomic)
        darwinNotifier.post(.themesChanged)
    }

    /// Also removes the theme's background image file, if any — a custom
    /// theme "owns" its image exclusively (never shared across themes), so
    /// there's no reference-counting concern in deleting it alongside.
    public func deleteCustomTheme(id: String) throws {
        if let theme = loadCustomTheme(id: id), case let .image(file, _, _) = theme.background {
            try? FileManager.default.removeItem(at: imagesDirectoryURL.appendingPathComponent(file))
        }
        let url = paths.themesDirectoryURL.appendingPathComponent("\(id).json")
        try FileManager.default.removeItem(at: url)
        darwinNotifier.post(.themesChanged)
    }

    /// `filename` only, matching `ThemeBackground.image(file:...)`'s own
    /// "filename, not absolute path" contract.
    public func imageURL(filename: String) -> URL {
        imagesDirectoryURL.appendingPathComponent(filename)
    }

    /// The caller (theme editor) has already baked blur/dim into `data`
    /// (§6.8.1: "blur and dim are baked into the saved image by the app") —
    /// this just persists the finished bytes.
    public func saveImage(_ data: Data, filename: String) throws {
        try FileManager.default.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        try data.write(to: imageURL(filename: filename), options: .atomic)
    }
}
