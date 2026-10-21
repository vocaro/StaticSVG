import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import StaticSVG

/// Drawings, images and resources made in code for the tests.
enum SVGTest {
    static let ns = "xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'"

    /// `markup` parsed with the default document limits, as a host parses a drawing before
    /// serializing it.
    static func document(_ markup: String) throws -> SVGDocument {
        try SVGDocument.parse(Data(markup.utf8))
    }

    static func root(_ markup: String) throws -> SVGNode {
        try document(markup).root
    }

    /// `markup` serialized with no resources, or with `resources`; nil where it is refused.
    static func serialized(_ markup: String, resources: (any SVGResourceProvider)? = nil,
                           resolve: (String) -> String? = { $0 }) throws -> SVGSerialization {
        try document(markup).serialized(resolve: resolve, resources: resources)
    }

    /// An image source the way a nested drawing is decoded: a bitmap, or an SVG screened and
    /// drawn by `SVGRenderer`, its size kept within `SVGRenderer.maximumDimension`.
    static func source(_ markup: String, fonts: [SVGFontData] = []) -> SVGImageSource? {
        SVGImageSource.svg(Data(markup.utf8), fonts: fonts)
    }

    static func bitmap(width: Int, height: Int, draw: (CGContext, CGRect) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context, CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func encode(_ images: [CGImage], as type: UTType, properties: [CFString: Any] = [:]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else { return nil }
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// An opaque PNG of one colour.
    static func solid(width: Int, height: Int, red: CGFloat = 0.2, green: CGFloat = 0.4, blue: CGFloat = 0.8) -> Data {
        encode([bitmap(width: width, height: height) { context, rect in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(rect)
        }], as: .png)!
    }

    /// The straight RGBA of a pixel, top-left origin.
    static func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let alpha = Int(data[3])
        guard alpha > 0 else { return [0, 0, 0, 0] }
        return (0..<3).map { UInt8(min(255, (Int(data[$0]) * 255 + alpha / 2) / alpha)) } + [UInt8(alpha)]
    }
}

/// Resources held in memory: files by path, with optional media types and fallback chains. A
/// reference with a scheme names nothing; any other resolves against the directory of the
/// drawing that holds it, with `.` and `..` segments, a fragment and percent escapes removed.
/// Each read is counted, so a test can show what was read and how often.
final class MemoryResources: SVGResourceProvider {
    var files: [String: Data]
    var mediaTypes: [String: String]
    var fallbacks: [String: [String]]
    private(set) var reads: [String: Int] = [:]

    init(files: [String: Data] = [:], mediaTypes: [String: String] = [:], fallbacks: [String: [String]] = [:]) {
        self.files = files; self.mediaTypes = mediaTypes; self.fallbacks = fallbacks
    }

    func imageCandidates(for path: String) -> [String] { fallbacks[path] ?? [path] }

    func data(at path: String) -> Data? {
        reads[path, default: 0] += 1
        return files[path]
    }

    func mediaType(at path: String) -> String? { mediaTypes[path] }

    func resolve(_ reference: String, relativeTo path: String) -> String? {
        Self.resolve(reference, relativeTo: path)
    }

    static func resolve(_ reference: String, relativeTo path: String) -> String? {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty, !reference.hasPrefix("#"), !reference.hasPrefix("/"),
              reference.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil else { return nil }
        let file = String(reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        var segments = path.split(separator: "/", omittingEmptySubsequences: false).dropLast().map(String.init)
        for segment in file.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch segment {
            case ".", "": continue
            case "..": guard !segments.isEmpty else { return nil }; segments.removeLast()
            default: segments.append(segment)
            }
        }
        return segments.joined(separator: "/").removingPercentEncoding
    }
}
