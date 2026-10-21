import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import StaticSVG

final class SVGRenderingTests: XCTestCase {
    func testViewBoxOffsetLetterboxingAndStretch() throws {
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='160' height='80' viewBox='10 20 40 40'><rect x='10' y='20' width='40' height='40' fill='red'/></svg>"
        let image = try XCTUnwrap(try XCTUnwrap(SVGTest.source(svg)).decode(maxPixelSize: 160))
        XCTAssertEqual(pixel(image, 20, 40)[3], 0)
        XCTAssertEqual(pixel(image, 80, 40), [255, 0, 0, 255])
        let stretched = svg.replacingOccurrences(of: "width='160'", with: "preserveAspectRatio='none' width='160'")
        let source = try XCTUnwrap(SVGTest.source(stretched))
        XCTAssertEqual(pixel(try XCTUnwrap(source.decode(maxPixelSize: 160)), 20, 40), [255, 0, 0, 255])
    }

    func testRendererCannotReadExistingAbsoluteImageOrRecursiveSVGData() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try SVGTest.solid(width: 10, height: 10).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='10'><image href='\(path.path)' width='10' height='10'/><rect x='10' width='10' height='10' fill='blue'/></svg>"
        let source = try XCTUnwrap(SVGTest.source(svg))
        let image = try XCTUnwrap(source.decode(maxPixelSize: 20))
        XCTAssertEqual(pixel(image, 5, 5)[3], 0)
        XCTAssertEqual(pixel(image, 15, 5), [0, 0, 255, 255])
        let nested = Data(svg.utf8).base64EncodedString()
        XCTAssertNil(SVGTest.source("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><image href='data:image/svg+xml;base64,\(nested)' width='10' height='10'/></svg>"))
    }

    func testFilterCSSOmissionPreservesPaintFontsAndLocalClipping() throws {
        let svg = """
        <svg xmlns='http://www.w3.org/2000/svg' id='s' width='120' height='80'>
        <defs><filter id='shadow'><feGaussianBlur stdDeviation='1e9'/></filter>
        <clipPath id='clip'><rect width='60' height='80'/></clipPath></defs>
        <style>.box { filter /* comment */ : url('#shadow'); fill: red; }
        .label {font-size: 14px; filter: url(#shadow); fill: blue; font-family: Arial;}</style>
        <rect class='box' width='120' height='80' style='clip-path: url(#clip); FILTER: url("#shadow"); stroke: blue;'/>
        <text class='label' x='2' y='30'>Labels survive</text></svg>
        """
        let data = try XCTUnwrap(SVGContent.serialize(try SVGTest.root(svg), resolve: { _ in nil }, resources: nil))
        let prepared = try SVGDocument.parse(data)
        XCTAssertFalse(SVGContent.unsupportedConstructs(prepared.root).contains("svg:filter"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("font-family: Arial"))
        let image = try XCTUnwrap(try XCTUnwrap(SVGImageSource.svg(data)).decode(maxPixelSize: 120))
        XCTAssertEqual(pixel(image, 30, 50), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, 90, 50)[3], 0)
        XCTAssertNil(SVGTest.source(svg), "Only the sanitizer may omit filters")
        for declaration in ["filter /* comment */ : blur(2px)", #"fi\6cter: blur(2px)"#] {
            let raw = "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20'><rect width='20' height='20' style='\(declaration)'/></svg>"
            XCTAssertNil(SVGTest.source(raw))
        }
    }

    func testOmittedFiltersStillRespectExpansionDepthAndArchiveReferenceLimits() throws {
        let markup = "<svg xmlns='http://www.w3.org/2000/svg' id='s' width='20' height='10'><filter id='f'><feImage href='file:///tmp/private.png'/></filter><image href='https://example.com/private.png' width='10' height='10'/><rect x='10' width='10' height='10' fill='blue' filter='url(#f)'/></svg>"
        let serialization = try SVGTest.serialized(markup, resources: MemoryResources(),
                                                   resolve: { MemoryResources.resolve($0, relativeTo: "drawing.svg") })
        let image = try XCTUnwrap(try XCTUnwrap(SVGImageSource.svg(try XCTUnwrap(serialization.data))).decode(maxPixelSize: 20))
        XCTAssertEqual(pixel(image, 5, 5)[3], 0)
        XCTAssertEqual(pixel(image, 15, 5), [0, 0, 255, 255])
        XCTAssertEqual(serialization.diagnostics[.image], 1)
        let cyclic = try SVGTest.root("<svg xmlns='http://www.w3.org/2000/svg' id='s'><filter id='f'/><g id='a' filter='url(#f)'><use href='#a'/></g></svg>")
        XCTAssertNil(SVGContent.serialize(cyclic, resolve: { _ in nil }, resources: nil))
        let deep = try SVGTest.root("<svg xmlns='http://www.w3.org/2000/svg' id='s'><filter>" + String(repeating: "<g>", count: 65) + String(repeating: "</g>", count: 65) + "</filter><rect width='20' height='10'/></svg>")
        XCTAssertNil(SVGContent.serialize(deep, resolve: { _ in nil }, resources: nil), "Original input bounds apply even to omitted subtrees")
        let path = String(repeating: "L1 1 ", count: 120_000)
        let uses = String(repeating: "<use href='#a'/>", count: 20)
        let expanded = try SVGTest.root("<svg xmlns='http://www.w3.org/2000/svg' id='s'><filter id='f'/><defs><path id='a' d='M0 0 \(path)'/></defs><g filter='url(#f)'>\(uses)</g></svg>")
        XCTAssertNil(SVGContent.serialize(expanded, resolve: { _ in nil }, resources: nil))
    }

    func testLegacyAppleBoldFontKeepsWeightWhenOS2TableIsMissing() throws {
        let font = CTFontCreateWithName("Courier-Bold" as CFString, 12, nil)
        let exported = try XCTUnwrap(SVGFontData.export(font))
        func u16(_ offset: Int) -> Int { Int(exported.data[offset]) << 8 | Int(exported.data[offset + 1]) }
        func u32(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }
        let index = try XCTUnwrap((0..<u16(4)).first { u32(12 + $0 * 16) == 0x4F532F32 })
        let offset = u32(12 + index * 16 + 8)
        XCTAssertEqual(u16(offset + 4), 700)
        XCTAssertFalse((CTFontManagerCreateFontDescriptorsFromData(exported.data as CFData) as? [CTFontDescriptor] ?? []).isEmpty)
    }

    func testColorFontGlyphsCannotBypassSVGPreflight() throws {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 12, nil)
        XCTAssertTrue(SVGFontData.hasColorGlyphs(font))
        if let exported = SVGFontData.export(font) {
            XCTAssertTrue(exported.strippedColorGlyphs)
            XCTAssertFalse(SVGFontData.hasColorGlyphs(exported.data))
            XCTAssertFalse((CTFontManagerCreateFontDescriptorsFromData(exported.data as CFData) as? [CTFontDescriptor] ?? []).isEmpty)
        }
    }

    func testLiveFontDatabasesStayBoundedAfterOptionsCacheEviction() throws {
        let exported = try XCTUnwrap(SVGFontData.export(CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 12, nil)))
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'><text y='15'>ABC</text></svg>".utf8)
        var held: [SVGRenderer] = []
        // SFNT permits trailing bytes. Distinct padded valid fonts force separate immutable
        // databases, while keeping every parsed tree alive beyond the four-entry cache.
        for index in 0..<20 {
            var data = exported.data
            data.append(Data(count: SVGFontData.maximumBytes - data.count))
            data[data.count - 1] = UInt8(index)
            guard let renderer = SVGRenderer(svg, fonts: [SVGFontData(family: exported.family, data: data)]) else { break }
            held.append(renderer)
        }
        XCTAssertGreaterThan(held.count, 1)
        XCTAssertLessThan(held.count, 20, "Live trees must retain the database byte reservation")
        XCTAssertNotNil(held.first?.render(maxPixelSize: 40))
        held.removeAll()
        var replacement = exported.data
        replacement.append(Data(count: SVGFontData.maximumBytes - replacement.count))
        replacement[replacement.count - 1] = 250
        XCTAssertNotNil(SVGRenderer(svg, fonts: [SVGFontData(family: exported.family, data: replacement)]), "Releasing trees returns their reservations")
    }

    func testLiveFontDatabaseIsSharedAfterOptionsCacheEviction() throws {
        let exported = try XCTUnwrap(SVGFontData.export(CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 12, nil)))
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'><text y='15'>ABC</text></svg>".utf8)
        // SFNT permits trailing bytes: each distinct byte is a distinct immutable database.
        func fonts(_ index: Int) -> [SVGFontData] {
            var data = exported.data
            data.append(UInt8(index))
            return [SVGFontData(family: exported.family, data: data)]
        }
        // Hold one parsed tree per font set until the shared budget refuses another database.
        // That refusal also empties the options cache, so none of these is cached any more.
        var held: [SVGRenderer] = []
        for index in 0..<64 {
            guard let renderer = SVGRenderer(svg, fonts: fonts(index)) else { break }
            held.append(renderer)
        }
        XCTAssertGreaterThan(held.count, 1)
        XCTAssertLessThan(held.count, 64, "Distinct live databases stay bounded")
        // A rebuilt section asks for the fonts its previous build still holds. That is the
        // same database, already reserved: it must be shared, not loaded and counted twice.
        for index in held.indices {
            let again = try XCTUnwrap(SVGRenderer(svg, fonts: fonts(index)), "Live font set \(index) was refused")
            XCTAssertNotNil(again.render(maxPixelSize: 40))
        }
        XCTAssertNil(SVGRenderer(svg, fonts: fonts(200)), "Sharing must not admit another database over the budget")
        held.removeAll()
        XCTAssertNotNil(SVGRenderer(svg, fonts: fonts(200)), "Releasing trees returns their reservations")
    }

    func testRepeatedUseStylesAndRasterRequestsRespectLayerBudget() throws {
        let svg = """
        <svg xmlns='http://www.w3.org/2000/svg' width='100' height='100'>
        <style>.layer { opacity: .5; }</style><defs><g id='a' class='layer'><rect width='100' height='100'/></g></defs>
        <use href='#a'/><use href='#a'/><use href='#a'/></svg>
        """
        let document = try SVGTest.document(svg)
        let layers = SVGContent.isolatedLayers(document.root)
        XCTAssertGreaterThan(layers, document.nodes.filter(\.isElement).count, "Expanded uses and CSS isolation are counted")
        let source = try XCTUnwrap(SVGTest.source(svg))
        let image = try XCTUnwrap(source.decode(maxPixelSize: Int.max))
        XCTAssertLessThanOrEqual(image.width * image.height * (4 + 25 * 5 * layers), 96 * 1024 * 1024)
        let deep = String(repeating: "<g>", count: 65) + "<rect width='1' height='1'/>" + String(repeating: "</g>", count: 65)
        XCTAssertNil(SVGTest.source("<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'>\(deep)</svg>"))
    }

    func testExpandedPathCostAndLargeDataRasterAreRefusedBeforeRendering() throws {
        let path = String(repeating: "L1 1 ", count: 120_000)
        let uses = String(repeating: "<use href='#a'/>", count: 20)
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs><path id='a' d='M0 0 \(path)'/></defs>\(uses)</svg>"
        XCTAssertNil(SVGTest.source(svg))
        let data = SVGTest.solid(width: 2100, height: 2100).base64EncodedString()
        let embedded = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><image href='data:image/png;base64,\(data)' width='10' height='10'/></svg>"
        XCTAssertNil(SVGTest.source(embedded))
    }

    /// The renderer reads a `data:` image by the data: URL processor, and so are its images read
    /// before it is given them (`DataURL`): in any case, as base64 broken by white space, or
    /// percent-encoded. Each of those forms is drawn when it is small and refused when it is not.
    func testDataImagesAreBoundedInEveryFormTheRendererDraws() throws {
        func drawing(_ href: String) -> Data {
            Data("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><image href='\(href)' width='10' height='10'/></svg>".utf8)
        }
        func forms(_ png: Data) -> [String] {
            let b64 = png.base64EncodedString()
            return ["data:image/png;base64,\(b64)", "DATA:IMAGE/PNG;BASE64,\(b64)",
                    "data:image/png;base64,\(b64.prefix(8))&#10; \(b64.dropFirst(8))",
                    "data:image/png,\(png.map { String(format: "%%%02X", $0) }.joined())"]
        }
        for href in forms(SVGTest.solid(width: 10, height: 10)) {
            let source = try XCTUnwrap(SVGImageSource.svg(drawing(href)), String(href.prefix(24)))
            XCTAssertEqual(pixel(try XCTUnwrap(source.decode(maxPixelSize: 10)), 5, 5)[3], 255, String(href.prefix(24)))
        }
        for href in forms(SVGTest.solid(width: 2100, height: 2100)) {
            XCTAssertNil(SVGImageSource.svg(drawing(href)), String(href.prefix(24)))
        }
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return Array(data[offset..<(offset + 4)])
    }
}
