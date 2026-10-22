# The screens

What each screen bounds, how it reads the drawing as the renderer does, and the sources it
follows. This was written for [EPUBLib](https://github.com/vocaro/EPUBLib), where the screens
were built, and moved here with them; where it says a drawing "shows its fallback text with the
`svg` disclosure", that is what EPUBLib shows for a drawing StaticSVG refuses. Here a refusal
is `nil` from `SVGRenderer` or `SVGDocument.serialized`, and `fallbackText` is what to show in
its place. The bounds are summarized in [design](design.md#limits).

A drawing is static: filter effects are omitted with a disclosure, preserving the remaining diagram;
pattern fills, animation and foreign content are unsupported. Rendering limits
include 4 MiB of SVG, 10,000 nodes, depth 64 and 8 MiB of expanded local references.
Amplifications the byte and node limits do not catch are bounded too, and an SVG past
any shows its fallback text with the `svg` disclosure, as one past the node, depth or
byte limits does. One `<text>` run, whose layout is super-linear in its length, is held to
20,000 Unicode scalar values. The sum across the drawing is held to 50,000, counting text
again wherever a `<use>` or a mask/clip reference expands it. This counts Rust's
`str::chars` units, including each combining scalar, rather than UTF-8 bytes or grapheme
clusters. An SVG that holds a `<tref>`, which SVG 2 removed and which draws
text from elsewhere in the document into a run, is refused. Markers, whose content the
renderer builds again at every vertex they are drawn at, are counted in the forms diagrams
use and refused in any other, rather than modelled.
- Supported: `marker-start`, `marker-mid` and `marker-end` as attributes, or those and
  `marker` in a `style` attribute, on a shape or on a group around it, a `<use>` of it
  included; and a `<marker>` that holds only `path`, `line`, `polyline`, `polygon`, `rect`,
  `circle` and `ellipse`, with `<g>`, `<title>` and `<desc>`, painted with colors,
  `currentColor`, `context-fill` or `context-stroke`. That is how Inkscape, Mermaid, D3 and
  OmniGraffle write arrowheads and data points.
- Counted: each time a marker is drawn, one for each element in it, and one more for every
  64 bytes of attributes an element has or inherits; a `marker-mid` is drawn at every
  vertex, a vertex being a number in the path data or points. A dash array of 64 bytes or
  more on the shape that bears the marker, and a stylesheet declaration as long, add to each.
  A drawing tool's arrowhead counts ten to twenty with its attributes. An SVG may reach
  100,000: some thousands of arrowheads, or of data points on a line.
- Refused: a `<style>` sheet that holds a `url(#…)` in an SVG that has a `<marker>`, so a
  marker given by a class (`.edge { marker-end: url(#arrow) }`) is to be given by attribute
  instead; a marker property, or a `fill` or `stroke` that names a gradient, on a
  `<marker>` or on an element that contains one; a `url(…)`, an `href` or a `filter` inside
  a `<marker>`, and any other element there, such as `<use>`, `<image>`, `<text>` or a
  nested `<svg>`; a shape that bears a marker inside a `<mask>`; `marker-mid` on a path
  with an elliptical arc, or on a `circle`, `ellipse` or rounded `rect` whose radius is not
  a plain number, and either of those inside a `<marker>`; and a marker that uses
  `context-fill` or `context-stroke` on a shape whose own fill or stroke is a gradient.

The renderer draws no marker on a shape inside a `<clipPath>`, so none is counted there.

References between a drawing's elements are held to what the renderer can follow, and an
SVG past any of these shows its fallback text with the `svg` disclosure too. The renderer
follows a `mask`, a `clip-path` and a `<use>` by calling itself, on a stack whose end is
the end of the process, and it guards against loops only in part. So references count
toward the depth limit: a chain of nesting, `<use>`, `mask` and `clip-path` may be 64
levels deep in all, a mask or clip path one level and its content the next, which lets 31
masks in a chain through their content draw and refuses 32. More than two masks or clip
paths that lead back to each other are refused: the renderer unlinks a loop of one and of
two, which still draw, and misses a longer one. A gradient whose `href` leads into a loop
of two or more gradients that it is not one of is refused, since the renderer would walk
that loop for ever; a loop that nothing outside it leads into, and a gradient that names
itself, end and still draw. A linear gradient whose `spreadMethod` is `reflect` or
`repeat` is refused as well, whether it states the spread or takes it through `href` from
another gradient, linear or radial. The renderer panics on such a gradient that has no
length, when the average of its stops rounds past one, and telling which gradients have no
length would mean reproducing the renderer's resolution of lengths: units, percentages,
coordinates taken through `href`. So the spread alone decides. A linear gradient that
repeats or reflects shows fallback text at any length, painted or not, and so does one
whose `href` can reach a gradient that does, even past one that pads. A linear gradient
that pads, or whose `spreadMethod` is absent or not a value the renderer knows, still
draws, and so does a radial gradient of any spread. A reference is found wherever the
renderer takes one from: an attribute, a `style` attribute, a rule of a stylesheet in the
drawing, read as the renderer's own CSS parser reads it, or `inherit`, behind a marker
included. More is assumed than the renderer follows where telling the two apart would
mean doing its work: a rule is taken to apply to every element its last compound selector
could match, a declaration counts even where another overrides it, and an `id` that
several elements share names them all.

The renderer also copies or re-reads some shared and inherited values once per painted shape,
which neither the byte nor the node limit catches, so a file of a few hundred kilobytes can make
it allocate hundreds of megabytes or parse for most of a minute. Each is charged per shape, against
a ceiling set from measurement (the worst passing drawing costs the renderer on the order of what
the other limits allow); each shape is charged the most that it or any ancestor, through every
`<use>` that draws it, could ask for, so the count never falls below what the renderer does. A
stylesheet's declarations have a separate whole-document bound described below. The screen's own work is counted too, in
steps for the gradients it looks up, the elements it walks and the CSS it reads, and a drawing
that spends its budget of steps shows its fallback text with the same disclosure: that limits the
screen's own reading and not what the renderer does, and it does not bound all of the screen's
work either, since a visit to an element is one step though it goes over every child the element
has, and what bounds that is the limit on expanded local references. Nested `<style>` elements
are now refused by a structural walk before any CSS text is read, including font discovery and
disclosure, so stylesheet bytes are not read again for each level of nesting.
- A gradient's stops are copied into a fresh paint server for every shape it paints by `fill` or
  `stroke`, directly or inherited, in an attribute or a `style` declaration, through a gradient
  `href` chain, and through each `<use>`; each shape is charged the stops its fill names and those
  its stroke names. A gradient with no stops of its own is charged those its `href` chain leads to,
  however long the chain. Where the chain meets an `id` that several gradients share, the renderer
  takes the last element that has the `id`: it goes on from that one when it is a gradient, and
  paints nothing when it is not. Which is last is not worked out, and the gradient is charged the
  most stops any gradient in the drawing has. A stylesheet that paints with a gradient is taken to
  reach every shape.
- A stroke's dash array is stored for every stroked shape that has or inherits one; each shape is
  charged its dash-array bytes, an upper bound on its entries.
- Every `em` or `ex` length reparses ancestor font sizes, including each dash-array and text
  positioning entry. Font-size values are capped at 64 bytes in presentation attributes,
  inline styles, stylesheets and the size token of a `font` shorthand; ordinary long font
  families retain their existing copy budget. CSS padding is trimmed as the renderer trims
  it, while presentation-attribute padding counts toward this cap. This bounds the repeated
  value-length factor for stroke widths/offsets, spacing and text positioning as well as
  dash arrays ([#443](https://github.com/vocaro/EPUBLib/issues/443)).
- Each inherited presentation value the renderer re-parses for every shape — the `fill` and
  `stroke` paint, the numbers (`stroke-width`, the opacities, `stroke-miterlimit`, offsets) and the
  keyword enumerations alike — is charged its bytes over 64, summed down the inheritance chain. A
  `style` value is counted with its white space trimmed, as the renderer trims it before storing.
- Stylesheet matching and declarations are bounded before the renderer parses them, by
  `SVGRenderingCostScreen` using the reference screen's simplecss reader. The matching budget
  is 32 Mi units: selector UTF-8 bytes and attribute-lookup/value-scan cost per element, plus ancestor choices for each descendant
  combinator whose final compound could match, and each matched declaration's name/value bytes
  plus 64. The last term includes declarations the renderer drops: it still visits every
  declaration of a matched rule. For depth `d` and `k` descendant combinators the number of
  partial ancestor choices is bounded by the sum of binomial coefficients `C(d,j)` for
  `0 <= j <= k`. This refuses both a small selector that backtracks exponentially and many
  rules applied to many elements, including a long compound without combinators.
- Stylesheet storage has a 16 MiB budget: a declaration's value bytes plus 64 for its owned
  attribute/string storage on every element its rule could match, including groups and `<use>`
  copies. `marker` charges three attributes and `font` eighteen, their maximum shorthand
  expansions. Cloning a declaration block for each selector in a list also counts, for every
  property whether stored or dropped, with its name bytes too. A list past the budget is refused
  before constructing lists of referenced resources. The original per-shape longest-value charge
  remains to bound resolved text-span and inherited-value copies. At-rules such as `@font-face`
  are skipped as in simplecss, and stylesheets stripped by serialization are skipped here.
  A synthetic exporter-style drawing of fifty five-declaration class/descendant rules over
  3,000 shapes remains within every limit and renders.
- A `<text>` run clones its resolved style for every span (at most one span per character): the
  gradient stops its fill and stroke name, into the span and each of three text decorations; the
  dash array, into the span's stroke and, when the run is decorated, each decoration stroke; the
  font family; and the `font-variation-settings`, the worst per-span copy, a list held per span and
  again in the glyph cache. A long inherited value re-parses to a small resolved value the span
  clones cheaply, so it is not charged per character. A gradient with a handful of stops on
  thousands of shapes, dashed strokes on a large chart, a short variable-font axis list, and long
  but ordinary values (a path's `d`, a `points` list, a `transform`, an embedded `data:` image, a
  normal `font-family`) stay well within the ceiling. A `<switch>` draws one alternative but every
  one is charged, a sound over-charge. The rendering cost screen additionally charges a mask or
  clip path's content once per reference against the 8 MiB expanded-reference ceiling. It follows
  nested references and `<use>` without expanding a tree, so branching resource chains are
  bounded as well. The renderer shares user-space masks and clip paths only after successful
  conversion; an invalid resource is repeatedly retried. The screen conservatively charges
  every reference in every unit system, even where the renderer successfully shares it. This
  also bounds the drawing work of repeatedly using successfully cached content. A marker's
  content can inherit a mask/clip from the marker root: its external resource bytes, text and
  stylesheet costs, and resolved gradient/dash/text-span copies, additionally pay the total
  charged marker instances. That is an upper bound on each marker's actual draw count; plain
  marker content retains its existing instance bound.

These charges follow the vendored renderer's sources: resvg 0.48.1 at
`68b14c4c3bccdb60344c777406486b54c36ec1a4`, with simplecss 0.2.2. The following is from
those sources, not a reproduction of system code
([#176](https://github.com/vocaro/EPUBLib/issues/176), [#220](https://github.com/vocaro/EPUBLib/issues/220), [#282](https://github.com/vocaro/EPUBLib/issues/282)):
- `usvg/src/parser/text.rs` counts and iterates `str::chars()`; `text/layout.rs` tracks scalar
  offsets through shaping. Each run has its own shaping/layout, so a bound on one run cannot
  bound the sum of many runs. [The independent text-cost measurements](https://github.com/vocaro/EPUBLib/issues/176#issuecomment-6159294552)
  informed the global limit. The screen retains the
  20,000-per-run bound and adds 50,000 scalars across expanded content: around 2.5 maximal
  runs, leaving substantial room for diagram labels. It counts `<use>` copies and repeated
  resource content too. UTF-8 bytes and grapheme clusters are not the units Rust's text code
  counts.
- `simplecss/src/selector.rs`, `Selector::matches_impl`, tries each ancestor at each
  descendant combinator. An unsuccessful chain tries combinations of ancestors, including
  partial matches. The screen bounds those choices by `sum(C(depth,j), j=0...descendants)`,
  with saturation. `usvg/src/parser/svgtree/parse.rs` applies every rule to each element, and
  then iterates every declaration of a matched rule, even declarations it will drop. The work
  charge therefore includes selector bytes per element, matched ancestor-choice work, and all
  matched declarations, including unrecognized properties. Long compound selectors also pay
  their full byte length. Attribute lookup/value scanning is charged even on failed matches,
  using the largest source attribute count, query-name width and largest field queried by a
  selector. This bounds a long class list scanned once per rule and a missing field searched
  through many XML attributes, including ancestor candidates. Collection stops at 10,000
  selectors and at the cloned-block storage budget before rule-list materialization or
  selector/reference multiplication can grow beyond those ceilings.
- `write_declaration` / `insert_attribute` in that same usvg source allocates an owned value
  on every matching element. `marker` expands to three attributes, `font` to as many as
  eighteen. All presentation declarations are counted on shapes, groups, `<use>` and their
  copies, with value bytes plus 64 per declaration as an upper estimate of the measured
  small-value storage. simplecss also clones each declaration block for each selector in a
  list; the screen charges that product before allocating per-selector reference lists. Every
  property counts for the block-clone cost, including names usvg later drops. The ceilings are
  32 Mi work units and 16 MiB estimated stylesheet storage. Original XML counts are checked
  before reference lists are resolved, and reference lookups have their own bounded byte
  counter: each ID's bytes for a lookup and 32 bytes for each candidate element examined,
  even where its type is wrong.
- `usvg/src/parser/mask.rs` shares a converted mask only if both `maskUnits` and
  `maskContentUnits` are `userSpaceOnUse`. The defaults are respectively `objectBoundingBox`
  and `userSpaceOnUse`. `clippath.rs` shares `userSpaceOnUse` clip paths, the default;
  `objectBoundingBox` clip paths convert their content again for each referencing element.
  Both insert into the cache only after successful conversion of nonempty content. An empty
  resource, a primitive whose positive Double dimension rounds to zero in f32, or failed
  nested resources can therefore be retried on every reference even in user-space units. Two
  failed references per level make that retry exponential. The screen charges every mask and
  clip-path reference in every unit system against the existing 8 MiB expanded-byte ceiling,
  including nested references, rather than attempt a proof that conversion will succeed. This
  deliberately overcharges successfully cached content and also bounds the work of drawing it
  repeatedly.
- `paint_server.rs`, `convert_pattern`, converts children when constructing each pattern
  paint; `filter.rs`, `convert_url`, shares filters only when both filter and primitive units
  are `userSpaceOnUse`, and only after successful conversion. Pattern fills remain refused
  and filter effects remain omitted. Supporting them in future requires analogous
  content/primitive work budgets and render-time raster budgets; the present screen is not
  acceptance for those features.

A source node costs 32 bytes plus its text and attribute names/values, as in the existing
`<use>` expansion bound. Resource targets, child subtrees and use targets add their saturated
costs without constructing expanded XML. Short resource loops already unlinked by usvg do not
expand again; the existing reference screen still refuses the longer loops and excessive
chains it does not stop.

The resource-conversion measurements are on
[#176](https://github.com/vocaro/EPUBLib/issues/176#issuecomment-6159294552), and
[testing](testing.md#rendering-cost-probe) has their repeatable probe.

The preflight for [#230](https://github.com/vocaro/EPUBLib/issues/230),
[#251](https://github.com/vocaro/EPUBLib/issues/251), and
[#375](https://github.com/vocaro/EPUBLib/issues/375) checks hostile text without
handing it to resvg. The checked Rust boundary still handles renderer panics
([renderer containment](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/document-parsing.md#native-renderer-containment-needs-more-than-a-byte-limit));
these bounds stop inputs whose expensive work would not panic.

`SVGGeometryCostScreen` reads path numbers with SVG's scientific notation,
compact signs, and adjacent arc flags. It accumulates relative coordinates and
bounds endpoints and control points to 10 million units. An elliptical arc also
pays its corrected radius: even a small authored radius can become enormous
when the renderer enlarges it to connect its endpoints. The screen overestimates
the correction using the chord length and the smaller radius, bounds the result
to 10 million units, and sums the ellipse subdivision estimate over the path
against 10,000 units. The reported huge stroked arc and far-off text path are
refused before parse. The same rule applies to paths in definitions.

An embedded image's transformed span may reach eight root canvas dimensions.
The screen includes percentages, physical units, image font-relative lengths,
ancestor transforms, nested viewport and symbol scaling, and `<use>` viewport
overrides. The larger viewport scale is charged on both axes, covering `slice`.
Competing transforms are enclosed separately rather than multiplied, so an
overridden downscale cannot hide an upscale. Linked text paths additionally pay
their transformed coordinate bounds; links to other shape types are refused.
Stylesheet transforms, relative stylesheet font sizes and font shorthands are
refused for SVGs with images or text paths: their cascade is not reproduced. Absolute font size
candidates raise the size bound. Header dimensions stand in for omitted image dimensions.
This is separate from the decoded-image pixel and byte limits.

A nested `<svg>` or `<symbol>` counts as an isolated raster layer, including
copies reached through `<use>`. [#541](https://github.com/vocaro/EPUBLib/issues/541)
records the independently found symbol accounting gap: the pinned renderer's
[`use_node` conversion](https://raw.githubusercontent.com/linebender/resvg/v0.48.1/crates/usvg/src/parser/use_node.rs)
creates a clipped group for each symbol use, while the previous Swift count
charged none for a plain symbol. Marker content is kept near its viewport,
measured relative to that viewport even when its origin is far from zero. Marker
viewports are also bounded after potential host transformations and strokeWidth
scaling. The largest projected marker content area, including orientation and
strokes, multiplied by the weighted marker-instance count may reach at most 256
root canvas areas. Ordinary arrowheads retain their existing resolution. The
dedicated raster screen checks geometry, transformation alternatives, inherited
strokes and candidate stylesheet values before rendering.

Nested `<style>` elements are refused by `SVGStyleScreen` before any stylesheet
text is read, including the font-discovery and disclosure paths before
serialization. The walk charges one visit per node and stops as soon as it
finds a style inside another style. It shares the existing node and depth
ceilings. After serialization, nested levels' text is concatenated in document order and the
renderer applies that concatenation. [The recorded experiment and minimal
reproducers](https://github.com/vocaro/EPUBLib/issues/375#issuecomment-6141053142)
settle that behavior; refusal avoids reading the same descendant stylesheet for
every level.

Embedded raster images are capped at 4 megapixels each and 16 megapixels in total.
Output is capped at 4,096 pixels on its long side and 16 megapixels, reduced further for
isolated layers to fit the raster working-memory budget. SVG text uses outline fonts;
embedded color-glyph tables are omitted and disclosed. Retained renderer font databases
share a 64 MiB budget across the process. Each distinct set of fonts an SVG names is one
database, with its own copy of the fallback faces, shared by every drawing that names
those fonts.

[Documentation index](../README.md#documentation)
