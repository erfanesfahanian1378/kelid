import CoreGraphics
import Foundation
import ImageIO

/// §6.5.8: downsample with ImageIO — never materializes a full `UIImage`
/// (the full-size decoded image is never kept), so this stays UIKit-free
/// and runs safely off the main thread from raw pasteboard bytes.
public enum ImageDownsampler {
    public struct Result: Sendable, Equatable {
        public let imageData: Data
        public let thumbnailData: Data
        public let isPNG: Bool
    }

    private static let maxSourceBytes = 25 * 1024 * 1024
    public static let maxPixelSize: CGFloat = 1024
    public static let thumbnailPixelSize: CGFloat = 160
    /// `CGImageAlphaInfo` has three "no meaningful alpha" variants, not
    /// just `.none` — `.noneSkipLast`/`.noneSkipFirst` are opaque images
    /// that still carry an (ignored) alpha byte per pixel. Treating only
    /// `.none` as opaque misclassified real opaque images as having alpha
    /// and encoded them as PNG instead of JPEG — caught by a test using a
    /// synthetic opaque image built with `.noneSkipLast`.
    private static let opaqueAlphaInfos: Set<CGImageAlphaInfo> = [.none, .noneSkipLast, .noneSkipFirst]

    /// `nil` if the source is unreadable or larger than 25 MB (§6.5.8's own
    /// skip rule).
    public static func downsample(data: Data) -> Result? {
        guard data.count <= maxSourceBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let full = thumbnail(from: source, maxPixelSize: maxPixelSize) else { return nil }
        guard let thumb = thumbnail(from: source, maxPixelSize: thumbnailPixelSize) else { return nil }

        let isPNG = !Self.opaqueAlphaInfos.contains(full.alphaInfo)
        guard let imageData = encode(full, asPNG: isPNG), let thumbnailData = encode(thumb, asPNG: isPNG) else { return nil }
        return Result(imageData: imageData, thumbnailData: thumbnailData, isPNG: isPNG)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG at quality 0.8, or PNG if the image has alpha (§6.5.8).
    private static func encode(_ image: CGImage, asPNG: Bool) -> Data? {
        let data = NSMutableData()
        let uti = (asPNG ? "public.png" : "public.jpeg") as CFString
        guard let destination = CGImageDestinationCreateWithData(data, uti, 1, nil) else { return nil }
        let options: [CFString: Any] = asPNG ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
