import Darwin
import Foundation
import XCTest
@testable import StaticSVG

/// The CSS the SVG sanitizer hands the bundled renderer. Every `filter` the renderer would apply
/// is removed or refused, wherever its tokenizer finds one
/// ([#253](https://github.com/vocaro/EPUBLib/issues/253)), and CSS is read by Unicode scalar, so
/// that a mark after a delimiter hides nothing and each input behaves as its mark-free twin does
/// ([#248](https://github.com/vocaro/EPUBLib/issues/248)).
///
/// What the renderer reads is asserted by pixel where a drawing reaches it, and otherwise through
/// `SVGReferenceScreen.CSSReader`, which reads CSS as the renderer's parser does.
final class SVGSanitizerCSSTests: XCTestCase {
    private static let ns = SVGTest.ns

    private func parsed(_ svg: String) throws -> SVGNode {
        try SVGDocument.parse(Data(svg.utf8),
                              limits: SVGLimits(bytes: 2 * SVGContent.maximumBytes, depth: SVGContent.maximumDepth, nodes: SVGContent.maximumNodes)).root
    }

    /// `svg` serialized with no resources, as a host serializes a drawing that uses none.
    private func serialize(_ svg: String, fontAliases: [String: String] = [:]) throws -> Data? {
        SVGContent.serialize(try parsed(svg), resolve: { _ in nil }, resources: nil, fontAliases: fontAliases)
    }

    /// The declarations the renderer reads in a `style` attribute, as `name:value`.
    private func reading(style: String) -> [String] {
        SVGReferenceScreen.CSSReader.declarations(of: style, referencesOnly: false).map { $0.name + ":" + $0.value }
    }

    /// The rules the renderer reads in a stylesheet, each as its subjects and declarations.
    private func reading(sheet: String) -> [String] {
        SVGReferenceScreen.CSSReader.rules(of: sheet, referencesOnly: false).map { rule in
            "\(rule.subjects) " + rule.declarations.map { $0.name + ":" + $0.value }.joined(separator: ";")
        }
    }

    /// Seconds of CPU time `work` takes on this thread, excluding time it is not scheduled.
    private func cpuSeconds(_ work: () -> Void) -> Double {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        work()
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
    }

    // MARK: #253: a filter wherever the renderer finds one

    /// Each spelling was drawn by the renderer before this screen read it: the rectangle came out
    /// inverted (#253). The direct entry now refuses it, as it refuses the well-spelled twin, and
    /// through the serializer both draw the red fill and blue stroke with the filter omitted.
    /// EPUBLib's test of the same name checks the reader's attachment and section report.
    func testEveryFilterSpellingIsRefusedDirectlyAndOmittedFromTheDrawing() throws {
        let rect = "<rect x='10' y='10' width='20' height='20'"
        let twins = [
            ("\(rect) style='fill:red !importantfilter:invert(1); stroke:blue; stroke-width:4'/>",
             "\(rect) style='fill:red !important; filter:invert(1); stroke:blue; stroke-width:4'/>"),
            ("\(rect) style='fill:red *filter:invert(1); stroke:blue; stroke-width:4'/>",
             "\(rect) style='fill:red; filter:invert(1); stroke:blue; stroke-width:4'/>"),
            ("\(rect) fill='red' stroke='blue' stroke-width='4' xlink:filter='invert(1)'/>",
             "\(rect) fill='red' stroke='blue' stroke-width='4' filter='invert(1)'/>"),
            ("<style>.r{fill:red !importantfilter:invert(1);stroke:blue;stroke-width:4}</style>\(rect) class='r'/>",
             "<style>.r{fill:red !important;filter:invert(1);stroke:blue;stroke-width:4}</style>\(rect) class='r'/>"),
            ("<style>.r{stroke:blue;stroke-width:4;fill:red *filter:invert(1)}</style>\(rect) class='r'/>",
             "<style>.r{stroke:blue;stroke-width:4;fill:red;filter:invert(1)}</style>\(rect) class='r'/>"),
        ]
        for (spelling, twin) in twins {
            for attributes in [spelling, twin] {
                let svg = "<svg \(Self.ns) id='s' width='40' height='40'>\(attributes)</svg>"
                XCTAssertTrue(SVGContent.unsupportedConstructs(try parsed(svg)).contains("svg:filter"), attributes)
                XCTAssertNil(SVGImageSource.svg(Data(svg.utf8)), "refused directly: \(attributes)")
                let data = try XCTUnwrap(try serialize(svg), attributes)
                let source = try XCTUnwrap(SVGImageSource.svg(data), attributes)
                let image = try XCTUnwrap(source.decode(maxPixelSize: 40))
                XCTAssertEqual(SVGTest.rgba(image, x: 20, y: 20), [255, 0, 0, 255], "fill without the filter: \(attributes)")
                XCTAssertEqual(SVGTest.rgba(image, x: 10, y: 20), [0, 0, 255, 255], "the stroke after it: \(attributes)")
            }
        }
    }

