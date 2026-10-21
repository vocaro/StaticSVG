import CoreGraphics
import Foundation
import ImageIO

/// An image a drawing inlines, as its bytes and the pixel size its header gives: a bitmap
/// ImageIO reads, decoded only when asked, or an SVG parsed and checked by `SVGRenderer`, then
/// rasterized when asked.
final class SVGImageSource {
    enum Format { case bitmap, svg }

    let data: Data
    let format: Format
    /// Pixels (bitmap) or points (SVG), with EXIF orientation applied.
    let pixelSize: CGSize
    private let renderer: SVGRenderer?

    /// Bitmaps over this many pixels are refused rather than decoded.
    static let maximumPixelCount = 64 * 1024 * 1024

    private init(data: Data, format: Format, pixelSize: CGSize, renderer: SVGRenderer? = nil) {
        self.data = data; self.format = format; self.pixelSize = pixelSize; self.renderer = renderer
    }

    /// Reads a bitmap's header (`CGImageSourceCopyPropertiesAtIndex`); nil when ImageIO cannot
    /// read it or it is implausibly large.
    static func bitmap(_ data: Data) -> SVGImageSource? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) != nil, CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maximumPixelCount / height else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        return SVGImageSource(data: data, format: .bitmap, pixelSize: size)
    }

    /// A bounded static SVG. Its own width and height, which its author controls, are kept to
    /// a size every later computation can represent.
    static func svg(_ data: Data, fonts: [SVGFontData] = []) -> SVGImageSource? {
        guard let renderer = SVGRenderer(data, fonts: fonts) else { return nil }
        let long = max(renderer.size.width, renderer.size.height)
        let scale = min(1, CGFloat(SVGRenderer.maximumDimension) / long)
        let size = CGSize(width: renderer.size.width * scale, height: renderer.size.height * scale)
        guard size.width >= 1 / 64, size.height >= 1 / 64 else { return nil }
        return SVGImageSource(data: data, format: .svg, pixelSize: size, renderer: renderer)
    }

    /// Decodes at most `maxPixelSize` pixels on the long side: a downsampled thumbnail with the
    /// orientation applied, or the SVG rasterized at that size.
    func decode(maxPixelSize: Int) -> CGImage? {
        switch format {
        case .bitmap:
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary)
        case .svg:
            return renderer?.render(maxPixelSize: maxPixelSize)
        }
    }
}
