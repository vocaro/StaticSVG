# StaticSVG

StaticSVG draws static SVG that nobody vetted — from a book, a document or a message — into a
`CGImage` on iOS, iPadOS and macOS. Drawing is done by a bundled, patched build of
[resvg](https://github.com/linebender/resvg). StaticSVG is what a host needs around it when it
cannot trust its input:

- **It reads nothing on its own.** The renderer opens no file and fetches no URL. A drawing's
  images come from the host, through a resource provider, and are decoded and inlined within
  byte and pixel budgets.
- **It bounds the work before it starts.** The exact bytes the renderer will read are screened
  first: size, depth, `<use>` expansion, text, stylesheet work, reference loops, geometry,
  raster memory, markers and per-shape copies. A drawing past a bound is refused.
- **It prepares fonts.** Faces are exported from CoreText as SFNT bytes with color glyph tables
  removed, shared between drawings and held to one memory reservation.
- **It fails without crashing.** A renderer panic is caught and becomes a refused drawing or a
  failed draw, and the drawing's own title, description or text stand in for it.
- **It says what it left out.** Scripts, animation, filter effects, refused stylesheets and
  images that could not be inlined are counted for the host to disclose.
- **It needs no Rust.** The renderer ships as a static XCFramework, built reproducibly from
  pinned sources.

[Design](doc/design.md) explains why each of these exists, why resvg alone and the Swift SVG
packages reviewed do not provide them, and where the guarantees end: catching panics is not a
sandbox, and the bounds are not a promise that every hostile drawing is refused.

Requires iOS/iPadOS or macOS 27+, Swift 6.2 and Xcode 27.

## Installation

```swift
.package(url: "https://github.com/vocaro/StaticSVG.git", exact: "0.1.2"),
```

and `.product(name: "StaticSVG", package: "StaticSVG")` in the target that draws.

## Quick start

Parse, serialize, then draw. Serialization removes what a static drawing must not run or reach
and inlines its images; the renderer screens the result again and draws it at any size.

```swift
import StaticSVG

let document = try SVGDocument.parse(svgData)
let serialization = document.serialized(resolve: { reference in reference },
                                        resources: MyResources(), fontAliases: [:])
// serialization.diagnostics counts what was removed or could not be inlined.
if let data = serialization.data, let renderer = SVGRenderer(data, fonts: []) {
    let image = renderer.render(maxPixelSize: 1024)   // CGImage, or nil if the draw fails
} else {
    show(document.fallbackText)                       // title and description, or its text
}
```

`MyResources` gives the bytes of the images a drawing names; StaticSVG reads nothing else:

```swift
struct MyResources: SVGResourceProvider {
    let files: [String: Data]
    func data(at path: String) -> Data? { files[path] }
}
```

`resolve` maps an `<image>` reference to a path the provider knows; a reference it returns nil
for, and every image when there is no provider, is left out and counted. `data:` images are read
from the drawing itself. A provider can also give fallbacks for a resource, its media type,
resolve references inside a nested SVG image, and parse the host's SVG files its own way.

A host that already has a parsed tree, such as an `<svg>` element inside an XHTML page, builds
an `SVGDocument` from it with `SVGDocument.Builder` instead of serializing it to bytes and
parsing them again. For text, give `SVGRenderer` the faces a drawing names
(`document.fontFamilies`), exported with `SVGFontData.export(_:)`.

## Documentation

- [Design](doc/design.md): why the package exists, how it compares with resvg alone and
  with other Swift SVG packages, and its scope, limits and failure behavior.
- [The bundled renderer](doc/renderer.md): the pinned resvg build, its patches and its panic
  boundary.
- [Maintenance](doc/maintenance.md): rebuilding and verifying the renderer, releasing it,
  keeping its notices, and what to review when resvg changes.
- [Testing](doc/testing.md).
- [Comparison notes](doc/research/alternatives-2026-10-21.md): the sources behind the design's
  comparison.
- [Release notes](CHANGELOG.md).

## License

StaticSVG is available under the [MIT license](LICENSE). The renderer library it links contains
resvg and other Rust crates under their own permissive licenses; an application that ships it
must retain their notices ([third-party notices](THIRD_PARTY_NOTICES.md)).
