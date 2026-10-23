import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import StaticSVG

/// SVG illustrations: `preserveAspectRatio`, drawing, the documented rendering limits, images
/// in `data:` URLs as the serializer prepares them, and robustness against adversarial
/// drawings. The halves of these tests that build a book, and the sizing, wrapper, label and
/// disclosure tests, are EPUBLib's (`RichMediaSVGCoverageTests`).
final class SVGCoverageTests: XCTestCase {
    private static let ns = SVGTest.ns

    private func source(_ svg: String) -> SVGImageSource? {
        SVGTest.source(svg)
    }

    // MARK: Sizing

    func testPreserveAspectRatioMeetSliceAndNone() throws {
        // A 40x40 viewBox in a 160x80 box, split red (top) / blue (bottom).
        func render(_ par: String) throws -> [String] {
            let svg = "<svg \(Self.ns) width='160' height='80' viewBox='0 0 40 40' preserveAspectRatio='\(par)'><rect width='40' height='20' fill='red'/><rect y='20' width='40' height='20' fill='blue'/></svg>"
            let image = try XCTUnwrap(source(svg)?.decode(maxPixelSize: 160))
            return [(10, 10), (80, 10), (150, 10), (10, 70), (80, 70), (150, 70)].map {
                let p = SVGTest.rgba(image, x: $0.0, y: $0.1)
                return p[3] == 0 ? "-" : p[0] > 128 ? "R" : p[2] > 128 ? "B" : "?"
            }
        }
        // meet letterboxes: centred, transparent sides, red over blue.
        XCTAssertEqual(try render("xMidYMid meet"), ["-", "R", "-", "-", "B", "-"])
        XCTAssertEqual(try render("xMinYMid meet"), ["R", "-", "-", "B", "-", "-"], "xMin pins the drawing to the left")
        // slice fills the box, cropping; none stretches to fill.
        XCTAssertEqual(try render("xMidYMid slice"), ["R", "R", "R", "B", "B", "B"])
        XCTAssertEqual(try render("none"), ["R", "R", "R", "B", "B", "B"], "none stretches to fill the whole box")
        XCTAssertEqual(try render("xMidYMin slice"), ["R", "R", "R", "R", "R", "R"], "YMin keeps the top band, which is all red")
    }

    // MARK: Drawing and labels

    func testInlineSVGDrawsPathsTextAndTransforms() throws {
        let svg = "<svg \(Self.ns) width='120' height='60' viewBox='0 0 120 60'><rect width='120' height='60' fill='white'/><circle cx='30' cy='30' r='20' fill='blue'/><g transform='translate(60 0)'><rect width='40' height='40' fill='red'/></g><text x='4' y='55' font-family='Arial' font-size='16'>Lbl</text></svg>"
        let image = try XCTUnwrap(source(svg)?.decode(maxPixelSize: 120))
        XCTAssertEqual(SVGTest.rgba(image, x: 30, y: 30), [0, 0, 255, 255], "the circle paints blue")
        XCTAssertEqual(SVGTest.rgba(image, x: 70, y: 10), [255, 0, 0, 255], "the translated rect paints red")
        var ink = 0
        for y in 44..<58 { for x in 2..<40 where SVGTest.rgba(image, x: x, y: y)[0] < 100 { ink += 1 } }
        XCTAssertGreaterThan(ink, 20, "the text glyphs are actually painted")
    }

    // MARK: Rendering limits (doc: 4 MiB, 10,000 nodes, depth 64)

    /// The renderer's boundaries. That an over-deep SVG in a book shows its alt text is
    /// EPUBLib's half of this test.
    func testRenderingLimitBoundariesShowFallbackText() throws {
        let ns = "xmlns='http://www.w3.org/2000/svg'"
        // Depth: nesting that stays under the limit renders; past it falls back.
        func nested(_ groups: Int) -> String { "<svg \(ns) width='10' height='10'>" + String(repeating: "<g>", count: groups) + "<rect width='5' height='5'/>" + String(repeating: "</g>", count: groups) + "</svg>" }
        XCTAssertNotNil(source(nested(62)), "62 nested groups render")
        XCTAssertNil(source(nested(63)), "a drawing nested past the depth limit is refused")
        // Node count: 9,999 shapes render; 10,000 are refused.
        func rects(_ count: Int) -> String { "<svg \(ns) width='10' height='10'>" + String(repeating: "<rect width='1' height='1'/>", count: count) + "</svg>" }
        XCTAssertNotNil(source(rects(9_999)))
        XCTAssertNil(source(rects(10_000)))
        // Serialized bytes: a drawing just over 4 MiB is refused.
        func big(_ bytes: Int) -> String { "<svg \(ns) width='10' height='10'><path d='M0 0 \(String(repeating: "L9 9 ", count: bytes / 5))' stroke='black'/></svg>" }
        XCTAssertNotNil(source(big(4_000_000)))
        XCTAssertNil(source(big(4_300_000)))
    }

