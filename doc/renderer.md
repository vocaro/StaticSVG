# The bundled renderer

StaticSVG draws with resvg 0.48.1, MIT/Apache-2.0, from upstream commit
[`68b14c4c3bccdb60344c777406486b54c36ec1a4`](https://github.com/linebender/resvg/tree/68b14c4c3bccdb60344c777406486b54c36ec1a4).
The source tarball SHA-256 is
`fda0203e2dc383ea334c2d95a9af83526d32647e63d8dee43c2875e95c641c0c`.

`Resvg.xcframework` contains static macOS arm64/x86_64, iOS arm64, and iOS simulator
arm64/x86_64 libraries, built with isolated Rust 1.95.0 and the upstream production profile
(`opt-level=3`, LTO, one codegen unit, stripped debug information), with `panic = "unwind"`
explicitly set so boundary catches can run. Rust's standard library is built with it from the
toolchain's own 1.95.0 source (`-Zbuild-std`, which `RUSTC_BOOTSTRAP=1` enables on the stable
compiler) without its `backtrace` feature, whose symbolizer reads the executable with `fstat`.
Apple counts that, and the `stat` and `fstat` of a file read, as file timestamp APIs an app has
to declare in its privacy manifest; the library calls none of the APIs Apple requires a reason
for ([EPUBLib#685](https://github.com/vocaro/EPUBLib/issues/685)), and
`scripts/verify-resvg.py` reads each slice for one. Features: `text,raster-images`; filesystem
font scanning, font memory mapping and SVGZ are disabled. A release distributes the framework as its
`Resvg.xcframework.zip` asset, which `Package.swift` pins by checksum, so a consumer needs no
Rust. Only the `StaticSVG` target links the `CResvg` module it provides. The library's build
deployment targets are macOS 11.0 and iOS 10.0 (Rust's Apple defaults); StaticSVG itself
requires iOS and macOS 27. [Maintenance](maintenance.md) says how to rebuild and verify it.

## Patches

The resource-policy changes, in `scripts/patch-resvg.py`, close every non-data image resolver,
usvg's default one too, which `Options::default()` builds before the policy replaces it, make
`resvg_parse_tree_from_file` open no file, allow raster data types only (PNG, JPEG, GIF and WebP, never nested SVG or SVGZ), and fix the C
API's feature gates so the filesystem font methods compile to no-ops. Fonts are supplied as
host-exported CoreText SFNT outline bytes (`SVGFontData.export`), with SVG, COLR, bitmap and other
color-glyph tables removed; `SVGFontData.strippedColorGlyphs` and `SVGDiagnostics.Kind.colorGlyphs`
let a host disclose that. No script or remote or file resource loader is installed.

`scripts/resvg-panic-boundary.py` and its Rust helper wrap both parse entry points, all tree
queries and the render entry points in `catch_unwind`, using Rust-ABI inner functions: an inner
`extern "C"` would abort before the catch. A tree's opaque handle owns a mutex-protected optional
tree. Calls on one tree serialize; after a caught panic its state is dropped while that lock is
still held, and every later query or draw fails. Separate trees can still render concurrently.
The upstream void `resvg_render` remains available; `SVGRenderer` calls the added boolean
`resvg_render_checked` so it can tell a failure from a transparent image.

The pinned tiny-skia 0.12.0 dependency also has one cleanup guard: its antialias
`SuperBlitter` drops an interrupted row without flushing it while the thread is unwinding.
Otherwise its `Drop` can panic a second time on that inconsistent row and abort before the
boundary catch runs. Normal drop still flushes the final row. The build downloads the crate
archive with its Cargo.lock SHA-256 and uses an isolated path patch; it never modifies Cargo's
registry cache.

The default Rust panic hook is deliberately unchanged: caught panic diagnostics still go to
stderr, with no backtrace, which the standard library is built without. There is no process-global hook replacement that could silence a host's own Rust panics.
StaticSVG never invokes `resvg_init_log`.

## What is screened before the renderer runs

Filter effects are omitted from a serialized drawing with a disclosure; the rest of the drawing
is kept. `SVGRenderer` itself refuses a drawing with a filter, since the bytes it is given have
not been through that omission. Pattern fills are refused, with the drawing's fallback text and a
disclosure. The screens bound SVG bytes, depth, nodes, `<use>` expansion, single text-run length
and total expanded text, stylesheet selector and declaration work and copies, repeated mask and
clip-path content, marker instances, reference loops and chains, the per-shape copies of gradient
stops, dash arrays, long inherited values and the font-variation-settings a text run copies per
span, image bytes and pixels, and output and isolated-layer raster memory, before rendering
([limits](design.md#limits)). Font databases share immutable options and retain a process-wide
64 MiB byte reservation (`SVGRenderer.maximumFontBytes`) for their full lifetime, including
trees remaining after cache eviction. A database a tree still holds is shared by later drawings
naming the same fonts, never duplicated.

The renderer follows a `mask`, a `clip-path`, a marker and a `use` by calling itself, and a
gradient's `href` in a loop. It stops a loop of one or two masks or clip paths
(`fix_recursive_links` in `usvg/parser/svgtree/parse.rs`), a marker it is already drawing
(`usvg/parser/marker.rs`) and an `href` walk that is back where it began (`HrefIter` in
`usvg/parser/svgtree/mod.rs`), and nothing else: a longer loop or a deep chain spends the stack,
and a walk into a loop it did not begin in never returns. Neither is a panic.
`SVGReferenceScreen.swift` refuses those drawings first. It reads a `url(#…)` as svgtypes 0.16.1
does (`funciri.rs`), a stylesheet and a `style` attribute as simplecss 0.2.2 does, step for step,
and takes the elements that are drawn where they stand from `convert_element` in
`usvg/parser/converter.rs`. Repeating and reflecting gradients are resolved by the renderer
itself. Review the remaining loop and depth screens against those sources whenever the renderer
is updated ([maintenance](maintenance.md#when-resvg-changes)).

## Failures found after construction

`SVGRenderer` draws a 64-pixel raster when it is created, so a known render-stage panic, as
well as a parse panic, refuses the drawing there, where a host can still show its fallback text
and disclose it. That small raster is not a proof about other sizes. Every later draw is
independently guarded: a draw that fails returns nil, `hasFailedRendering` becomes true, and every
later draw of that renderer returns nil too, sizes that succeeded before included. EPUBLib, for
one, then paints the drawing's alternative text where it stood.

Unwinding does not contain stack overflow, allocation failure, memory or CPU exhaustion, or a
parser loop that never returns; their screens and budgets stay. The image output size bound is a
capacity bound, not a prediction of panics. None of this is an operating-system sandbox.

## Notices

The XCFramework is about 19 MiB before compression; it was 45 MiB, in 0.1.0, before the
standard library was built with the production profile and without backtraces. `Resvg/checksums.json` records the library
hashes, `Resvg/dependencies.json` identifies the locked normal dependency graph, and
`Resvg/Licenses/` contains their complete license and notice texts, plus Rust's standard-library
copyright and third-party notices. An application redistributing this static code must retain
these notices ([third-party notices](../THIRD_PARTY_NOTICES.md)).

[Documentation index](../README.md#documentation)
