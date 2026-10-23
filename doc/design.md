# Design

StaticSVG draws static SVG that nobody vetted — a drawing in a book, a document or a message —
into a `CGImage` on iOS and macOS. It hands the drawing to [resvg](https://github.com/linebender/resvg),
a mature Rust renderer, and adds what that alone does not give a host that cannot trust its
input. This document says what that is, why resvg used directly and the Swift SVG packages
reviewed do not provide it, and where the package's guarantees end.

## Why a wrapper

resvg does the drawing: parsing, CSS, text layout and shaping, paths, gradients, masks,
clipping, markers and raster images. StaticSVG adds:

- **Controlled resource access.** The renderer opens no file and fetches no URL. Every image a
  drawing uses is read through a host's `SVGResourceProvider`, decoded within byte and pixel
  budgets, and inlined into the drawing as PNG before the renderer sees it; the renderer itself
  accepts only those `data:` rasters. A host decides what a reference names, which fallbacks to
  try and how its own SVG files are parsed.
- **Bounded processing of untrusted SVG.** Before the renderer runs, the exact bytes it will
  read are parsed and screened against bounds on size, depth and nodes, `<use>` expansion, text,
  stylesheet work, reference loops and chains, geometry, raster memory, markers and the copies
  the renderer makes per shape ([limits](#limits)). A drawing outside them is refused, not
  drawn slowly or until memory runs out.
- **Font preparation and accounting.** Fonts are given to the renderer as SFNT bytes exported
  from CoreText (`SVGFontData.export`), WOFF and WOFF2 faces included, with color glyph tables
  removed. Font databases are shared between drawings that name the same faces and are held to
  one process-wide byte reservation for as long as any drawing uses them.
- **Recoverable failure.** A renderer panic is caught at the C boundary and becomes a refusal
  or a failed draw, with the drawing's own title and description or its text as fallback words,
  instead of ending the process.
- **Diagnostics.** What was left out (scripts, foreign content, animation, filter effects), refused
  (pattern fills, stylesheets reaching outside the drawing) or could not be inlined is counted
  by kind (`SVGDiagnostics`), so a host can tell its reader.
- **Apple packaging.** A static XCFramework for macOS, iOS and the iOS simulator, built
  reproducibly from pinned sources, distributed as a release asset with its notices, behind a
  small Swift API. Consumers need no Rust.

## Why resvg alone does not meet this contract

What follows distinguishes what upstream resvg 0.48.1 provides, what StaticSVG adds as policy,
and what it patches to work around that version. Upstream facts were read at
[`68b14c4`](https://github.com/linebender/resvg/tree/68b14c4c3bccdb60344c777406486b54c36ec1a4)
on 2026-10-22; the [comparison notes](research/alternatives-2026-10-21.md#upstream-resvg--usvg-048x)
cite the lines.

### What upstream provides

- **Resource hooks in Rust.** `usvg::Options` has an `image_href_resolver` with separate
  resolvers for `data:` URLs and other strings, and a `font_resolver` and `fontdb`. Its
  documentation says the hook can "forbid access to local files (which is allowed by default)",
  and that usvg makes no network requests.
- **A node limit and some loop checks.** A document of more than 1,000,000 nodes is refused.
  Recursive `<use>` is skipped; a mask or clip path that leads back to itself directly or
  through one other is unlinked; a marker already being drawn is skipped; a gradient `href` walk
  that returns to where it began stops.
- **An empty font database by default** in the C API, and no system fonts unless asked.

### What it does not, and what StaticSVG does about it

| Need | Upstream 0.48.1 | StaticSVG |
|---|---|---|
| Refuse file reads for `<image>` | Rust hook exists; the C API exposes none, and its default string resolver reads files | Patch: the C API's options close the string resolver, usvg's default one included, and allow PNG, JPEG, GIF and WebP `data:` only, never nested SVG; `resvg_parse_tree_from_file` opens no file (`scripts/patch-resvg.py`) |
| Nothing an app must declare | The standard library's backtrace symbolizer and file reads call `fstat` and `stat`, file timestamp APIs an app declares in its privacy manifest | Build: the standard library is built without backtraces, and no file is read ([EPUBLib#685](https://github.com/vocaro/EPUBLib/issues/685)); `scripts/verify-resvg.py` checks each slice |
| Supply image bytes | Not through the C API | Policy: images are prepared in Swift through `SVGResourceProvider` and inlined as PNG |
| No filesystem font methods | The C API gates them on `text` instead of `system-fonts` | Patch: gate on `system-fonts`, which the build leaves off |
| Survive a panic | No `catch_unwind`; since Rust 1.81 a panic leaving an `extern "C"` function aborts the process | Patch: every parse, query and render entry point catches unwinds, and a tree that panicked is disposed of ([renderer](renderer.md#patches)); tiny-skia's antialias `Drop` is guarded so unwinding cannot panic twice |
| Tell a failed draw from a transparent one | `resvg_render` returns nothing | Patch: `resvg_render_checked` returns false after a caught panic |
| Longer reference loops and deep chains | Only one- and two-element mask and clip-path loops, marker re-entry and a gradient walk back to its start are stopped; a longer loop or deep chain spends the stack, and a walk into a loop it did not begin in never returns ([EPUBLib#229](https://github.com/vocaro/EPUBLib/issues/229)) | Policy: `SVGReferenceScreen` refuses them, reading references as svgtypes and simplecss do |
| Bounded work | The node limit only: no bound on depth, `<use>` expansion, text, stylesheet work, geometry or raster memory | Policy: the screens and budgets in [limits](#limits), each set from measurement and recorded on its issue ([#170](https://github.com/vocaro/EPUBLib/issues/170), [#176](https://github.com/vocaro/EPUBLib/issues/176), [#220](https://github.com/vocaro/EPUBLib/issues/220), [#230](https://github.com/vocaro/EPUBLib/issues/230), [#251](https://github.com/vocaro/EPUBLib/issues/251), [#252](https://github.com/vocaro/EPUBLib/issues/252), [#282](https://github.com/vocaro/EPUBLib/issues/282), [#375](https://github.com/vocaro/EPUBLib/issues/375), [#443](https://github.com/vocaro/EPUBLib/issues/443), [#541](https://github.com/vocaro/EPUBLib/issues/541)) |
| Known panics before a size is drawn | An image box or a zero-length gradient can panic the renderer ([#186](https://github.com/vocaro/EPUBLib/issues/186), [#229](https://github.com/vocaro/EPUBLib/issues/229)) | Policy: `SVGRenderer` draws 64 pixels when it is created, so such a drawing is refused while a host can still show its fallback |
| Hostile markup | roxmltree reads internal DTD entities | Policy: entity declarations and internal DTD subsets are refused before parsing, and the bytes must read the same as UTF-8 |
| Fonts from the platform | Faces are loaded from files or bytes | Policy: CoreText faces exported as SFNT with color tables removed, shared and accounted |
| Filter effects and patterns | Drawn | Policy: filter effects are omitted with a disclosure; pattern fills refuse the drawing ([#53](https://github.com/vocaro/EPUBLib/issues/53), [#253](https://github.com/vocaro/EPUBLib/issues/253)) |

The policy rows are StaticSVG's choices for untrusted input, not upstream defects. The patch
rows are workarounds for the pinned version: [maintenance](maintenance.md#retiring-a-patch-or-a-screen)
says when each can go. Each screen names the upstream function it follows, and its tests hold
the bound at its edge and just past it; the tests carry the history of each bound in their
links to EPUBLib, where the work was done.

## Why an existing package was not adopted

Four Swift SVG packages were compared against this contract from their sources and
documentation in October 2026: [swift-resvg](https://github.com/alexey1312/swift-resvg),
[SwiftDraw](https://github.com/swhitty/SwiftDraw), [SVGKit](https://github.com/SVGKit/SVGKit)
and [SVGView](https://github.com/exyte/SVGView). The [comparison notes](research/alternatives-2026-10-21.md)
have every fact with its pinned source and the date it was read. This was not a rendering-parity
test or a security audit: where a project does not document a guarantee, that is all that is
said of it.

| | swift-resvg | SwiftDraw | SVGKit | SVGView |
|---|---|---|---|---|
| Version read | `v0.45.1-swift.15`, 2026-02-23 | 0.29.0, 2026-07-19 | 3.0.0, 2021-04-15 | 1.0.6, 2023-08-30 |
| Engine | resvg 0.45.1 | Own parser, CoreGraphics | Objective-C, CoreAnimation layers | Own parser, SwiftUI |
| iOS device and simulator | No iOS slice in its manifests or build scripts | Yes | Yes | Yes |
| Host-supplied images | No: upstream defaults, which read existing file paths and parse nested SVG | `data:` PNG and JPEG only; no way to supply bytes by reference | Fetches `http(s):` synchronously and resolves relative paths against its source; no documented hook to refuse | Loader cannot be subclassed outside the module; reads relative paths from disk when parsing a file URL |
| Supplied fonts | None loaded; no font API | Installed fonts, or `@font-face` `data:` URLs | Installed families | `Font.custom(name:)` |
| Documented processing bounds | Upstream's node limit | None found | None found | None found beyond a `<use>` recursion check |
| Panics and crashes | No `catch_unwind` | Failable initializers; no cycle check found for `<use>` | Assertions; open crash reports | Open crash and hang reports |
| Output | RGBA bytes | `CGContext` drawing, images | `UIImage`, `CALayer` tree | SwiftUI views |
| Coverage gaps for books | None beyond upstream's | No markers; `feGaussianBlur` only; one string per `<text>` | No masks, markers, filters or patterns found | Its own report: 19.3% of SVG 1.1, text and fonts 0% |

- **swift-resvg** is closest in engine: it wraps resvg as a binary target and needs no Rust.
  Adopting it would still mean adding iOS slices, replacing its C API to reach the resolver
  hooks, adding fonts, budgets and a panic boundary, and updating from 0.45.1 — the whole of
  this package, against someone else's build.
- **SwiftDraw** is the closest in API: a `Sendable` value drawn into any `CGContext`, and
  sub-resources other than `data:` are never loaded. But it is a different renderer, without
  markers, with one filter and simplified text, which the diagrams in books depend on; it has
  no documented bounds, and GIF and WebP images would not draw.
- **SVGKit** loads remote and relative resources itself, has not tagged a release since 2021,
  and lacks masks, markers, filters and patterns.
- **SVGView** renders a fifth of SVG 1.1 by its own count, with no text, into SwiftUI views
  rather than images.

Each could change; the notes say what to look at again.

## Scope and limitations

### What is drawn

Static SVG as resvg 0.48.1 draws it: shapes and paths, text with supplied fonts, CSS
stylesheets and `style` attributes, gradients, masks, clip paths, markers, `<use>`, nested
viewports and raster images. Not drawn:

- Scripts, `foreignObject`, `iframe`, `video`, `audio`, event handlers and listeners, and
  animation elements: removed by serialization and counted (`SVGDiagnostics.Kind`). Event
  attributes, `xml:base` and namespace declarations are dropped too.
- Filter effects: removed, the rest of the drawing kept, and counted as `.filter`. `SVGRenderer`
  given raw bytes with a filter refuses them; only a serialized drawing has had them removed.
- Pattern fills: the drawing is refused and counted as `.pattern`.
- A stylesheet with an `@import`, a `url()` that leaves the drawing or any escape, and an
  attribute whose CSS could reach outside: removed and counted.
- `<tref>`, which SVG 2 removed: the drawing is refused.
- An SVG image nested in a drawing is drawn by StaticSVG first, at most 2,048 pixels on its long
  side, and inlined as PNG; the renderer never reads nested SVG. An `<image>` that gives neither
  `width` nor `height` is given the nested drawing's own size, as a browser lays it out, not the
  raster's. SVGZ is not read.
- Text needs a font: the renderer exports Times New Roman, Arial and Courier New from the
  system for the default, serif, sans-serif and monospace families, and uses the faces a host
  gives `SVGRenderer` by family name. A nested SVG image draws with the defaults only.

### Fallback

Where a drawing is refused or a draw fails, a host shows `fallbackText`: the drawing's own
`<title>` and `<desc>`, else the words of its `<text>`, else "Illustration unavailable".
`accessibleLabel` gives the title and description alone, for assistive technology.

### Limits

The bounds a drawing is screened against. They are fixed; `SVGImagePreparation.Limits` alone
can be set by a host.

| Bound | Value | Where |
|---|---|---|
| Serialized drawing bytes | 4 MiB | `SVGLimits.renderer`, `SVGContent.maximumBytes` |
| Nesting depth, nodes | 64, 10,000 | `SVGLimits.renderer` |
| Attributes in one tag | 1,024 | `SVGMarkupSafety` |
| `<use>` expansion | 8 MiB, at 32 bytes or more an element | `maximumExpandedBytes` |
| Characters in one text run; in all text through `<use>` | 20,000; 50,000 | `maximumTextRunCharacters`, `SVGRenderingCostScreen` |
| A `font-size` value | 64 bytes | `maximumFontSizeValueBytes` |
| Stylesheet matching work; selectors; declarations copied onto elements | 32 Mi steps; 10,000; 16 Mi | `SVGRenderingCostScreen` |
| Marker instances | 100,000 | `maximumMarkerInstances` |
| Per-shape copies of stops, dashes and inherited values | 8 Mi | `maximumSharedCopies` |
| Reference loops and chains | Loops longer than upstream stops, and chains past the depth bound, are refused | `SVGReferenceScreen` |
| Path coordinates; image span | 10,000,000; 8 canvases | `SVGGeometryCostScreen` |
| Marker overshoot and layer area | 8 viewports; 256 canvases | `SVGRasterCostScreen` |
| Inlined image bytes; pixels per image; pixels in all | 8 MiB; 4 Mi; 16 Mi | `SVGContent` |
| Image work per serialization | 128 visits, 16 MiB read, 16 MiB written, 64 Mi pixels, 8 MiB cached | `SVGImagePreparation.Limits` |
| Raster | 4,096 pixels on the long side, and 16 Mi pixels, or fewer with isolated layers so their memory stays under 96 MiB | `SVGRenderer` |
| Fonts | 8 MiB a face; 64 MiB for all live databases | `SVGFontData.maximumBytes`, `SVGRenderer.maximumFontBytes` |

A refusal is `nil` from `SVGRenderer` and `serialized().data`; the public API does not say which
bound refused a drawing. What serialization removed or could not inline is in
`SVGSerialization.diagnostics`, whether or not a drawing results.

### Cancellation, concurrency and lifetime

- `SVGNode` and `SVGDocument` are immutable once built and can be read from any thread.
- One serialization runs on its caller's thread and calls the host's provider there, one call
  at a time. An `SVGImagePreparation` is shared by the drawings nested in one serialization and
  is not thread-safe; its `cancelled` closure, `Task.isCancelled` by default, is asked before
  each costly phase, and once it is true the serialization gives no drawing.
- An `SVGRenderer` holds one parsed tree. Its draws are serialized; separate renderers draw
  concurrently. A draw that fails leaves the renderer failed for good. The tree, and the font
  database it shares, live as long as the renderer.

### Platforms

iOS and iPadOS 27 on device (arm64) and simulator (arm64, x86_64), and macOS 27 (arm64,
x86_64), with Swift 6.2 and Xcode 27.

### What catching panics does not do

Catching a panic contains only a panic. It does not contain a stack overflow, an allocation
failure, exhaustion of memory or CPU, or a loop that never returns; that is what the screens and
budgets are for, and a drawing they do not anticipate can still cost what they do not bound.
StaticSVG runs the renderer in the host's own process. It is not an operating-system sandbox,
and nothing here is a guarantee that every hostile drawing is refused.

[Documentation index](../README.md#documentation)
