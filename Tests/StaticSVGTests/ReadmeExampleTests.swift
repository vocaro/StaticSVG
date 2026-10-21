import CoreGraphics
import XCTest
import StaticSVG

/// The README's quick start, as a host outside the package writes it, so that it compiles and
/// does what the README says.
final class ReadmeExampleTests: XCTestCase {
    struct MyResources: SVGResourceProvider {
        let files: [String: Data]
        func data(at path: String) -> Data? { files[path] }
    }

    func testTheQuickStartDrawsAndCountsWhatItLeftOut() throws {
        let svgData = Data("""
            <svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'>
            <title>Two boxes</title><script>alert(1)</script>
            <image href='left.png' width='20' height='20'/><image href='missing.png' x='20' width='20' height='20'/>
            </svg>
            """.utf8)
        let png = SVGTest.solid(width: 4, height: 4, red: 1, green: 0, blue: 0)

        let document = try SVGDocument.parse(svgData)
        let serialization = document.serialized(resolve: { reference in reference },
                                                resources: MyResources(files: ["left.png": png]), fontAliases: [:])
        XCTAssertEqual(serialization.diagnostics[.image], 1, "the missing image is left out and counted")
        XCTAssertEqual(document.constructs, [.script])
        let data = try XCTUnwrap(serialization.data)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("script"))
        let renderer = try XCTUnwrap(SVGRenderer(data, fonts: []))
        let image = try XCTUnwrap(renderer.render(maxPixelSize: 1024))
        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(SVGTest.rgba(image, x: 256, y: 256), [255, 0, 0, 255])
        XCTAssertEqual(SVGTest.rgba(image, x: 768, y: 256)[3], 0)
        XCTAssertEqual(document.fallbackText, "Two boxes")
    }
}
