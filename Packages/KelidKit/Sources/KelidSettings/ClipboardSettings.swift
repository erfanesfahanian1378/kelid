public enum ClipboardCaptureMode: String, Codable, Sendable, CaseIterable {
    case auto
    case onTap
    case off
}

public enum OTPHandling: String, Codable, Sendable, CaseIterable {
    case skip
    case expire
    case keep
}

public enum ClipboardTapAction: String, Codable, Sendable, CaseIterable {
    case insert
    case insertAndClose
    case copy
}

/// PLAN.md §6.1.7.
public struct ClipboardSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Default is ".auto if no prompt", per the on-device pasteboard-access
    /// test (§2.1 C3, task 5.0). Phase 1 has no clipboard yet, so this is
    /// just the data default; Phase 5 may override it based on that test.
    public var captureMode: ClipboardCaptureMode
    public var pollWhileVisible: Bool
    public var maxItems: Int
    /// `nil` means "forever". Allowed values: 1, 7, 30, 90, or `nil`.
    public var retentionDays: Int?
    public var showChip: Bool
    public var chipSeconds: Int
    public var skipSensitive: Bool
    public var otpHandling: OTPHandling
    public var maskPasswordLike: Bool
    public var captureImages: Bool
    public var tapAction: ClipboardTapAction
    public var smartSpacing: Bool
    public var ignorePatterns: [String]
    public var lockWithFaceID: Bool

    public static let allowedRetentionDays: [Int] = [1, 7, 30, 90]

    public init(
        enabled: Bool = true,
        captureMode: ClipboardCaptureMode = .auto,
        pollWhileVisible: Bool = true,
        maxItems: Int = 200,
        retentionDays: Int? = 30,
        showChip: Bool = true,
        chipSeconds: Int = 90,
        skipSensitive: Bool = true,
        otpHandling: OTPHandling = .expire,
        maskPasswordLike: Bool = true,
        captureImages: Bool = true,
        tapAction: ClipboardTapAction = .insert,
        smartSpacing: Bool = true,
        ignorePatterns: [String] = [],
        lockWithFaceID: Bool = false
    ) {
        self.enabled = enabled
        self.captureMode = captureMode
        self.pollWhileVisible = pollWhileVisible
        self.maxItems = maxItems
        self.retentionDays = retentionDays
        self.showChip = showChip
        self.chipSeconds = chipSeconds
        self.skipSensitive = skipSensitive
        self.otpHandling = otpHandling
        self.maskPasswordLike = maskPasswordLike
        self.captureImages = captureImages
        self.tapAction = tapAction
        self.smartSpacing = smartSpacing
        self.ignorePatterns = ignorePatterns
        self.lockWithFaceID = lockWithFaceID
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, captureMode, pollWhileVisible, maxItems, retentionDays, showChip, chipSeconds
        case skipSensitive, otpHandling, maskPasswordLike, captureImages, tapAction, smartSpacing
        case ignorePatterns, lockWithFaceID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = c.value(.enabled, default: d.enabled)
        captureMode = c.value(.captureMode, default: d.captureMode)
        pollWhileVisible = c.value(.pollWhileVisible, default: d.pollWhileVisible)
        maxItems = c.value(.maxItems, default: d.maxItems)
        retentionDays = c.value(.retentionDays, default: d.retentionDays)
        showChip = c.value(.showChip, default: d.showChip)
        chipSeconds = c.value(.chipSeconds, default: d.chipSeconds)
        skipSensitive = c.value(.skipSensitive, default: d.skipSensitive)
        otpHandling = c.value(.otpHandling, default: d.otpHandling)
        maskPasswordLike = c.value(.maskPasswordLike, default: d.maskPasswordLike)
        captureImages = c.value(.captureImages, default: d.captureImages)
        tapAction = c.value(.tapAction, default: d.tapAction)
        smartSpacing = c.value(.smartSpacing, default: d.smartSpacing)
        ignorePatterns = c.value(.ignorePatterns, default: d.ignorePatterns)
        lockWithFaceID = c.value(.lockWithFaceID, default: d.lockWithFaceID)
    }

    public func clamped() -> ClipboardSettings {
        var copy = self
        copy.maxItems = copy.maxItems.clamped(to: 20 ... 2000)
        copy.chipSeconds = copy.chipSeconds.clamped(to: 15 ... 600)
        if let days = copy.retentionDays, !Self.allowedRetentionDays.contains(days) {
            copy.retentionDays = 30
        }
        return copy
    }
}
