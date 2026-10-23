# Release notes

## Unreleased

- An `href` or `src` whose `#` a combining mark follows is kept as the fragment the renderer
  reads, where the serializer took it for a file, dropped it and reported an image
  ([vocaro/EPUBLib#641](https://github.com/vocaro/EPUBLib/issues/641)).

## 0.1.1 — 2026-10-22

The renderer EPUBLib moved to after 0.1.0 was cut, as a release of its own: resvg reads no file
and is built without backtraces, so an app that links it has no required-reason API to declare for it
in its privacy manifest ([vocaro/EPUBLib#685](https://github.com/vocaro/EPUBLib/issues/685),
[vocaro/EPUBLib#728](https://github.com/vocaro/EPUBLib/pull/728)). 0.1.0's library imports
`stat` and `fstat`.

- `resvg_parse_tree_from_file` opens no file, and usvg's default image resolver, which
  `Options::default()` builds before the resource policy replaces it, reads no path.
- The standard library is built from Rust 1.95.0's own source without its `backtrace` feature;
  the framework is 19 MiB, from 45. Library checksums are in
  [Resvg/checksums.json](Resvg/checksums.json).
- `scripts/verify-resvg.py` reads each slice for an API Apple requires a reason for.

## 0.1.0 — 2026-10-21

The first release: EPUBLib's static SVG pipeline as a package of its own
([vocaro/EPUBLib#636](https://github.com/vocaro/EPUBLib/issues/636)). The screens, serializer,
image and font preparation, budgets and renderer are those EPUBLib shipped at
[`e50f6a6`](https://github.com/vocaro/EPUBLib/commit/e50f6a6), and the renderer binary is the
one it vendored, unchanged: resvg 0.48.1 with its resource, panic-boundary and tiny-skia
patches, built with Rust 1.95.0. Library checksums are in
[Resvg/checksums.json](Resvg/checksums.json).

- `SVGDocument` parses UTF-8 XML with bounded size, depth and nodes, refusing entity
  declarations and internal DTD subsets, or is built from a host's own tree.
- `SVGDocument.serialized` sanitizes a drawing and inlines its images through a host's
  `SVGResourceProvider`, within shared work budgets (`SVGImagePreparation`), and reports what it
  left out (`SVGDiagnostics`).
- `SVGRenderer` screens the exact bytes it is given and draws them into a `CGImage`, with
  host-supplied fonts (`SVGFontData`).
