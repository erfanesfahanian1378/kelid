import CoreGraphics
import KelidCore

public enum OneHandedMode: String, Codable, Sendable, CaseIterable {
    case off
    case left
    case right
}

/// Orientation as `SettingsStore.sizeProfile(for:)` resolves it. Lives here
/// (not in `KeyboardUI`) so `KelidSettings` doesn't need UIKit just to know
/// there are two profiles — the real trait-collection-to-orientation
/// mapping is the keyboard controller's job (§6.3.4: landscape ⇔
/// `verticalSizeClass == .compact` on iPhone).
public enum SizeOrientation: Sendable {
    case portrait
    case landscape
}

/// PLAN.md §6.1.3. Portrait and landscape have *different* defaults for the
/// same fields, so — unlike the other settings groups — `SizeProfile` isn't
/// itself `Decodable`: a generic `Self()`-based tolerant default (§6.1.1)
/// would silently use the wrong orientation's default for whichever one
/// isn't first. `SizeSettings` below decodes each nested profile with the
/// right default explicitly instead.
public struct SizeProfile: Sendable, Equatable {
    public var rowHeight: CGFloat
    public var toolbarHeight: CGFloat
    public var bottomLift: CGFloat
    public var sidePadding: CGFloat
    public var keyGapH: CGFloat
    public var keyGapV: CGFloat
    public var oneHanded: OneHandedMode
    public var oneHandedWidthRatio: Double
    public var fontScale: Double

    public init(
        rowHeight: CGFloat,
        toolbarHeight: CGFloat,
        bottomLift: CGFloat,
        sidePadding: CGFloat,
        keyGapH: CGFloat,
        keyGapV: CGFloat,
        oneHanded: OneHandedMode = .off,
        oneHandedWidthRatio: Double = 0.80,
        fontScale: Double = 1.0
    ) {
        self.rowHeight = rowHeight
        self.toolbarHeight = toolbarHeight
        self.bottomLift = bottomLift
        self.sidePadding = sidePadding
        self.keyGapH = keyGapH
        self.keyGapV = keyGapV
        self.oneHanded = oneHanded
        self.oneHandedWidthRatio = oneHandedWidthRatio
        self.fontScale = fontScale
    }

    /// "Standard" device-class default from §6.3.2 (668–900 pt screens).
    /// Phase 4 replaces this with the real device-class-aware value,
    /// computed once at first run and stored (§4.2 task 4.2).
    public static let portraitDefault = SizeProfile(
        rowHeight: 54, toolbarHeight: 44, bottomLift: 0, sidePadding: 3, keyGapH: 6, keyGapV: 12
    )

    public static let landscapeDefault = SizeProfile(
        rowHeight: 40, toolbarHeight: 36, bottomLift: 0, sidePadding: 3, keyGapH: 6, keyGapV: 8
    )

    enum CodingKeys: String, CodingKey {
        case rowHeight, toolbarHeight, bottomLift, sidePadding, keyGapH, keyGapV
        case oneHanded, oneHandedWidthRatio, fontScale
    }

    static func decode(from container: KeyedDecodingContainer<CodingKeys>, default d: SizeProfile) -> SizeProfile {
        SizeProfile(
            rowHeight: container.value(.rowHeight, default: d.rowHeight),
            toolbarHeight: container.value(.toolbarHeight, default: d.toolbarHeight),
            bottomLift: container.value(.bottomLift, default: d.bottomLift),
            sidePadding: container.value(.sidePadding, default: d.sidePadding),
            keyGapH: container.value(.keyGapH, default: d.keyGapH),
            keyGapV: container.value(.keyGapV, default: d.keyGapV),
            oneHanded: container.value(.oneHanded, default: d.oneHanded),
            oneHandedWidthRatio: container.value(.oneHandedWidthRatio, default: d.oneHandedWidthRatio),
            fontScale: container.value(.fontScale, default: d.fontScale)
        )
    }

    func encode(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(rowHeight, forKey: .rowHeight)
        try container.encode(toolbarHeight, forKey: .toolbarHeight)
        try container.encode(bottomLift, forKey: .bottomLift)
        try container.encode(sidePadding, forKey: .sidePadding)
        try container.encode(keyGapH, forKey: .keyGapH)
        try container.encode(keyGapV, forKey: .keyGapV)
        try container.encode(oneHanded, forKey: .oneHanded)
        try container.encode(oneHandedWidthRatio, forKey: .oneHandedWidthRatio)
        try container.encode(fontScale, forKey: .fontScale)
    }

    /// Only `rowHeight`'s valid range differs by orientation (§6.1.3); every
    /// other field shares one range across portrait and landscape. Does
    /// *not* enforce the §6.3.3 total-height clamp against screen height —
    /// that needs runtime geometry this model-level type doesn't have
    /// (`HeightCoordinator`, Phase 4).
    func clamped(orientation: SizeOrientation) -> SizeProfile {
        var copy = self
        let rowHeightRange: ClosedRange<CGFloat> = orientation == .portrait ? 38 ... 80 : 30 ... 60
        copy.rowHeight = copy.rowHeight.clamped(to: rowHeightRange)
        copy.toolbarHeight = copy.toolbarHeight.clamped(to: 32 ... 56)
        copy.bottomLift = copy.bottomLift.clamped(to: 0 ... 80)
        copy.sidePadding = copy.sidePadding.clamped(to: 0 ... 24)
        copy.keyGapH = copy.keyGapH.clamped(to: 0 ... 14)
        copy.keyGapV = copy.keyGapV.clamped(to: 2 ... 20)
        copy.oneHandedWidthRatio = copy.oneHandedWidthRatio.clamped(to: 0.60 ... 0.95)
        copy.fontScale = copy.fontScale.clamped(to: 0.8 ... 1.4)
        return copy
    }
}

/// PLAN.md §6.1.3: `size.portrait`, `size.landscape` (iPad profiles arrive
/// in Phase 17 — tolerant decoding means adding them later needs no
/// migration).
public struct SizeSettings: Codable, Sendable, Equatable {
    public var portrait: SizeProfile
    public var landscape: SizeProfile

    public init(portrait: SizeProfile = .portraitDefault, landscape: SizeProfile = .landscapeDefault) {
        self.portrait = portrait
        self.landscape = landscape
    }

    private enum CodingKeys: String, CodingKey {
        case portrait, landscape
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.nestedContainer(keyedBy: SizeProfile.CodingKeys.self, forKey: .portrait) {
            portrait = SizeProfile.decode(from: nested, default: .portraitDefault)
        } else {
            portrait = .portraitDefault
        }
        if let nested = try? c.nestedContainer(keyedBy: SizeProfile.CodingKeys.self, forKey: .landscape) {
            landscape = SizeProfile.decode(from: nested, default: .landscapeDefault)
        } else {
            landscape = .landscapeDefault
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var portraitContainer = c.nestedContainer(keyedBy: SizeProfile.CodingKeys.self, forKey: .portrait)
        try portrait.encode(into: &portraitContainer)
        var landscapeContainer = c.nestedContainer(keyedBy: SizeProfile.CodingKeys.self, forKey: .landscape)
        try landscape.encode(into: &landscapeContainer)
    }

    public func clamped() -> SizeSettings {
        SizeSettings(portrait: portrait.clamped(orientation: .portrait), landscape: landscape.clamped(orientation: .landscape))
    }
}