    // MARK: Images in data: URLs — EPUB 3.3 §3.7 (#657)

    /// A 30 × 10 drawing: an `<image>` with `image`'s attributes in its left third, blue in the rest.
    private static func drawing(_ image: String) -> String {
        "<svg \(ns) width='30' height='10'><image \(image) width='10' height='10'/><rect x='10' width='20' height='10' fill='blue'/></svg>"
    }

    /// Images in `data:` URLs are held to the bounds of archive images: the pixels a drawing's
    /// images have together, and the work its preparation may do, which counts a URL's bytes as
    /// it counts a file's and knows a URL given twice as it knows a path.
    ///
    /// The serializer's half. That the fifth of five large images in a book's drawing is left out
    /// is EPUBLib's half of this test.
    func testImagesInDataURLsKeepTheBoundsOfArchiveImages() throws {
        let red = SVGTest.solid(width: 10, height: 10, red: 1, green: 0, blue: 0)
        let blue = SVGTest.solid(width: 10, height: 10, red: 0, green: 0, blue: 1)
        let three = "<svg \(Self.ns) width='30' height='10'><image width='10' height='10' href='data:image/png;base64,\(red.base64EncodedString())'/>"
            + "<image x='10' width='10' height='10' xlink:href='data:image/png;base64,\(red.base64EncodedString())'/>"
            + "<image x='20' width='10' height='10' href='data:image/png;base64,\(blue.base64EncodedString())'/></svg>"
        let root = try SVGTest.root(three)
        let resources = MemoryResources()
        let context = SVGImagePreparation(), report = SVGDiagnosticsBox()
        XCTAssertNotNil(SVGContent.serialize(root, resolve: { XCTFail("resolved \($0)"); return nil }, resources: resources,
                                             report: report, imagePreparation: context))
        XCTAssertEqual(context.visits, 2, "the URL given twice is prepared once")
        XCTAssertEqual(context.cacheHits, 1)
        XCTAssertEqual(report.diagnostics.counts, [:])
        var limits = SVGImagePreparation.Limits()
        limits.sourceBytes = red.count + blue.count - 1
        let limited = SVGImagePreparation(limits: limits), limitedReport = SVGDiagnosticsBox()
        XCTAssertNotNil(SVGContent.serialize(root, resolve: { _ in nil }, resources: resources, report: limitedReport, imagePreparation: limited))
        XCTAssertEqual(limitedReport.diagnostics.counts, [.image: 1], "the blue image's bytes are past what is left")
    }

    /// The renderer is given the drawing as it is prepared: an image in a `data:` URL reaches it
    /// as the PNG its bytes decode to, so one of a type the renderer does not read itself is
    /// drawn, and the prepared drawing passes the second screening (`SVGRenderer`). The first
    /// screens the drawing as the book has it, `data:` images and all. A drawing in a `data:` URL
    /// has no base in the archive, inside a drawing as anywhere: a reference in it names no file,
    /// though there is one at that path.
    ///
    /// The serializer's and renderer's half. How a book's drawing with these images is shown,
    /// and the first screening's refusal of an oversized `data:` image, are EPUBLib's half.
    func testAnImageInADataURLReachesTheRendererAsAPreparedPNGAndNoArchiveFile() throws {
        let red = SVGTest.bitmap(width: 10, height: 10) { context, rect in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(rect)
        }
        let bmp = try XCTUnwrap(SVGTest.encode([red], as: .bmp))
        let raw = Self.drawing("href='data:image/bmp;base64,\(bmp.base64EncodedString())'")
        XCTAssertNil(source(raw), "the renderer's own entry point reads no BMP")
        let resources = MemoryResources(files: ["OPS/pic.png": SVGTest.solid(width: 10, height: 10)])
        let prepared = try XCTUnwrap(SVGContent.serialize(try SVGTest.root(raw), resolve: { _ in nil }, resources: resources))
        XCTAssertTrue(String(decoding: prepared, as: UTF8.self).contains("href=\"data:image/png;base64,"))
        XCTAssertFalse(String(decoding: prepared, as: UTF8.self).contains("image/bmp"))
        XCTAssertTrue(SVGContent.preparedImagesAreBounded(try SVGDocument.parse(prepared).root))
        XCTAssertNotNil(source(String(decoding: prepared, as: UTF8.self)))

        let inner = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><image href='pic.png' width='5' height='10'/>"
            + "<image href='/OPS/pic.png' width='5' height='10'/><rect x='5' width='5' height='10' fill='lime'/></svg>"
        let nested = Self.drawing("href='data:image/svg+xml,\(try XCTUnwrap(inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)))'")
        var resolved: [String] = []
        let report = SVGDiagnosticsBox()
        XCTAssertNotNil(SVGContent.serialize(try SVGTest.root(nested),
                                             resolve: { resolved.append($0); return "OPS/" + $0 }, resources: resources, report: report))
        XCTAssertEqual(resolved, [], "nothing in or round the drawing in the data: URL is resolved")
        XCTAssertEqual(report.diagnostics.counts, [.image: 2])
    }