    /// The renderer takes a `filter` attribute in any namespace it reads attributes from, and the
    /// screen looks for it in every one. The serializer writes none of them.
    func testAFilterAttributeInAnyNamespaceIsFound() throws {
        for attribute in ["xlink:filter", "xml:filter", "s:filter", "f:filter"] {
            let svg = "<svg \(Self.ns) xmlns:s='http://www.w3.org/2000/svg' xmlns:f='urn:f' id='s' width='20' height='20'><rect width='20' height='20' fill='red' \(attribute)='invert(1)'/></svg>"
            let root = try parsed(svg)
            XCTAssertTrue(SVGContent.unsupportedConstructs(root).contains("svg:filter"), attribute)
            XCTAssertFalse(SVGContent.isWithinRenderingLimits(root), attribute)
            XCTAssertTrue(SVGContent.isWithinRenderingLimits(root, omittingFilters: true), attribute)
            let data = try XCTUnwrap(SVGContent.serialize(root, resolve: { _ in nil }, resources: nil))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("filter"), attribute)
            XCTAssertNotNil(SVGImageSource.svg(data), attribute)
        }
    }

    /// What is left of a `style` attribute is read by the renderer as what is left of its twin,
    /// and holds nothing the screen would find again.
    func testTheRendererReadsTheRestOfAStyleAsItReadsTheTwin() {
        let cases: [(String, [String])] = [
            ("fill:red !importantfilter:invert(1); stroke:blue", ["fill:red", "stroke:blue"]),
            ("fill:red !importantfilter:invert(1)", ["fill:red"]),
            ("fill:red !important filter:invert(1);stroke:blue", ["fill:red", "stroke:blue"]),
            ("fill:red *filter:invert(1); stroke:blue", ["fill:red", "stroke:blue"]),
            ("fill: url(#a) !importantfilter:invert(1);;stroke:blue", ["fill:url(#a)", "stroke:blue"]),
            ("*filter:invert(1); fill:red", ["fill:red"]),
            ("filter:invert(1); filter:blur(1); fill:red", ["fill:red"]),
            ("fill:red; filter:a(1); *filter:b(2); stroke:blue", ["fill:red", "stroke:blue"]),
            ("FILTER:invert(1); fill:red", ["fill:red"]),
            ("filter /* note */ : invert(1); fill: red", ["fill:red"]),
            ("x:\"/*\";filter:invert(1);y:\"*/\"", ["x:\"/*\"", "y:\"*/\""]),
            ("x: '\u{301}'; filter: url(#shadow); fill: red", ["x:'\u{301}'", "fill:red"]),
            (";;filter:invert(1);", []),
        ]
        for (style, expected) in cases {
            let result = SVGContent.omittingFilterDeclarations(style, sheet: false)
            XCTAssertTrue(result.omitted, style)
            XCTAssertEqual(reading(style: result.css), expected, style)
            XCTAssertFalse(SVGContent.omittingFilterDeclarations(result.css, sheet: false).omitted, "nothing is left to find: \(style)")
        }
        for style in ["fill:red; stroke:url(#filter)", "font-family: 'Filter Sans'", "fill:red"] {
            XCTAssertEqual(SVGContent.omittingFilterDeclarations(style, sheet: false).css, style)
            XCTAssertFalse(SVGContent.omittingFilterDeclarations(style, sheet: false).omitted, style)
        }
    }

    /// The same for a stylesheet: each rule keeps the declarations it had but the filter.
    func testTheRendererReadsTheRestOfASheetAsItReadsTheTwin() {
        let cases: [(String, String)] = [
            ("rect{fill:red !importantfilter:invert(1);stroke:blue}", "rect{fill:red;stroke:blue}"),
            ("rect{*filter:invert(1)} circle{fill:red}", "rect{} circle{fill:red}"),
            ("rect{filter:invert(1)}}circle{fill:red}", "rect{}}circle{fill:red}"),
            ("rect{stroke:blue;fill:red *filter:invert(1);stroke-width:2}", "rect{stroke:blue;fill:red;stroke-width:2}"),
            ("@media print{rect{filter:a}} rect{fill:red !importantfilter:b}", "@media print{rect{}} rect{fill:red}"),
            ("a:lang(x){filter:y} .c{fill:red !importantfilter:z;stroke:blue}", "a:lang(x){} .c{fill:red;stroke:blue}"),
            (".a { filter /* note */ : url('#shadow'); fill: red; }", ".a { fill: red; }"),
        ]
        for (sheet, twin) in cases {
            let result = SVGContent.omittingFilterDeclarations(sheet, sheet: true)
            XCTAssertTrue(result.omitted, sheet)
            XCTAssertEqual(reading(sheet: result.css), reading(sheet: twin), sheet)
            XCTAssertFalse(SVGContent.omittingFilterDeclarations(result.css, sheet: true).omitted, "nothing is left to find: \(sheet)")
        }
    }

    /// A name the renderer's tokenizer could begin a `filter` declaration at, which the reading
    /// of the rule takes otherwise, is blanked too; so is every name that ends in `filter` where
    /// blanking one leaves another before a colon.
    func testANameLeftWhereAFilterCouldBeginIsBlanked() {
        for (css, sheet) in [("fill:red; /* filter: invert(1) */ stroke:blue", false), ("rect{fill:'filter:x'}", true),
                             ("filter afilter: invert(1)", false), ("x{y:filter afilter:z}", true)] {
            let result = SVGContent.omittingFilterDeclarations(css, sheet: sheet)
            XCTAssertTrue(result.omitted, css)
            XCTAssertEqual(result.css.utf8.count, css.utf8.count, "blanked, not cut: \(css)")
            XCTAssertFalse(SVGContent.omittingFilterDeclarations(result.css, sheet: sheet).omitted, css)
            XCTAssertFalse((sheet ? reading(sheet: result.css) : reading(style: result.css)).contains { $0.lowercased().hasPrefix("filter:") }, css)
        }
    }

    /// The scan is linear. Its worst case at the largest SVG the reader takes, a stylesheet of
    /// rules that the renderer's reading of a stylesheet has to read to its end, was measured and
    /// recorded on #253 with these shapes among others: one for each pass that can run longest.
    /// The bound catches quadratic growth, which at this size takes hours.
    func testTheFilterScanOfTheLargestStylesheetIsLinear() {
        let size = SVGContent.maximumBytes
        func fill(_ unit: String, suffix: String = "") -> String {
            String(repeating: unit, count: (size - suffix.utf8.count) / unit.utf8.count) + suffix
        }
        let shapes = [
            ("rules, then a filter after important", fill("a{b:c}", suffix: "x{fill:red !importantfilter:y}"), true),
            ("filters after a star", fill("a:b *filter:c "), false),
            ("names that end in filter", fill("xfilter afilter:"), false),
        ]
        for (name, css, sheet) in shapes {
            var result: (css: String, omitted: Bool) = ("", false)
            let seconds = cpuSeconds { result = SVGContent.omittingFilterDeclarations(css, sheet: sheet) }
            XCTAssertTrue(result.omitted, name)
            XCTAssertLessThan(seconds, 30, "\(name): \(seconds) CPU s")
        }
    }

    // MARK: #248: CSS read by scalar

    /// A combining mark after a quote leaves the quote a quote, so the filter after it is omitted
    /// and the drawing shown, as it is after `x: 'a'`.
    func testAMarkAfterAQuoteHidesNoFilter() throws {
        for value in ["'&#x301;'", "'a'"] {
            let svg = "<svg \(Self.ns) id='s' width='20' height='20'><defs><filter id='shadow'><feGaussianBlur stdDeviation='1'/></filter></defs><rect width='20' height='20' style=\"x: \(value); filter: url(#shadow); fill: red\"/></svg>"
            let data = try XCTUnwrap(try serialize(svg), value)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("filter:"), value)
            let source = try XCTUnwrap(SVGImageSource.svg(data), value)
            XCTAssertEqual(SVGTest.rgba(try XCTUnwrap(source.decode(maxPixelSize: 20)), x: 10, y: 10), [255, 0, 0, 255], value)
        }
    }

    /// Any backslash is an escape, and a `url(` to anything but a fragment leaves the document,
    /// whatever mark follows the backslash, precedes it, or follows the bracket.
    func testEscapesAndURLsAreFoundWhateverMarkIsBesideThem() {
        let twins = [("a\u{600}\\62 c", "a\\62 c"), ("a\\\u{301}c", "a\\c"),
                     ("fill: url(\u{301}http://example.com/x)", "fill: url(http://example.com/x)"),
                     ("fill: URL( '\u{301}#a')", "fill: URL( 'b#a')")]
        for (marked, twin) in twins {
            XCTAssertTrue(SVGContent.unsafeCSS(twin), twin)
            XCTAssertTrue(SVGContent.unsafeCSS(marked), marked.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))
        }
        for safe in ["fill: url(#a)", "fill: url( \"#a\")", "fill: red; font-family: 'A\u{301}'"] {
            XCTAssertFalse(SVGContent.unsafeCSS(safe), safe)
        }
    }

    /// A `font-family` list is split at a comma that a mark follows, so the family before it is
    /// aliased as it is in the mark-free list, in the attribute and in a `style`.
    func testAFamilyListIsSplitAtACommaBeforeAMark() throws {
        for (value, expected, families) in [("Foo,&#x301;Bar, Foo", "'Alias',\u{301}Bar,'Alias'", ["foo", "\u{301}bar"]),
                                            ("Foo,Bar, Foo", "'Alias',Bar,'Alias'", ["foo", "bar"])] {
            let svg = "<svg \(Self.ns) id='s' width='20' height='20'><text font-family='\(value)' style='font-family: \(value)'>a</text></svg>"
            XCTAssertEqual(SVGContent.fontFamilies(try parsed(svg)), Set(families), value)
            let data = try XCTUnwrap(try serialize(svg, fontAliases: ["foo": "Alias"]))
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(text.contains("font-family=\"\(expected)\""), text)
            XCTAssertTrue(text.contains("style=\"font-family: \(expected)\""), text)
        }
    }

    /// An embedded font's own family name comes from its file, which is book content. Before, a
    /// font whose name table said `Times'New Roman` was written `'Times'New Roman'`, and a name
    /// could end the string and add declarations of its own. Such a name is not put in the CSS:
    /// the family stays as the drawing names it. A plain name is quoted as before. EPUBLib's test
    /// of the same name checks that its font registry gives a book font such a name.
    func testAnEmbeddedFontsOwnNameIsQuotedOnlyWhenNothingInItIsCSS() throws {
        let drawing = "<svg \(Self.ns) id='s' width='180' height='40'><text x='2' y='30' font-family='BookFont' style='font-family: BookFont; font-size: 24px'>Archive font</text></svg>"
        let data = try XCTUnwrap(try serialize(drawing, fontAliases: ["bookfont": "Times'New Roman"]))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("font-family=\"BookFont\" style=\"font-family: BookFont; font-size: 24px\""), text)

        let injected = "<svg \(Self.ns) id='s' width='20' height='20'><rect width='20' height='20' style='fill: red; font-family: BookFont'/></svg>"
        for (alias, written) in [("x'; fill: blue; y: 'z", "BookFont"), ("x\\'; fill: blue", "BookFont"), ("A;B", "BookFont"), ("A{B", "BookFont"),
                                 ("url(a)", "BookFont"), ("Book Font Pro", "'Book Font Pro'"), ("Gill Sans MT", "'Gill Sans MT'"),
                                 ("M+ 1p", "'M+ 1p'"), ("ヒラギノ明朝 ProN", "'ヒラギノ明朝 ProN'"), ("Cafe\u{301}", "'Cafe\u{301}'")] {
            let data = try XCTUnwrap(try serialize(injected, fontAliases: ["bookfont": alias]))
            let style = try XCTUnwrap(try parsed(String(decoding: data, as: UTF8.self)).elementChildren.first?.attribute("style"))
            XCTAssertEqual(reading(style: style), ["fill:red", "font-family:" + written], alias)
        }
    }
}
