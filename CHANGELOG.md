# Release notes

## Unreleased

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
