import XCTest
@testable import StaticSVG

final class SmokeTests: XCTestCase {
    func testADrawingRendersThroughTheScreens() throws {
        let markup = #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10" fill="red"/></svg>"#
        let document = try SVGDocument.parse(Data(markup.utf8))
        let serialized = document.serialized()
        let data = try XCTUnwrap(serialized.data)
        let renderer = try XCTUnwrap(SVGRenderer(data))
        XCTAssertEqual(renderer.size, CGSize(width: 20, height: 10))
        let image = try XCTUnwrap(renderer.render(maxPixelSize: 40))
        XCTAssertEqual(image.width, 40)
    }
}
