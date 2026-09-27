import Foundation

/// Loads the ≥12 built-in themes (§6.8.2) bundled as `BuiltInThemes/*.json`
/// package resources. Cached after first load — the whole catalog is a
/// handful of small JSON files, so eager-parse-once is simpler than a
/// per-theme lazy cache and still trivially cheap.
public final class BuiltInThemeCatalog: @unchecked Sendable {
    private let bundle: Bundle
    private var cached: [Theme]?
    private let lock = NSLock()

    /// `nil` resolves to `.module` — same injectable-bundle pattern as
    /// `EmojiData.EmojiSuggester`, for fixture-backed tests.
    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? .module
    }

    public func allThemes() -> [Theme] {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        // `.process("BuiltInThemes")` (Package.swift) flattens the folder's
        // contents into the resource bundle's root rather than preserving it
        // as a subdirectory — unlike `.copy`, which `Fonts` uses instead.
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        let themes = urls.compactMap { url -> Theme? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Theme.self, from: data)
        }.sorted { $0.id < $1.id }
        cached = themes
        return themes
    }

    public func theme(id: String) -> Theme? {
        allThemes().first { $0.id == id }
    }
}
