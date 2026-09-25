/// One key slot in a layout row (PLAN.md §6.2.1). A plain JSON string
/// (`"ض"`) is shorthand for `{ "out": "ض" }`; anything more specific uses
/// the full object form.
///
/// `out` is optional because it only means something for `action == .char`
/// (the default) — a `.backspace` or `.space` key's behavior comes entirely
/// from `action`, and a spacer (`spacer != nil`) is an empty gap with no
/// key at all.
public struct KeyDefinition: Sendable, Equatable {
    /// Text inserted for `action == .char`.
    public var out: String?
    /// Display label, if different from `out` (e.g. a combining mark shown
    /// with a dotted circle, §6.2.4).
    public var label: String?
    public var action: KeyAction
    /// Relative width units (default 1.0).
    public var width: Double
    /// When set, this slot is an empty gap of this width — no key.
    public var spacer: Double?
    /// Overrides the layout file's top-level `alternates` table for this
    /// specific key.
    public var alternates: [String]?
    /// Output with Shift (English letters uppercase automatically without
    /// needing this).
    public var shifted: String?
    /// Small corner label (e.g. a digit hint).
    public var hint: String?
    /// Bottom-row-only (§6.2.6 preamble): this key takes all remaining row
    /// width instead of a fixed number of units — the space bar. Not part
    /// of the JSON layout file schema (§6.2.1 has no `flex` field); only
    /// `BottomRowBuilder`-constructed keys set this.
    public var flex: Bool

    public init(
        out: String? = nil,
        label: String? = nil,
        action: KeyAction = .char,
        width: Double = 1.0,
        spacer: Double? = nil,
        alternates: [String]? = nil,
        shifted: String? = nil,
        hint: String? = nil,
        flex: Bool = false
    ) {
        self.out = out
        self.label = label
        self.action = action
        self.width = width
        self.spacer = spacer
        self.alternates = alternates
        self.shifted = shifted
        self.hint = hint
        self.flex = flex
    }

    /// Convenience for a plain character key — what the JSON string
    /// shorthand decodes to.
    public static func char(_ text: String) -> KeyDefinition {
        KeyDefinition(out: text)
    }

    public var isSpacer: Bool {
        spacer != nil
    }
}

/// Mirrors the JSON string shorthand (§6.2.1) on the Swift-code side too —
/// handy for building rows in code (tests, `BottomRowBuilder` internals).
extension KeyDefinition: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(out: value)
    }
}

extension KeyDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case out, label, action, width, spacer, alternates, shifted, hint, flex
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let shorthand = try? single.decode(String.self) {
            self.init(out: shorthand)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An initializer declared in an extension can't assign a struct's
        // stored properties field-by-field — it must delegate to a
        // designated initializer from the main type declaration.
        try self.init(
            out: c.decodeIfPresent(String.self, forKey: .out),
            label: c.decodeIfPresent(String.self, forKey: .label),
            action: c.decodeIfPresent(KeyAction.self, forKey: .action) ?? .char,
            width: c.decodeIfPresent(Double.self, forKey: .width) ?? 1.0,
            spacer: c.decodeIfPresent(Double.self, forKey: .spacer),
            alternates: c.decodeIfPresent([String].self, forKey: .alternates),
            shifted: c.decodeIfPresent(String.self, forKey: .shifted),
            hint: c.decodeIfPresent(String.self, forKey: .hint),
            flex: c.decodeIfPresent(Bool.self, forKey: .flex) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        // Always the full object form on encode — round-tripping doesn't
        // need to reproduce the string shorthand.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(out, forKey: .out)
        try c.encodeIfPresent(label, forKey: .label)
        if action != .char {
            try c.encode(action, forKey: .action)
        }
        if width != 1.0 {
            try c.encode(width, forKey: .width)
        }
        try c.encodeIfPresent(spacer, forKey: .spacer)
        try c.encodeIfPresent(alternates, forKey: .alternates)
        try c.encodeIfPresent(shifted, forKey: .shifted)
        try c.encodeIfPresent(hint, forKey: .hint)
        if flex {
            try c.encode(flex, forKey: .flex)
        }
    }
}
