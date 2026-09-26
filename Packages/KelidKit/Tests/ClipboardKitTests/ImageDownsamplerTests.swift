@testable import ClipboardKit
import CoreGraphics
import Foundation
import ImageIO
import Testing

@Suite("ImageDownsampler")
struct ImageDownsamplerTests {
    /// A synthetic opaque JPEG, larger than both target sizes, so a real
    /// downsampling pass actually has work to do.
    private func makeOpaqueTestImage(pixelSize: Int = 2000) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        let cgImage = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test("downsample produces an image at most 1024px and a thumbnail at most 160px on the longest side")
    func downsampleRespectsMaxSizes() throws {
        let source = makeOpaqueTestImage()
        let result = try #require(ImageDownsampler.downsample(data: source))

        let imageSource = try #require(CGImageSourceCreateWithData(result.imageData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(max(image.width, image.height) <= Int(ImageDownsampler.maxPixelSize))

        let thumbSource = try #require(CGImageSourceCreateWithData(result.thumbnailData as CFData, nil))
        let thumb = try #require(CGImageSourceCreateImageAtIndex(thumbSource, 0, nil))
        #expect(max(thumb.width, thumb.height) <= Int(ImageDownsampler.thumbnailPixelSize))
    }

    @Test("an opaque source image is encoded as JPEG, not PNG")
    func opaqueImageEncodesAsJPEG() throws {
        let source = makeOpaqueTestImage()
        let result = try #require(ImageDownsampler.downsample(data: source))
        #expect(result.isPNG == false)
        // JPEG magic bytes.
        #expect(result.imageData.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test("data larger than 25 MB is skipped")
    func oversizedDataIsSkipped() {
        let oversized = Data(count: 25 * 1024 * 1024 + 1)
        #expect(ImageDownsampler.downsample(data: oversized) == nil)
    }

    @Test("unreadable data returns nil rather than crashing")
    func unreadableDataReturnsNil() {
        #expect(ImageDownsampler.downsample(data: Data([0x00, 0x01, 0x02])) == nil)
    }
}
