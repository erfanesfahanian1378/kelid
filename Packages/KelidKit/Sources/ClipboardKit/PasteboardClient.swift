import Foundation

/// `UIPasteboard` only through this (rule 5.1.5) — §6.5.2's monitor and the
/// edit panel's Copy/Cut/Paste both read/write through it, never touching
/// `UIPasteboard` directly, so both are testable with `FakePasteboardClient`.
@MainActor
public protocol PasteboardClient: AnyObject {
    /// Metadata reads (§2.1 C3): never show a banner or a paste prompt.
    var changeCount: Int { get }
    var hasStrings: Bool { get }
    var hasURLs: Bool { get }
    var hasImages: Bool { get }
    var typeIdentifiers: [String] { get }

    /// Content reads (§2.1 C3): may show the "pasted from" banner or an
    /// "Allow Paste" prompt — only call on `changeCount` change or a user tap.
    var string: String? { get }
    var url: URL? { get }
    /// Raw bytes of the first image representation found (PNG/JPEG/HEIC) —
    /// never materializes a `UIImage` here (§6.5.8: downsampling happens
    /// off the main thread from these bytes, the full-size image is never
    /// kept).
    func loadImageData() -> Data?

    /// Writes update `changeCount` — callers must call this then
    /// immediately tell their own monitor about the new `changeCount`
    /// (`ClipboardMonitor.noteOwnWrite()`) so the write isn't re-captured.
    func setString(_ string: String)
    func setImageData(_ data: Data, uti: String)
}

/// Test double — every property is a plain settable var.
@MainActor
public final class FakePasteboardClient: PasteboardClient {
    public var changeCount = 0
    public var hasStrings = false
    public var hasURLs = false
    public var hasImages = false
    public var typeIdentifiers: [String] = []
    public var string: String?
    public var url: URL?
    public var imageData: Data?

    public init() {}

    public func loadImageData() -> Data? {
        imageData
    }

    public func setString(_ string: String) {
        self.string = string
        hasStrings = true
        changeCount += 1
    }

    public func setImageData(_ data: Data, uti _: String) {
        imageData = data
        hasImages = true
        changeCount += 1
    }
}
