#if canImport(UIKit)
    import UIKit

    /// Wraps `UIPasteboard.general` — the only place in `ClipboardKit`
    /// allowed to touch it directly (rule 5.1.5).
    @MainActor
    public final class LivePasteboardClient: PasteboardClient {
        private let pasteboard = UIPasteboard.general
        private static let imageUTIs = ["public.png", "public.jpeg", "public.heic", "public.tiff"]

        public init() {}

        public var changeCount: Int {
            pasteboard.changeCount
        }

        public var hasStrings: Bool {
            pasteboard.hasStrings
        }

        public var hasURLs: Bool {
            pasteboard.hasURLs
        }

        public var hasImages: Bool {
            pasteboard.hasImages
        }

        public var typeIdentifiers: [String] {
            pasteboard.types
        }

        public var string: String? {
            pasteboard.string
        }

        public var url: URL? {
            pasteboard.url
        }

        public func loadImageData() -> Data? {
            for uti in Self.imageUTIs {
                if let data = pasteboard.data(forPasteboardType: uti) {
                    return data
                }
            }
            return nil
        }

        public func setString(_ string: String) {
            pasteboard.string = string
        }

        public func setImageData(_ data: Data, uti: String = "public.jpeg") {
            pasteboard.setData(data, forPasteboardType: uti)
        }
    }
#endif
