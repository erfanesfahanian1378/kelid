import Foundation
import PersianText

/// §6.7.10's emoji suggester (task 8.7) — a lazily-loaded keyword → emoji
/// lookup, compiled by `Tools/data-pipeline/pipeline/emoji.py` from Unicode
/// CLDR annotations into `emoji_suggest_<lang>.json` (a compact
/// `{keyword: [emoji, ...]}` object, bundled as an `EmojiData` package
/// resource alongside `emoji.json`'s full catalog).
///
/// `language` is a plain code ("fa"/"en"), matching both the resource file
/// name and `emoji.json`'s own catalog schema — `EmojiData` doesn't depend
/// on `KelidCore` (§4.2), so it can't use `KelidCore.LanguageID` directly;
/// `KeyboardUI` passes `LanguageID.rawValue` when calling this.
///
/// `@MainActor`, not an `actor`: like `InputEngine.InputProcessor`, this is
/// UIKit-free but single-caller, synchronous, cached-after-first-load state
/// — an actor would only add an async hop for what's otherwise a plain
/// dictionary lookup once loaded.
@MainActor
public final class EmojiSuggester {
    private let bundle: Bundle
    private var tables: [String: [String: [String]]] = [:]

    /// `nil` resolves to `.module` (the real, bundled resources) —
    /// `Bundle.module`'s synthesized accessor is `internal`, so it can't be
    /// referenced directly in a `public` default-argument position; tests
    /// pass an explicit fixture bundle instead.
    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? .module
    }

    /// Up to 3 emoji (most common first) for `word`, matched by
    /// `PersianNormalization.matchKey` against `language`'s suggestion
    /// table. Empty if `word` is empty, the language has no table, or
    /// nothing matches — never throws, since a missing/corrupt resource
    /// should degrade to "no suggestions," not break typing.
    public func suggest(forWord word: String, language: String) -> [String] {
        guard !word.isEmpty else { return [] }
        let key = PersianNormalization.matchKey(word)
        return table(for: language)[key] ?? []
    }

    private func table(for language: String) -> [String: [String]] {
        if let cached = tables[language] {
            return cached
        }
        let loaded = Self.load(language: language, bundle: bundle)
        tables[language] = loaded
        return loaded
    }

    private static func load(language: String, bundle: Bundle) -> [String: [String]] {
        guard let url = bundle.url(forResource: "emoji_suggest_\(language)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }
}