    /// The serializer finds a fragment's `#` by its byte, as the renderer does. One that a
    /// combining mark follows is a single `Character` with the mark, and is still a fragment: the
    /// reference is kept as written, not resolved as a file and dropped
    /// ([EPUBLib#641](https://github.com/vocaro/EPUBLib/issues/641)).
    func testAFragmentThatBeginsWithACombiningMarkIsKept() throws {
        for element in ["use", "image"] {
            let markup = "<svg \(Self.ns) width='10' height='10'><defs><rect id='&#x301;x' width='5' height='5'/></defs>"
                + "<\(element) href='#&#x301;x' width='5' height='5'/></svg>"
            let report = SVGDiagnosticsBox()
            let bytes = try XCTUnwrap(SVGContent.serialize(try SVGTest.root(markup), resolve: { XCTFail("resolved \($0)"); return nil },
                                                           resources: MemoryResources(), report: report), element)
            XCTAssertNotNil(bytes.range(of: Data("href=\"#\u{301}x\"".utf8)), element)
            XCTAssertEqual(report.diagnostics.counts, [:], element)
        }
    }

    // MARK: Robustness

    func testAdversarialSVGStaysBoundedAndNeverTraps() throws {
        let ns = "xmlns='http://www.w3.org/2000/svg'"
        // Self-referential clip/mask and a use of an ancestor must not loop forever.
        XCTAssertNotNil(source("<svg \(ns) width='10' height='10'><clipPath id='c' clip-path='url(#c)'><rect width='5' height='5'/></clipPath><rect width='10' height='10' clip-path='url(#c)'/></svg>"))
        XCTAssertNil(source("<svg \(ns) width='10' height='10'><g id='g'><rect width='5' height='5'/><use href='#g'/></g></svg>"), "a use of an enclosing group is a cycle and is refused")
        // Degenerate geometry is accepted or rejected, never a trap.
        _ = source("<svg \(ns) width='10' height='10'><rect width='5' height='5' transform='scale(1e300)'/></svg>")
        _ = source("<svg \(ns) width='10' height='10' viewBox='0 0 NaN inf'><rect width='5' height='5'/></svg>")
        XCTAssertNil(source("<svg \(ns) width='-10' height='-10'><rect width='5' height='5'/></svg>"), "a negative size is refused")
        XCTAssertNil(source("<svg \(ns) width='1e-9' height='1e-9'><rect width='5' height='5'/></svg>"), "a sub-point size is refused")
        // A huge declared width is clamped to the raster ceiling, not honoured.
        if let huge = source("<svg \(ns) width='100000' height='1'><rect width='5' height='5'/></svg>") {
            XCTAssertLessThanOrEqual(max(huge.pixelSize.width, huge.pixelSize.height), CGFloat(SVGRenderer.maximumDimension))
        }
        // An embedded raster over 4 megapixels is refused before rendering.
        let bomb = SVGTest.solid(width: 2100, height: 2100).base64EncodedString()
        XCTAssertNil(source("<svg \(ns) width='10' height='10'><image href='data:image/png;base64,\(bomb)' width='10' height='10'/></svg>"))
    }
}
