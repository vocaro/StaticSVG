import XCTest
@testable import StaticSVG

/// The tree StaticSVG screens: what `SVGDocument.parse` reads and refuses, and what a host
/// builds with `SVGDocument.Builder`.
final class SVGDocumentTests: XCTestCase {
    private func parse(_ markup: String, limits: SVGLimits = .document) -> Result<SVGDocument, SVGDocumentError> {
        Result { try SVGDocument.parse(Data(markup.utf8), limits: limits) }.mapError { $0 as! SVGDocumentError }
    }

    func testEntityDeclarationsAndInternalSubsetsAreRefusedBeforeParsing() {
        let laughs = "<?xml version='1.0'?><!DOCTYPE svg [<!ENTITY a 'aaaaaaaaaa'><!ENTITY b '&a;&a;&a;'>]><svg xmlns='http://www.w3.org/2000/svg'><text>&b;</text></svg>"
        XCTAssertEqual(parse(laughs).failure, .unsafeMarkup)
        XCTAssertEqual(parse("<!DOCTYPE svg []><svg xmlns='http://www.w3.org/2000/svg'/>").failure, .unsafeMarkup)
        // libxml2 reads a `[` straight after the doctype's `>` as its subset too.
        XCTAssertEqual(parse("<!DOCTYPE svg>[<svg xmlns='http://www.w3.org/2000/svg'/>").failure, .unsafeMarkup)
        // An external DTD is never loaded, and an entity it would declare is refused.
        let external = "<!DOCTYPE svg PUBLIC '-//W3C//DTD SVG 1.1//EN' 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd'>"
        XCTAssertNotNil(parse(external + "<svg xmlns='http://www.w3.org/2000/svg'/>").success)
        XCTAssertEqual(parse(external + "<svg xmlns='http://www.w3.org/2000/svg'><text>&nbsp;</text></svg>").failure, .malformed)
        // What looks like a declaration in a comment, CDATA or an attribute is not one.
        let quoted = "<svg xmlns='http://www.w3.org/2000/svg' data-x='&lt;!ENTITY'><!-- <!ENTITY x 'y'> --><style><![CDATA[ <!ENTITY ]]></style></svg>"
        XCTAssertNotNil(parse(quoted).success)
    }

    func testAttributesInOneTagAreCapped() {
        func tag(_ count: Int) -> String {
            "<svg xmlns='http://www.w3.org/2000/svg' " + (1..<count).map { "a\($0)='1'" }.joined(separator: " ") + "/>"
        }
        XCTAssertNotNil(parse(tag(SVGMarkupSafety.attributesPerElement)).success)
        XCTAssertEqual(parse(tag(SVGMarkupSafety.attributesPerElement + 1)).failure, .limitExceeded("attributesPerElement"))
    }

    func testBytesAreReadAsUTF8AndADeclaredEncodingMustReadThemTheSame() {
        let body = "<svg xmlns='http://www.w3.org/2000/svg'><text>caf\u{E9}</text></svg>"
        XCTAssertEqual(parse(body).success?.root.textContent, "caf\u{E9}")
        XCTAssertEqual(parse("<?xml version='1.0' encoding='UTF-8'?>" + body).success?.root.textContent, "caf\u{E9}")
        // Bytes that are not UTF-8 at all.
        XCTAssertEqual(Result { try SVGDocument.parse(Data([0x3C, 0xFF, 0x3E])) }.mapError { $0 as! SVGDocumentError }.failure, .notUTF8)
        // UTF-8 bytes declared as UTF-16, which a reader honoring the declaration reads as other
        // text: refused, as such a drawing was when it was parsed by its declaration (#636).
        XCTAssertEqual(parse("<?xml version='1.0' encoding='UTF-16'?>" + body).failure, .notUTF8)
        // Latin-1 reads ASCII as UTF-8 does, but not `é`'s two UTF-8 bytes.
        let ascii = "<svg xmlns='http://www.w3.org/2000/svg'><text>cafe</text></svg>"
        XCTAssertNotNil(parse("<?xml version='1.0' encoding='ISO-8859-1'?>" + ascii).success)
        XCTAssertEqual(parse("<?xml version='1.0' encoding='ISO-8859-1'?>" + body).failure, .notUTF8)
        XCTAssertEqual(parse("<?xml version='1.0' encoding='x-no-such-encoding'?>" + ascii).failure, .notUTF8)
        // The renderer screens the exact bytes it is given the same way.
        XCTAssertNil(SVGRenderer(Data(("<?xml version='1.0' encoding='UTF-16'?><svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='4'/></svg>").utf8)))
        XCTAssertNotNil(SVGRenderer(Data(("<?xml version='1.0' encoding='UTF-8'?><svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='4'/></svg>").utf8)))
    }

