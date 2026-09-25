import KelidCore

public struct LocalizedName: Codable, Sendable, Equatable {
    public var en: String
    public var fa: String

    public init(en: String, fa: String) {
        self.en = en
        self.fa = fa
    }
}

/// A bundled layout JSON file (PLAN.md §6.2.1) — `fa.standard`, `fa.compact`,
/// `en.qwerty`, `fa.symbols`, `en.symbols`, or `numpad`.
public struct KeyboardLayoutFile: Sendable, Equatable {
    public var id: String
    public var language: LanguageID
    public var direction: Direction
    public var name: LocalizedName
    /// The label the space bar shows (e.g. "فارسی"). `nil` for layouts
    /// with no bottom row of their own, like `numpad` (§6.2.5).
    public var spaceLabel: String?
    /// Keyed by `KeyboardPage.rawValue`, not `KeyboardPage` itself: Swift's
    /// synthesized `Dictionary` `Codable` only encodes as a JSON *object*
    /// when `Key` is literally `String` or `Int` — any other type
    /// (including a `String`-backed `RawRepresentable` enum) encodes as a
    /// flat array of alternating key/value elements instead, which doesn't
    /// match §6.2.1's `"pages": {"letters": {...}}` object format. Use the
    /// `subscript(_:)` below for enum-keyed lookups.
    public var pages: [String: PageDefinition]
    /// Long-press alternates, keyed by the base character. Overridable per
    /// key (`KeyDefinition.alternates`).
    public var alternates: [String: [String]]
    /// Small corner-label hints, keyed by the base character (§6.2.2's
    /// digit hints on the Persian letters page).
    public var digitHints: [String: String]

    public init(
        id: String,
        language: LanguageID,
        direction: Direction,
        name: LocalizedName,
        spaceLabel: String? = nil,
        pages: [String: PageDefinition],
        alternates: [String: [String]] = [:],
        digitHints: [String: String] = [:]
    ) {
        self.id = id
        self.language = language
        self.direction = direction
        self.name = name
        self.spaceLabel = spaceLabel
        self.pages = pages
        self.alternates = alternates
        self.digitHints = digitHints
    }

    public subscript(page: KeyboardPage) -> PageDefinition? {
        pages[page.rawValue]
    }
}

extension KeyboardLayoutFile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, language, direction, name, spaceLabel, pages, alternates, digitHints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Delegates to the designated initializer (see KeyDefinition's
        // init(from:) for why: an extension initializer can't assign a
        // struct's stored properties field-by-field).
        try self.init(
            id: c.decode(String.self, forKey: .id),
            language: c.decode(LanguageID.self, forKey: .language),
            direction: c.decode(Direction.self, forKey: .direction),
            name: c.decode(LocalizedName.self, forKey: .name),
            spaceLabel: c.decodeIfPresent(String.self, forKey: .spaceLabel),
            pages: c.decode([String: PageDefinition].self, forKey: .pages),
            alternates: c.decodeIfPresent([String: [String]].self, forKey: .alternates) ?? [:],
            digitHints: c.decodeIfPresent([String: String].self, forKey: .digitHints) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(language, forKey: .language)
        try c.encode(direction, forKey: .direction)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(spaceLabel, forKey: .spaceLabel)
        try c.encode(pages, forKey: .pages)
        if !alternates.isEmpty {
            try c.encode(alternates, forKey: .alternates)
        }
        if !digitHints.isEmpty {
            try c.encode(digitHints, forKey: .digitHints)
        }
    }
}
