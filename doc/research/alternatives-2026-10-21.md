# Swift SVG packages considered before StaticSVG

Research for the StaticSVG design document: why the existing Swift SVG packages were not
adopted directly for rendering untrusted static SVG from EPUB books on iOS/iPadOS 27 and
macOS 27.

This is a source and documentation comparison. It is not a rendering-parity test and not a
security audit. Where a guarantee (a processing bound, a resource restriction) is neither
documented nor evident in the files read, it is recorded as "not documented" or "not found in
the files read". That is a statement about this reading, not a claim that the project is
unsafe or incapable.

Sources were read on two days because the session was interrupted. Each section gives the
date its sources were read: **2026-10-21** (repository metadata, releases and tags for all
four projects; swift-resvg and SwiftDraw sources) or **2026-10-22** (SVGKit, SVGView and
upstream resvg sources; the four default-branch heads were re-checked on 2026-10-22 and had
not moved). All GitHub API reads were unauthenticated-equivalent GETs through `gh api`;
file contents came from `raw.githubusercontent.com` at the commit named.

## Contract being compared against

- Platforms: iOS 27 device (arm64), iOS simulator (arm64, x86_64), macOS 27 (arm64, x86_64);
  Swift Package Manager; no Rust toolchain for consumers.
- Supplied resources only: the renderer never opens a path or fetches a URL; image bytes come
  from the host through a bounded interface; `data:` images only, png/jpeg/gif/webp, no nested
  SVG decoded by the renderer.
- Fonts: host-supplied SFNT bytes, no system font scanning, color glyph tables removed.
- Budgets checked before rendering: input bytes, depth, nodes, `<use>` expansion, text run
  length, stylesheet work, reference chains and loops, geometry, raster memory.
- Failure: renderer panics caught at the C boundary; failure is recoverable, not a crash.
- API: Swift, draws into a `CGImage` at arbitrary sizes, thread-safe immutable trees.

## Summary