    func testMalformedXMLAndNamespaceErrorsAreRefused() {
        XCTAssertEqual(parse("<svg xmlns='http://www.w3.org/2000/svg'><g></svg>").failure, .malformed)
        XCTAssertEqual(parse("<svg xmlns='http://www.w3.org/2000/svg'><x:g/></svg>").failure, .malformed)
        XCTAssertEqual(parse("<svg xmlns='http://www.w3.org/2000/svg'><text>&nbsp;</text></svg>").failure, .malformed)
    }

    func testTheTreeKeepsNamesNamespacesAttributesAndMergedText() throws {
        let document = try XCTUnwrap(parse("""
            <svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'><!-- c --><use xlink:href='#a' href='#b'/>a<![CDATA[b]]>&amp;c<?pi x?>d<h:p xmlns:h='http://www.w3.org/1999/xhtml'/><H:P xmlns:H='http://www.w3.org/1999/xhtml'/></svg>
            """).success)
        let root = document.root
        XCTAssertTrue(document.isSVG)
        XCTAssertEqual(root.children.map(\.isText), [false, true, false, false])
        let use = root.children[0]
        XCTAssertEqual(use.attribute("href", namespace: SVGNamespace.xlink), "#a")
        XCTAssertEqual(use.attribute("href"), "#b")
        XCTAssertTrue(use.parent === root)
        XCTAssertEqual(root.children[1].text, "ab&cd")
        // An XHTML name is lowercased, as a reader of XHTML compares it.
        XCTAssertEqual(root.children[2].name, "p")
        XCTAssertEqual(root.children[3].name, "p")
        XCTAssertEqual(document.nodes.count, 5)
        XCTAssertTrue(zip(document.nodes, document.nodes.indices).allSatisfy { $0.order == $1 })
        XCTAssertEqual(root.subtreeEnd, 4)
    }

    func testLimitsAreCheckedWhileParsing() {
        let deep = String(repeating: "<g>", count: 63) + String(repeating: "</g>", count: 63)
        XCTAssertNotNil(parse("<svg xmlns='http://www.w3.org/2000/svg'>" + deep + "</svg>", limits: .renderer).success)
        let deeper = "<g>" + deep + "</g>"
        XCTAssertEqual(parse("<svg xmlns='http://www.w3.org/2000/svg'>" + deeper + "</svg>", limits: .renderer).failure, .limitExceeded("depth"))
        let nodes = { (count: Int) in "<svg xmlns='http://www.w3.org/2000/svg'>" + String(repeating: "<g/>", count: count - 1) + "</svg>" }
        XCTAssertNotNil(parse(nodes(SVGLimits.renderer.nodes), limits: .renderer).success)
        XCTAssertEqual(parse(nodes(SVGLimits.renderer.nodes + 1), limits: .renderer).failure, .limitExceeded("nodes"))
        let bytes = SVGLimits(bytes: 64, depth: 8, nodes: 8)
        XCTAssertEqual(parse("<svg xmlns='http://www.w3.org/2000/svg'>" + String(repeating: " ", count: 64) + "</svg>", limits: bytes).failure, .limitExceeded("bytes"))
    }

    func testABuiltTreeIsTheTreeAParseGives() throws {
        var builder = SVGDocument.Builder()
        try builder.startElement("svg", namespace: SVGNamespace.svg, attributes: [SVGAttribute(name: "width", value: "4")])
        try builder.appendText("a")
        try builder.appendText("b")
        try builder.startElement("rect", namespace: SVGNamespace.svg)
        try builder.endElement()
        try builder.endElement()
        let built = try builder.finish()
        let parsed = try XCTUnwrap(parse("<svg xmlns='http://www.w3.org/2000/svg' width='4'>ab<rect/></svg>").success)
        func outline(_ document: SVGDocument) -> [String] {
            document.nodes.map { "\($0.order) \($0.subtreeEnd) \($0.namespace) \($0.name) \($0.attributes.filter { $0.namespace != "http://www.w3.org/2000/xmlns/" }.map { "\($0.name)=\($0.value)" }) \($0.text)" }
        }
        XCTAssertEqual(outline(built), outline(parsed))

        // A second root, text outside an element, an unbalanced end and an unfinished tree are
        // refused, and so is a tree past the builder's limits.
        var twice = SVGDocument.Builder()
        try twice.startElement("svg"); try twice.endElement()
        XCTAssertThrowsError(try twice.startElement("svg"))
        var loose = SVGDocument.Builder()
        XCTAssertThrowsError(try loose.appendText("x"))
        XCTAssertThrowsError(try loose.endElement())
        var open = SVGDocument.Builder()
        try open.startElement("svg")
        XCTAssertThrowsError(try open.finish())
        var small = SVGDocument.Builder(limits: SVGLimits(bytes: 0, depth: 2, nodes: 2))
        try small.startElement("svg"); try small.startElement("g")
        XCTAssertThrowsError(try small.startElement("g"))
    }
}

private extension Result {
    var success: Success? { if case .success(let value) = self { value } else { nil } }
    var failure: Failure? { if case .failure(let error) = self { error } else { nil } }
}