| Project | Version / date | License | Platforms (manifest) | Engine | Resource model | Fonts | Documented bounds | Failure handling | API |
|---|---|---|---|---|---|---|---|---|---|
| [swift-resvg](https://github.com/alexey1312/swift-resvg) | `v0.45.1-swift.15`, 2026-02-23; `main` head 2026-02-23 | MIT (wrapper); resvg Apache-2.0 OR MIT | macOS 12 only (plus Linux, Windows); no iOS slice | resvg 0.45.1 static library, C API extended by an appended patch | Upstream usvg defaults; wrapper sets no options; C API has no href hook | None loaded; C API fontdb empty by default; no font API in wrapper | Upstream 1,000,000-element limit only | Throws `ResvgError` for parse errors; no `catch_unwind` | `RasterizedSvg` (RGBA `[UInt8]`), `SvgTree` traversal, normalizer |
| [SwiftDraw](https://github.com/swhitty/SwiftDraw) | `0.29.0`, 2026-07-19; `main` head 2026-08-25 | Zlib | iOS 13, macOS 10.15, tvOS 13, watchOS 6, visionOS 1 | Own Swift XML/DOM parser, CoreGraphics command renderer | `<image>`: `data:` png/jpeg only; `@font-face`: `data:` only; file/URL entry points exist | `CTFontCreateWithName` (installed fonts) or `data:` TTF/WOFF/WOFF2 | Not documented; cache cost limit only | `init?` returns nil and logs; unsupported elements skipped | `SVG` value, `CGContext.draw`, `UIImage`/`NSImage`/PNG/JPEG/PDF, SwiftUI `SVGView`/`AsyncSVGView` |
| [SVGKit](https://github.com/SVGKit/SVGKit) | `3.0.0`, 2021-04-15 (CocoaPods 3.0.0, 2021-04-16); `3.x` head 2026-09-21 | MIT-style text (GitHub: NOASSERTION) | iOS 13, macOS 10.10, tvOS 13 (SPM); 11.0 (podspec) | Objective-C, libxml2 SAX parser, DOM, CoreAnimation `CALayer` tree | Synchronous fetch of `http(s):` image hrefs; relative paths resolved against the source URL/file; `data:` base64 | Installed font families (`UIFont.familyNames` / `NSFontManager`) | Not documented | Parse errors in `SVGKParseResult`; `NSAssert` in source (blocked in SPM release builds) | `SVGKImage` (`UIImage`, `CALayerTree`), image views, exporters |
| [SVGView](https://github.com/exyte/SVGView) | tag `1.0.6`, 2023-08-30 (no GitHub releases); `main` head 2026-07-08 (README only since 1.0.6) | MIT | iOS 14, macOS 11, watchOS 7 | Own Swift parser to SwiftUI views | `SVGLinker`: `.none`, base URL or relative to SVG file (`Data(contentsOf:)`); `data:` png/jpg/svg+xml | SwiftUI `Font.custom(name:)` (installed or registered fonts) | Not documented; `<use>` recursion check | Returns optional `SVGNode`; errors logged | SwiftUI `View` (`SVGView`), mutable `SVGNode` model |

## swift-resvg (alexey1312/swift-resvg)

Read 2026-10-21 (metadata, tags, sources); head re-checked 2026-10-22.

- **Latest release**: `v0.45.1-swift.15`, published 2026-02-23T18:23:29Z
  ([release](https://github.com/alexey1312/swift-resvg/releases/tag/v0.45.1-swift.15),
  [API](https://api.github.com/repos/alexey1312/swift-resvg/releases/latest)). Tag commit
  `6707e4f94a05b4ea91e82cafa9b6c4ecb78a73bb` (2026-02-23T18:23:14Z), on branch
  `release/artifact-bundle`. A second release branch `release/xcframework` is at
  `ffd0809bfbb375d7359c1aa0fc66feab96be04c8`. GitHub's compare API reports no common ancestor
  between the release commits and `main`.
- **Default branch**: `main`, head `7996384aad0ecbc310d5e3926a715eddab9281d6`,
  2026-02-23T17:33:25Z ([commits API](https://api.github.com/repos/alexey1312/swift-resvg/commits?sha=main&per_page=1)).
  0 open issues; 2 stars (repo API, 2026-10-21).
- **License**: MIT, "Copyright (c) 2025 Aleksei Kakoulin"
  ([LICENSE](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/LICENSE)).
  README: "resvg is licensed under Apache 2.0 or MIT."
- **Platforms**: `platforms: [.macOS(.v12)]` in both release manifests
  ([artifact-bundle Package.swift](https://github.com/alexey1312/swift-resvg/blob/6707e4f94a05b4ea91e82cafa9b6c4ecb78a73bb/Package.swift),
  [xcframework Package.swift](https://github.com/alexey1312/swift-resvg/blob/ffd0809bfbb375d7359c1aa0fc66feab96be04c8/Package.swift)).
  The artifact bundle lists triples `arm64-apple-macosx`, `x86_64-apple-macosx`, Linux
  x86_64/aarch64 and Windows x86_64/aarch64 MSVC
  ([info.json](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/resvg.artifactbundle/info.json)).
  The XCFramework is built from the single `macos-universal/libresvg.a`
  ([Scripts/build-xcframework.sh](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/Scripts/build-xcframework.sh)).
  No iOS device or simulator slice was found in the manifests, bundle metadata or build
  scripts read.
- **Distribution**: SPM binary target only. Artifact bundle (SE-0482, Swift 6.2+) zip
  60,125,588 bytes; XCFramework zip (Swift 5.9+) 16,380,117 bytes (release assets,
  [API](https://api.github.com/repos/alexey1312/swift-resvg/releases/latest)). Consumers need no
  Rust; rebuilding "requires Rust + Docker"
  ([README](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/README.md)).
  No CocoaPods or Carthage files in the tree. The release workflow installs
  `dtolnay/rust-toolchain@stable`
  ([release.yml](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/.github/workflows/release.yml), lines 33, 108).
- **Engine**: resvg 0.45.1. `Scripts/build.sh` defaults `RESVG_VERSION` to 0.45.1 (line 34),
  clones upstream (line 61), then appends Rust functions to `crates/c-api/lib.rs` for SVG
  export and tree traversal (`resvg_tree_to_svg`, `resvg_tree_root`, `resvg_node_as_text`, ...)
  ([build.sh](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/Scripts/build.sh)).
  Feature coverage is therefore upstream resvg 0.45.1's (text, CSS, masks, clip paths,
  markers, patterns, filters, gradients, `<use>`, images); the wrapper adds no SVG features.
- **API shape**: `SvgRasterizer.rasterize(data:scale:)` and `rasterize(file:scale:)` return
  `RasterizedSvg { width, height, rgba: [UInt8] }`, straight alpha
  ([SvgRasterizer.swift](https://github.com/alexey1312/swift-resvg/blob/6707e4f94a05b4ea91e82cafa9b6c4ecb78a73bb/Sources/Resvg/SvgRasterizer.swift), lines 33, 44).
  `SvgTree` exposes a node tree (group, path, image, text) and `toSvgString()`
  ([SvgTree.swift](https://github.com/alexey1312/swift-resvg/blob/6707e4f94a05b4ea91e82cafa9b6c4ecb78a73bb/Sources/Resvg/SvgTree.swift));
  `SvgNormalizer` returns usvg-normalized SVG. No `CGImage`, `CGContext` or target-size API.
- **Options and resources**: every entry point calls `resvg_options_create()` and sets nothing
  else (SvgRasterizer.swift line 46; SvgTree.swift line 34). The bundled C header declares
  `resvg_options_set_resources_dir` (line 165) and `resvg_options_load_system_fonts` (line 334)
  but no function for an image href resolver
  ([resvg.h](https://github.com/alexey1312/swift-resvg/blob/7996384aad0ecbc310d5e3926a715eddab9281d6/resvg.artifactbundle/include/resvg.h)).
  `<image>` handling is therefore upstream usvg's default (see the upstream section), which the
  wrapper exposes no way to change. `ImageKind` includes `.svg`
  ([Image.swift](https://github.com/alexey1312/swift-resvg/blob/6707e4f94a05b4ea91e82cafa9b6c4ecb78a73bb/Sources/Resvg/Image.swift)).
- **Fonts**: the wrapper loads none and has no font API. Upstream documents the C API font
  database as "empty by default" (resvg c-api `lib.rs` line 113 at v0.48.1; not re-checked at
  0.45.1).
- **Input limits**: `ResvgError.elementsLimitReached` maps upstream's limit, described as
  "SVG has more than 1,000,000 elements (security limit)"
  ([ResvgError.swift](https://github.com/alexey1312/swift-resvg/blob/6707e4f94a05b4ea91e82cafa9b6c4ecb78a73bb/Sources/Resvg/ResvgError.swift), line 49).
  No other bound is documented. The rasterizer allocates `width * height * 4` bytes from the
  SVG's declared size times `scale` with no upper bound in that function (SvgRasterizer.swift
  lines 82-90).
- **Failure handling**: parse errors become thrown `ResvgError` values. A search of the Rust
  patch appended by `build.sh` and of upstream 0.45.1 `crates/c-api/lib.rs`
  ([at v0.45.1](https://github.com/linebender/resvg/blob/1b6c2fddbcbeffa8135df4323b02aaae84890907/crates/c-api/lib.rs), read 2026-10-22)
  found no `catch_unwind`. See the upstream section for what a panic does at that boundary.
- **Thread safety**: `SvgRasterizer` is a `Sendable` struct (line 24); `SvgTree` is declared
  `final class SvgTree: @unchecked Sendable` (SvgTree.swift line 26). No threading notes in the
  README.

## SwiftDraw (swhitty/SwiftDraw)

Read 2026-10-21 (all items); head re-checked 2026-10-22. Files at tag `0.29.0`, commit
`82699f4bdf2f075793cfa0d392eb27c59b41a3fe`. Base URL below:
`https://github.com/swhitty/SwiftDraw/blob/82699f4bdf2f075793cfa0d392eb27c59b41a3fe/`.

- **Latest release**: `0.29.0` "Template / AsyncSVGView", published 2026-07-19T10:28:23Z
  ([release](https://github.com/swhitty/SwiftDraw/releases/tag/0.29.0)). Earlier: 0.28.1
  (2026-07-15), 0.28.0 (2026-07-03), 0.27.0 (2026-02-23).
- **Default branch**: `main`, head `cf234e7739058fd1c2558728997157db959ffc02`,
  2026-08-25T22:30:15Z. Eight commits after 0.29.0 touch `<use>` href parsing, viewBox commas,
  SF Symbol validation and samples
  ([compare](https://github.com/swhitty/SwiftDraw/compare/0.29.0...main)). 654 stars, 7 open
  issues (repo API).
- **License**: zlib ([LICENSE.txt](https://github.com/swhitty/SwiftDraw/blob/82699f4bdf2f075793cfa0d392eb27c59b41a3fe/LICENSE.txt)).
- **Platforms**: `.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)`,
  swift-tools-version 6.0 ([Package.swift](https://github.com/swhitty/SwiftDraw/blob/82699f4bdf2f075793cfa0d392eb27c59b41a3fe/Package.swift));
  same minimums in the podspecs.
- **Distribution**: SPM and CocoaPods (`SwiftDraw` and `SwiftDrawDOM` podspecs, version
  0.29.0) ([SwiftDraw.podspec.json](https://github.com/swhitty/SwiftDraw/blob/82699f4bdf2f075793cfa0d392eb27c59b41a3fe/SwiftDraw.podspec.json));
  source, pure Swift, no dependencies, no Rust. Also a CLI (`swiftdraw`, Homebrew).
- **Engine**: own parser ("a pure-Swift SVG parser and renderer",
  [README](https://github.com/swhitty/SwiftDraw/blob/82699f4bdf2f075793cfa0d392eb27c59b41a3fe/README.md)).
  XML is read with Foundation `XMLParser` (`DOM/Sources/XML.SAXParser.swift`), converted to a
  DOM, then a LayerTree, then CoreGraphics render commands (`SwiftDraw/Sources/SVG.swift`
  lines 162-179).
- **Feature coverage (from the parser)**: elements `g`, `line`, `circle`, `ellipse`, `rect`,
  `polyline`, `polygon`, `path`, `text`, `a`, `use`, `switch`, `image`, `svg`
  (`DOM/Sources/Parser.XML.Element.swift` lines 84-101). Defs: `clipPath`, `mask`, `pattern`,
  linear and radial gradients (`DOM/Sources/Parser.XML.SVG.swift` lines 131-135). Filters:
  only `feGaussianBlur` is parsed (`DOM/Sources/Parser.XML.Filter.swift` line 66), with an
  option `hideUnsupportedFilters` (SVG.swift line 98). Markers: the string "marker" does not
  occur in `DOM/Sources` or `SwiftDraw/Sources`. Text: one string per `<text>`, taking the
  first `<tspan>` (`DOM/Sources/Parser.XML.Text.swift` lines 36-43). CSS: `<style>` with id,
  element and class selectors (`DOM/Sources/DOM.SVG.swift` lines 101-105) and `@font-face`;
  other at-rules skipped (`DOM/Sources/Parser.XML.StyleSheet.swift` lines 101, 127-129).
- **Resource loading**: `SVG(data:)` parses bytes without file access (SVG.swift lines 87-90,
  157-160); `SVG(fileURL:)`, `SVG(named:in:)` and `UIImage(contentsOfSVGFile:)` read files the
  host names. `<image>` resolves only `data:` URLs: `decodedData` requires `data:` with
  `;...base64,` (`DOM/Sources/URL+Data.swift` line 54), `LayerTree.Image` accepts
  `image/png`, `image/jpeg`, `image/jpg` (`SwiftDraw/Sources/LayerTree/LayerTree.Image.swift`
  lines 55-57), and anything else throws and the element is skipped via `try?`
  (`SwiftDraw/Sources/LayerTree/LayerTree.Builder.Layer.swift` lines 77-79;
  `LayerTree.Builder.swift` line 158). Images are decoded with `UIImage(data:)` /
  `NSImage(data:)` (`Renderer/Renderer.CoreGraphics.swift` line 313). `AsyncSVGView` fetches
  the SVG document itself with an injectable `URLSession` (`AsyncSVGView.swift` line 37). No
  host hook for sub-resources was found; none is needed for files because sub-resource URLs
  other than `data:` are not loaded.
- **Fonts**: `font-family` names go to `CTFontCreateWithName` and are kept only if the
  PostScript or family name matches (`Renderer/Renderer.CoreGraphics.swift` lines 226-241);
  generic families map to Times, Helvetica, Courier, Papyrus, Apple Chancery
  (`LayerTree/LayerTree.Builder.swift` lines 306-321); the fallback is Times (line 245). Fonts
  can also come from `@font-face` `data:` URLs as TrueType, WOFF or WOFF2; a non-`data:` source
  throws "unsupported format" (`LayerTree.Builder.swift` lines 333-359). There is no API for a
  host-supplied font set separate from installed fonts.
- **Input limits**: none documented in the README. The only size limit found is the
  `SVGGCache` total cost (200 MB AppKit, 50 MB otherwise; `SVGCache.swift`). Traversal was
  made iterative in merged PR [#76](https://github.com/swhitty/SwiftDraw/pull/76) (merged
  2025-04-13) after issue [#72](https://github.com/swhitty/SwiftDraw/issues/72) reported a
  crash on a deeply nested SVG off the main thread; the explicit stack is at
  `LayerTree.Builder.swift` line 99. `<use>` is expanded by building the referenced element
  again (`LayerTree.Builder.Layer.swift` lines 43-57); no reference-cycle check was found in
  the files read. Open, unmerged PR [#142](https://github.com/swhitty/SwiftDraw/pull/142)
  (2026-10-09) lists "reference cycles never crash" among its proposed changes.
- **Failure handling**: public initializers are failable; a parse error is logged and `nil`
  returned (SVG.swift lines 57-59, 72-73). The parser defaults to `.skipInvalidElements`
  (`DOM/Sources/DOM.SVG+Parse.swift`).
- **Thread safety**: `public struct SVG: Hashable, Sendable` (SVG.swift line 42), an immutable
  value holding render commands. With `scale <= 0`, `rasterize` reads `UIScreen.main.scale`
  through `DispatchQueue.main.sync` when called off the main thread (`UIImage+SVG.swift`
  lines 126-153).
- **API shape**: `SVG` value with `sized`, `scaled`, `expanded`; `CGContext.draw(_:in:)`
  (`SVG+CoreGraphics.swift` line 38); `rasterize` to `UIImage`/`NSImage`; `pngData`,
  `jpegData`, `pdfData`; SwiftUI `SVGView` and `AsyncSVGView`. A host can draw into its own
  bitmap `CGContext` and take a `CGImage` from it.

## SVGKit (SVGKit/SVGKit)

Metadata and tags read 2026-10-21; sources read 2026-10-22 at the default-branch head
`6002a0ff6b2d4405805395959b92b38aa24662cb` (branch `3.x`). Base URL below:
`https://github.com/SVGKit/SVGKit/blob/6002a0ff6b2d4405805395959b92b38aa24662cb/`.

- **Latest release**: `3.0.0`, published 2021-04-15T23:53:49Z
  ([release](https://github.com/SVGKit/SVGKit/releases/tag/3.0.0)); tag commit
  `58152b9f7c85eab239160b36ffdfd364aa43d666` dated 2021-02-21. The podspec on `3.x` says
  version 3.1.1, but the repository has no 3.1.1 tag (tags API lists 3.0.0, 2.1.0, 2.0.0,
  v1.2.0, v1.1.0, v1.0), and CocoaPods trunk's newest is 3.0.0, 2021-04-16
  ([trunk API](https://trunk.cocoapods.org/api/v1/pods/SVGKit), read 2026-10-22).
- **Default branch**: `3.x`, head 2026-09-21T21:08:41Z ("Update CocoaLumberjack dependency
  version range (#879)"). Repo `pushed_at` 2026-10-13. 280 open issues, 4,582 stars.
- **License**: GitHub reports `NOASSERTION`; the
  [LICENSE](https://github.com/SVGKit/SVGKit/blob/6002a0ff6b2d4405805395959b92b38aa24662cb/LICENSE)
  text is the MIT permission notice ("Copyright (c) 2010-2011 Matt Rajca, 2011-2025 various
  authors, Parts Copyright (c) Tipbit Inc"); the podspec says `'MIT'`.
- **Platforms**: `.macOS(.v10_10), .iOS(.v13), .tvOS(.v13)` (swift-tools-version 5.3,
  [Package.swift](https://github.com/SVGKit/SVGKit/blob/6002a0ff6b2d4405805395959b92b38aa24662cb/Package.swift));
  podspec 11.0 for iOS, macOS, tvOS
  ([SVGKit.podspec](https://github.com/SVGKit/SVGKit/blob/6002a0ff6b2d4405805395959b92b38aa24662cb/SVGKit.podspec)).
- **Distribution**: SPM, CocoaPods, Carthage and a manual static library
  ([README.mdown](https://github.com/SVGKit/SVGKit/blob/6002a0ff6b2d4405805395959b92b38aa24662cb/README.mdown)).
  Objective-C source; depends on CocoaLumberjack (`3.7.0...3.9.1` in Package.swift) and
  links libxml2 and CoreText (podspec). No Rust. A `SVGKitSwift` product adds SwiftUI
  wrappers.
- **Engine**: libxml2 push parser (`Source/Parsers/SVGKParser.m` line 226) into an SVG DOM,
  rendered as a CoreAnimation `CALayer` tree (repo description: "native rendering
  (CoreAnimation)"). The `xmlCtxtUseOptions` call with `XML_PARSE_NOENT` is inside a comment
  block (SVGKParser.m lines 228-235).
- **Feature coverage (from the parser)**: element classes for `svg`, `circle`, `description`,
  `ellipse`, `g`, `clipPath`, `image`, `line`, `path`, `polygon`, `polyline`, `rect`,
  `switch`, `title`, `text`, `textArea` (`Source/Parsers/Parser Extensions/SVGKParserSVG.m`
  lines 36-51); `defs` and `use` (`SVGKParserDefsAndUse.m` line 27); gradients
  (`SVGKParserGradient.m`); `<style>` (`SVGKParserStyles.m`). Patterns:
  `NSAssert( FALSE, @"Patterns are not supported by SVGKit yet ...")`
  (`SVGKParserPatternsAndGradients.m` line 44). No parser for `mask`, `marker` or `filter`
  elements was found in `Source/`.
- **Resource loading**: in `SVGImageElement.m`
  (`Source/DOM classes/Unported or Partial DOM/SVGImageElement.m`): `http:`/`https:` hrefs are
  fetched with `[NSData dataWithContentsOfURL:]` (line 73); `data:` hrefs are base64-decoded
  (line 76); other hrefs are resolved against the document's source with
  `sourceFromRelativePath:` (line 99), which for a local file or URL source uses
  `NSURL URLWithString:relativeToURL:` (`Source/Sources/SVGKSourceLocalFile.m` line 111,
  `SVGKSourceURL.m`, `SVGKSourceNSData.m` line 44 when an effective URL exists). If the bytes
  are not an image Apple decodes, it tries to parse them as an embedded SVG (lines 117-124).
  `SVGKImage` also offers `imageWithContentsOfURL:` (`Source/SVGKImage.h` line 104). No
  documented hook for a host to forbid or supply these loads was found. Open issue
  [#776](https://github.com/SVGKit/SVGKit/issues/776) (2022-12-13) reports a CFNetwork warning
  about synchronous URL loading on the main thread.
- **Fonts**: `font-family` is matched against installed families (`UIFont.familyNames`, or
  `NSFontManager` on macOS), then `CTFontCreateWithFontDescriptor`, with a system-font
  fallback (`SVGTextElement.m` lines 359-420). No supplied-font interface found.
- **Input limits**: not documented. No depth, node, `<use>`-expansion or raster limits found
  in the files searched; no `<use>` cycle check found in `SVGKParserDefsAndUse.m`.
- **Failure handling**: parse errors and warnings are collected in `SVGKParseResult`
  (`SVGKImage.parseErrorsAndWarnings`, SVGKImage.h line 67); `xmlParseChunk` is wrapped in
  `@try/@catch` (SVGKParser.m lines 265-269). The source contains 163 lines matching
  `NSAssert`, `@throw` or `NSException raise`; the SPM manifest defines `NS_BLOCK_ASSERTIONS=1`
  for release builds (Package.swift). Open issues report assertion and parser crashes, for
  example [#839](https://github.com/SVGKit/SVGKit/issues/839) ("SVGLength.m:571 Assert crash",
  2024-08-05) and [#641](https://github.com/SVGKit/SVGKit/issues/641) (2019-08-22).
- **Thread safety**: not documented beyond the asynchronous loaders
  (`imageWithDataAsynchronously:onCompletion:`, SVGKImage.h line 122). The parser stores the
  active parser in the thread dictionary (SVGKParser.m). `SVGKImage` is a mutable `NSObject`.
- **API shape**: `SVGKImage` with `UIImage` (SVGKImage.h line 64) and `CALayerTree` (line 71),
  `SVGKFastImageView`, `SVGKLayeredImageView`, exporters to `UIImage`/`NSImage`/`NSData`
  (`Source/Exporters/`).

## SVGView (exyte/SVGView)

Metadata and tags read 2026-10-21; sources read 2026-10-22 at `main` head
`fd9f0303bc2da37e5d1ea98f42835c8273361c7b`. The compare from tag `1.0.6` to `main` changes
only `README.md`
([compare](https://github.com/exyte/SVGView/compare/1.0.6...main)), so the sources equal tag
`1.0.6` (`6465962facdd25cb96eaebc35603afa2f15d2c0d`). Base URL below:
`https://github.com/exyte/SVGView/blob/fd9f0303bc2da37e5d1ea98f42835c8273361c7b/`.

- **Latest release/tag**: no GitHub releases (`releases/latest` returns 404). Newest tag
  `1.0.6`, commit dated 2023-08-30T04:55:54Z ("Bump version").
- **Default branch**: `main`, head 2026-07-08T08:24:43Z ("Update README.md"). 44 open issues,
  860 stars.
- **License**: MIT, "Copyright (c) 2020 exyte"
  ([LICENSE](https://github.com/exyte/SVGView/blob/fd9f0303bc2da37e5d1ea98f42835c8273361c7b/LICENSE)).
- **Platforms**: `.macOS(.v11), .iOS(.v14), .watchOS(.v7)`, swift-tools-version 5.3,
  Swift 5 language mode
  ([Package.swift](https://github.com/exyte/SVGView/blob/fd9f0303bc2da37e5d1ea98f42835c8273361c7b/Package.swift));
  podspec iOS 14.0, macOS 11.0, version 1.0.6.
- **Distribution**: SPM, CocoaPods, Carthage
  ([README](https://github.com/exyte/SVGView/blob/fd9f0303bc2da37e5d1ea98f42835c8273361c7b/README.md));
  Swift source, no dependencies, no Rust.
- **Engine**: own Swift parser over Foundation `XMLParser` (`Source/Parser/XML/DOMParser.swift`)
  producing an `SVGNode` model rendered as SwiftUI views. The README describes the goal as
  representing SVG "in SwiftUI" with interactivity and animation.
- **Feature coverage**: the parser table maps `svg`, `g`, `use`, `text`, `image`, `rect`,
  `circle`, `ellipse`, `line`, `polygon`, `polyline`, `path`
  (`Source/Parser/SVG/SVGParser.swift` lines 54-65). Gradients come from an index
  (`SVGIndex.swift`); `clip-path` references are followed in `SVGElementParser.swift`
  (lines 24-27). CSS: id, class and tag selectors (`Source/Parser/CSS/CSSParser.swift`
  lines 10-12). The project's generated
  [w3c-coverage.md](https://github.com/exyte/SVGView/blob/fd9f0303bc2da37e5d1ea98f42835c8273361c7b/w3c-coverage.md)
  reports SVG 1.1 coverage of 19.3% (101/522), with Text 0.0%, Fonts 0.0%, Filters 0.0%,
  Masking 5.2%, Pservers 18.1%, Struct 9.7%, Styling 16.6%.
- **Resource loading**: `SVGImageParser` decodes `data:` URLs with prefixes `image/png`,
  `image/jpg`, `image/svg+xml` and base64 (`Source/Parser/SVG/Elements/SVGImageParser.swift`
  lines 19-27); any other href goes to `context.linker.load(src:)` (line 31). `SVGLinker`
  offers `.none`, `.base(url:)` and `.relative(to:)`; the URL linker returns
  `Data(contentsOf: url.appendingPathComponent(src))`
  (`Source/Parser/SVG/Settings/SVGLinker.swift` lines 10-38). `SVGLinker` is declared
  `public class`, not `open`. Parsing from `Data` uses `.none` by default
  (`SVGSettings.swift` line 20); parsing `contentsOf:` a URL switches to a linker relative to
  that file (`SVGParser.swift` line 14, `SVGSettings.swift` line 27). Decoded image bytes are
  shown through `UIImage(data:)` / `NSImage(data:)` (`Model/Images/SVGDataImage.swift`,
  `SVGURLImage.swift`).
- **Fonts**: `SVGFont.toSwiftUI()` returns `Font.custom(name, size:)`
  (`Source/Model/Primitives/SVGFont.swift` line 16), so names resolve against fonts available
  to SwiftUI. No supplied-font interface found; no `@font-face` handling found.
- **Input limits**: not documented. A `<use>` chain that revisits an id is refused with the log
  message "<use> recursion detected!" (`Source/Parser/SVG/SVGContext.swift` lines 77-86). No
  depth, node or raster limits found in the files searched.
- **Failure handling**: parse functions return `SVGNode?`; XML errors go to an `SVGLogger`
  (`DOMParser.swift`). Open issues report a crash for `currentColor`
  ([#67](https://github.com/exyte/SVGView/issues/67), 2024-12-18), a macOS crash in
  `NSBezierPath.appendArc` with NaN/inf angles ([#81](https://github.com/exyte/SVGView/issues/81),
  2026-02-24) and a hang with `stroke-dasharray:none`
  ([#82](https://github.com/exyte/SVGView/issues/82), 2026-03-15).
- **Thread safety**: not documented. `SVGNode` is a class with `@Published` mutable properties
  (`Source/Model/Nodes/SVGNode.swift` lines 4-11). Open issue
  [#57](https://github.com/exyte/SVGView/issues/57) (2023-12-04) is titled "DOMParser working
  on Main thread".
- **API shape**: SwiftUI `struct SVGView: View` with `init(contentsOf:)`, `init(data:)`,
  `init(string:)`, `init(stream:)` and `getNode(byId:)`
  (`Source/Parser/SVG/SVGView.swift`). No `CGImage`, `UIImage` or `CGContext` output in the
  sources.

## Upstream resvg / usvg 0.48.x

Read 2026-10-22 at tag `v0.48.1`, commit `68b14c4c3bccdb60344c777406486b54c36ec1a4`
(released 2026-08-02T14:14:17Z; `v0.48.0` the same day). Repository
[linebender/resvg](https://github.com/linebender/resvg), license Apache-2.0 OR MIT (file
headers: `SPDX-License-Identifier: Apache-2.0 OR MIT`). Base URL below:
`https://github.com/linebender/resvg/blob/68b14c4c3bccdb60344c777406486b54c36ec1a4/`.

- **Resource resolution hook (Rust API)**: `usvg::Options` has `resources_dir`,
  `image_href_resolver`, `font_resolver`, `fontdb` and `style_sheet`
  (`crates/usvg/src/parser/options.rs` lines 13-100). `ImageHrefResolver` has
  `resolve_data` and `resolve_string`; its doc says it can be used to "forbid access to local
  files (which is allowed by default)" and that "usvg doesn't do any network requests"
  (`crates/usvg/src/parser/image.rs` lines 23-37).
  - Default data resolver: `image/jpg`/`jpeg`, `png`, `gif`, `webp`, and `image/svg+xml`
    parsed as a nested SVG; `text/plain` is sniffed (image.rs lines 58-76).
  - Default string resolver: treats the href as a file path, made absolute against
    `resources_dir` when set and used as given otherwise (`options.rs` `get_abs_path`), and
    reads it with `std::fs::read` if it exists (image.rs lines 85-110).
  - A nested SVG image is parsed with `from_data_nested`, which keeps the data resolver and
    ignores string (external) hrefs (`crates/usvg/src/parser/mod.rs` lines 121-155).
- **C API**: the C header has no function for an image href resolver or font resolver (search
  of `crates/c-api/resvg.h` for "href" and "resolver" found none). It offers
  `resvg_options_set_resources_dir`, `resvg_options_load_font_data`,
  `resvg_options_load_font_file` and `resvg_options_load_system_fonts`
  (`crates/c-api/lib.rs` lines 145, 413, 445, 472).
- **Font database**: `Options::default()` uses `fontdb::Database::new()` (options.rs line 120);
  the C API notes "The database is empty by default" (`crates/c-api/lib.rs` line 113). System
  fonts are loaded only when asked (`load_system_fonts`). The `system-fonts` and
  `memmap-fonts` Cargo features are on by default for both the `resvg` crate and the C API
  (`crates/resvg/Cargo.toml` line 34, `crates/c-api/Cargo.toml` line 20).
- **Built-in limits and loop checks** (a keyword search of `crates/usvg/src`):
  - More than 1,000,000 nodes fails with `NodesLimitReached`
    (`crates/usvg/src/parser/svgtree/parse.rs` lines 183, 417-418), surfaced as
    `ElementsLimitReached`, documented "We do not allow SVG with more than 1_000_000 elements
    for security reasons" (`parser/mod.rs` lines 40-41).
  - Recursive `<use>` is detected and skipped (svgtree/parse.rs lines 610-645); recursive
    patterns, clip paths, masks, filters and `feImage` are removed
    (svgtree/parse.rs lines 125-129); recursive markers are skipped (`parser/marker.rs`
    line 64).
  - XML is parsed with `roxmltree` and `allow_dtd: true` (`parser/mod.rs` line 161).
  - The search found no limit on nesting depth, `<use>` expansion count, text length,
    stylesheet size, geometry or raster memory.
- **Panic behavior**: no `catch_unwind` in `crates/c-api/lib.rs` (also none at v0.45.1).
  The C functions are `extern "C"` and use `assert!` on null pointers and `.unwrap()`, for
  example `PixmapMut::from_bytes(...).unwrap()` in `resvg_render` (lib.rs line 890). Since
  Rust 1.81, "the non-unwind ABIs (e.g., "C") will now abort on uncaught unwinds"
  ([Rust 1.81.0 announcement](https://blog.rust-lang.org/2024/09/05/Rust-1.81.0/), read
  2026-10-22), so a panic inside these functions ends the process unless the caller's build
  adds a catch.

## Gaps against the contract

Stated per project, with the source for each. "Not found" means not found in the files read.

### swift-resvg

- Platforms: macOS 12 only in both manifests; no iOS device or simulator slices in the bundle
  metadata or XCFramework script (Package.swift; info.json; build-xcframework.sh).
- Supplied resources: the wrapper sets no options, and the bundled C API exposes no image href
  resolver, so `<image>` uses usvg's default string resolver, which reads file paths when they
  exist, and the default data resolver, which accepts nested `image/svg+xml`
  (SvgRasterizer.swift line 46; resvg.h; usvg image.rs lines 58-110). The `rasterize(file:)`
  and `SvgTree(file:)` entry points read files by design.
- Fonts: no font interface; text renders only with fonts the C API database contains, which is
  empty by default (resvg c-api lib.rs line 113). No color-table handling.
- Budgets: only upstream's 1,000,000-element limit; raster allocation follows declared size
  times scale with no cap (SvgRasterizer.swift lines 82-90).
- Failure: no `catch_unwind` in the appended patch or upstream 0.45.1 C API; releases are built
  with the stable Rust toolchain (release.yml lines 33, 108), where a panic across `extern "C"`
  aborts.
- API: RGBA byte array or tree traversal; no `CGImage` or target-size drawing. `SvgTree` is
  `@unchecked Sendable` (SvgTree.swift line 26).
- Version: resvg 0.45.1, against 0.48.1 upstream.

### SwiftDraw

- Engine and coverage: own parser and CoreGraphics renderer, not resvg. No marker support
  found; filters limited to `feGaussianBlur`; text is one string per `<text>` from the first
  `<tspan>` (Parser.XML.Filter.swift line 66; Parser.XML.Text.swift lines 36-43).
- Supplied resources: closest of the four. Sub-resources other than `data:` are not loaded,
  and `<image>` accepts only png/jpeg (LayerTree.Image.swift lines 55-57), so gif and webp
  images would not render. There is no host interface to supply image bytes by reference.
- Fonts: names resolve through `CTFontCreateWithName` against installed fonts, with Times as
  fallback; no host-supplied font set (Renderer.CoreGraphics.swift lines 226-245).
- Budgets: none documented; `<use>` expansion has no cycle check found in the files read, and
  an open unmerged PR (#142) proposes "reference cycles never crash".
- Failure: Swift code with no panic boundary; failures return `nil`. Crash reports exist in
  closed issues (#72, #64).
- API: meets most of it: `Sendable` value type, `CGContext.draw`. Rasterizing with the default
  scale off the main thread synchronously hops to the main queue (UIImage+SVG.swift
  lines 126-153).

### SVGKit

- Release: last tagged release 3.0.0, 2021-04-15; the manifest's newest version (3.1.1) has no
  tag.
- Supplied resources: fetches `http(s):` image hrefs synchronously, resolves relative hrefs
  against the source file or URL, and decodes non-image bytes as embedded SVG; no documented
  hook to refuse them (SVGImageElement.m lines 73-124).
- Coverage: patterns unsupported by assertion; no `mask`, `marker` or `filter` parsers found
  (SVGKParserPatternsAndGradients.m line 44; SVGKParserSVG.m lines 36-51).
- Fonts: installed font families only (SVGTextElement.m lines 359-420).
- Budgets: none documented; no `<use>` cycle check found.
- Failure: assertion-based checks in source (disabled in SPM release builds by
  `NS_BLOCK_ASSERTIONS`); open crash reports (#839, #641).
- API and threading: mutable `NSObject` and `CALayer` tree; threading not documented. Adds a
  CocoaLumberjack dependency.

### SVGView

- Release: newest tag 1.0.6, 2023-08-30; sources unchanged since.
- Coverage: its own report gives SVG 1.1 coverage of 19.3%, with Text, Fonts and Filters at
  0.0% and Masking at 5.2% (w3c-coverage.md); the parser table has no `mask`, `marker`,
  `pattern` or `filter` entries (SVGParser.swift lines 54-65).
- Supplied resources: parsing from `Data` loads nothing by default (`SVGLinker.none`), but the
  linker cannot be subclassed from outside the module (`public class`, not `open`), so a host
  cannot supply bytes through it; parsing from a file URL reads relative hrefs from disk with
  `appendingPathComponent` (SVGLinker.swift lines 10-38). `data:` images limited to png, `jpg`
  and svg+xml prefixes (SVGImageParser.swift line 19).
- Fonts: `Font.custom(name:)` only (SVGFont.swift line 16).
- Budgets: none documented beyond the `<use>` recursion check (SVGContext.swift lines 77-86).
- Failure: open crash and hang reports (#67, #81, #82).
- API and threading: SwiftUI views over mutable `@Published` classes; no `CGImage` output;
  threading not documented.

## Not checked

- Rendering parity or correctness against any test suite; nothing was built or run.
- Whether swift-resvg's binaries contain iOS slices beyond what the manifests, `info.json` and
  scripts say (the zips were not downloaded).
- Upstream resvg 0.45.1 sources other than the C API's `lib.rs` (`catch_unwind` search); the
  usvg facts above are for 0.48.1.
- `roxmltree`'s own defaults (for example any node or entity limits) and `fontdb`'s loading
  behavior beyond the usvg and C API comments quoted.
- Foundation `XMLParser` external-entity behavior as used by SwiftDraw and SVGView (neither
  file read sets `shouldResolveExternalEntities`); libxml2 defaults as used by SVGKit.
- Rust toolchain version actually used to build swift-resvg release binaries (the workflow
  names `@stable`).
- Issue trackers beyond the keyword searches cited; closed issues for SVGKit and SVGView;
  SwiftDraw's `main` changes after 0.29.0 beyond the commit list.
- Font color-table handling (`COLR`, `CBDT`, `sbix`, `SVG `) in any of the four projects.
- Other Swift SVG packages not named in the brief.
