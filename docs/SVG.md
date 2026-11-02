# SVG technical reference

This document describes the SVG/SVGZ model, editing contracts, preservation rules, and resource limits implemented by SvgKit. Start with the [README](../README.md) for usage examples.

## Contents

- [Editing sessions](#editing-sessions)
- [Structure and content](#structure-and-content)
- [Editable geometry and transforms](#editable-geometry-and-transforms)
- [Styles and rich text](#styles-and-rich-text)
- [Resources and references](#resources-and-references)
- [Conversion contract](#conversion-contract)
- [Geometry metadata](#geometry-metadata)
- [Limits and errors](#limits-and-errors)
- [Compatibility evidence](#compatibility-evidence)
- [References](#references)

## Editing sessions

`document.edit((editor) { ... })` copies the document, runs a synchronous callback
and returns a validated immutable snapshot. Exceptions leave the original
unchanged. A longer-lived `SvgEditor(document: document)` can produce multiple
independent `build()` snapshots. Handles belong to their session; cross-session
insertion is rejected. Use `importElement(element: handle.xml)` to copy instead.

`root`, `elements`, `elementById`, `children`, `descendants` and `parent` return
stable editing handles. `xml` on a handle returns a detached copy, including
namespace declarations needed by the subtree. The complete XML remains the
source of truth: no parallel scene model discards unknown SVG features.

`build()` rejects duplicate IDs by default; `validateIds: false` permits retention
of pre-existing malformed markup. `elementById` rejects ambiguous IDs rather
than silently choosing one. Successful build validates XML and resource limits,
not every SVG schema constraint, resource type, CSS value or rendering outcome.

## Structure and content

All constructors return **detached** elements. Insert them with
`parent.insert(child: element, index: ...)`; index is the final element-child
position after removing an existing child from that parent. Text/comments are
not counted. Omitting index appends after all mixed content. Cycles and root
reparent/removal are rejected. `remove()` keeps a detached handle that can be
reinserted. References are not deleted automatically.

`createElement(name: ..., namespace: ..., attributes: ...)` supports every SVG
and extension element. `setAttribute` uses qualified names, while
`setNamespacedAttribute` declares a prefix and rejects conflicting bindings.
Namespace bindings are preserved on move/import. Rebinding an existing namespace
requires explicit XML replacement, so already-resolved node names cannot silently
change meaning. `replaceContent(nodes: ...)` accepts copied XML text, CDATA,
comments, processing instructions and elements. Existing child handles detach.

`group(selection: ...)` requires contiguous siblings, sorts by document order
and includes intervening comments/text. `ungroup` splices children into the parent.
Groups carrying transforms/styles/effects require explicit
`discardGroupAttributes: true`, or caller handling before ungrouping. These are
**structural** operations, not appearance-preserving flattening. Reparenting can
change inherited style, CSS selectors, viewport coordinates and compositing;
group opacity cannot generally be distributed among children. Geometry/style
compensation belongs in the host adapter.

## Editable geometry and transforms

`SvgPathData` parses every SVG path command, including implicit command repeats,
implicit lines following moveto, adjacent signs, decimal/exponent numbers and
compact arc flags. `SvgPathCommand` retains the command letter and immutable
operands in SVG order. Named constructors cover moves, lines, cubics, quadratics,
arcs and closepath; the general constructor covers H/V/S/T as well.

`normalized()` emits absolute M/L/C/Q/A/Z commands. It expands horizontal/vertical
segments and reflected control points, preserves subpath origins after closepath
and keeps arcs as arcs. Arc radii are made nonnegative as specified by SVG; they
are not approximated with cubic curves. `replace(start:, end:, replacement:)`
edits a command range. Normalize first when editing explicit anchor/control-point
coordinates; changing a relative command otherwise intentionally affects the
following coordinates. Shape-to-path conversion, bounds, stroke outlines, curve
flattening and Boolean operations remain in host geometry.

`SvgPointList` edits polygon/polyline points as `(x: ..., y: ...)` records.
`SvgTransformList` retains ordered translate, scale, rotate, skewX, skewY and
matrix functions. `prepend` places a function outside the existing coordinate
space; `append` places it inside. Angles use degrees. These are format syntax
values, not a duplicate of the host's affine/scene model. CSS transform values
with units or functions such as `calc()` remain editable as CSS source instead.

Elements expose `pathData`/`setPathData`, `points`/`setPoints`,
`transforms`/`setTransforms`, `length`/`setLength`, `viewBox`/`setViewBox`, and
`preserveAspectRatio`/`setPreserveAspectRatio`. Use the transform attribute name
argument for `gradientTransform` and `patternTransform`.

Typed attribute parsers are strict. They reject malformed syntax without
discarding the containing document; the original attribute remains editable as
text. SVG renderer error recovery for partially malformed paths is not emulated.
Path parsing defaults to 1,000,000 commands and 16,000,000 characters; point lists
default to 1,000,000 points, transform lists to 100,000 functions. Limits are
configurable per parser and nonpositive limits are rejected.

## Styles and rich text

`SvgStyle` edits **specified inline declarations**. It retains source text until
an edit, including unknown/invalid balanced fragments. Property edits remove all
occurrences of that property and append the replacement. Untouched declarations
keep their source spelling. Parsing respects comments, strings, escaped names,
data URLs, nested functions/blocks, custom-property case and `!important`.
`property(name:)` reports the winning inline declaration, considering duplicate
declarations and importance. Values themselves are not validated against each
CSS property's grammar. Unbalanced CSS requires raw attribute editing instead.

`setStyleProperty`, `removeStyleProperty` and `setClasses` operate on an element.
No computed cascade, selector matching, inherited-value resolution, variable
substitution or external CSS loading occurs. Stylesheet elements are edited with
`setText`/`replaceTextRun`; arbitrary stylesheets remain intact as source.

`setText` deliberately replaces all children with plain text. For rich text, use
`textRuns` and `replaceTextRun` to edit one immediate run while preserving tspan,
textPath, comments and positioning attributes. `appendText` adds a run without
removing spans. Text-run indices count immediate text/CDATA nodes, not characters
or rendered glyphs. Font selection, shaping, text-on-path layout and outlining
require the host. No whitespace is inserted by pretty printing.

## Resources and references

Convenience constructors cover basic shapes, text, images, symbols, use,
linear/radial gradients and stops, patterns, clipping, masks, filter containers
and markers. `definitions` finds/creates the first SVG defs child of the root.
Gradient coordinates/stops, pattern children, clip geometry, mask content and
ordered fe* filter primitives remain normal editable elements. Filter input and
result names are not XML IDs and are edited as attributes. Colors remain CSS
strings, preserving currentColor, variables and color-space syntax.

`setHref` synchronizes SVG 2 href and any existing XLink href. `href` gives SVG 2
precedence. `hrefTarget` resolves only known fragment-only links, without fetching
or expanding use/symbol instances. `setReference(property:, target:)` assigns a
target ID if needed and writes href or an inline CSS URL.

`renameId` updates recognized local references throughout the document.
`duplicate` copies a subtree next to its source, assigns unique IDs to every
identified descendant and rewrites internal links. References to targets outside
the copied subtree remain unchanged. `importElement` remaps IDs by default;
pass `remapIds: false` when the caller manages identity. Outside stylesheet rules
are not duplicated, so ID-based rules may need edits for a copied subtree.

Recognized static reference forms are:

- Fragment-only href/XLink href, including percent-encoded and Unicode IDs.
- URL tokens in presentation attributes, inline styles and style text, including
  quoted arguments and CSS escapes. Colors, comments and quoted content are not
  treated as references.
- CSS ID selectors in ordinary qualified rules, including rules inside common
  grouping at-rules such as media/supports/layer/container.
- SMIL begin/end event or syncbase references and common ARIA IDREF attributes.

`references` reports these forms; `danglingReferences` filters targets absent
from the tree. Unmatched CSS selectors can be intentional, so this is diagnostic
data, not an automatic build failure. Resource target types and circular paint/
use inheritance are not evaluated.

**Caller-managed forms:** scripts/event handlers, external styles/resources,
extension-specific links, CSS attribute selectors/nesting, references in at-rule
preludes and URLs under nonempty xml:base. The kit cannot determine their meaning
without a runtime or document base URL. It preserves these sources; explicit
edits may be necessary during ID changes. It does not rewrite external URIs just
because they end in a matching fragment. `hrefTarget` returns null under explicit
xml:base and `setReference` rejects an implicit local-link assignment there.

## Conversion contract

`SvgCodec` converts one complete document, with a `List<int>` binary side so it
can be fused with `base64`. It does not offer incremental conversion. Encoding
returns `Uint8List`. `compressed: true` selects SVGZ output; input compression is
detected independently by gzip magic, so the same codec reads SVG and SVGZ.

`SvgDocument.parse(source: ...)` accepts a Dart XML string.
`SvgDocument.fromXml(document: ...)` validates and snapshots a mutable XML tree.
The `xml`, `root` and `elementById` accessors return detached copies. Modify the
whole `xml` copy and create a new snapshot to retain edits. Modifying a detached
lookup result does not mutate the document.

Serialization deliberately avoids indentation changes, since inserted
whitespace can change SVG text. Unknown elements, namespace declarations,
attributes, processing instructions, comments and CDATA remain in the XML model.
Quotes and entity spelling need not match the original byte representation.

## Geometry metadata

`viewBox` returns an `SvgViewBox` or null. Finite minimum coordinates and
nonnegative dimensions are required; zero dimensions remain valid.
`width` and `height` expose `SvgLength`, or null when missing/`auto`.
`SvgLength.pixels` resolves absolute units at 96 CSS pixels per inch. Percentages,
font-relative and viewport-relative units return null. `resolve(...)` can use
explicit host-supplied percentage basis, font size, root font size, x-height,
zero advance and viewport dimensions. Missing required metrics return null.
The caller chooses the correct percentage basis for the attribute (width,
height, or normalized diagonal), rather than assuming all percentages use width.
`SvgPreserveAspectRatio` retains alignment, meet/slice and SVG 1.1's defer flag.
Unsupported expressions such as CSS `calc()` remain preserved in XML but are
rejected by the optional numeric helper. This does not prevent document decoding.

## Limits and errors

| Limit | Default |
| --- | --- |
| Compressed input / UTF-8 XML bytes | 64 MiB |
| Element nesting | 256 |
| XML events, including comments and text | 1,000,000 |

Gzip decompression is bounded by ZCodec. XML events are counted before allocating
the DOM. Internal DTD subsets and entity declarations are rejected; external
DTD identifiers do not trigger network or filesystem access. The parser does not
expand `use` references or resolve CSS URLs. UTF-16 input requires a BOM; declared
ISO-8859-1 input is decoded as Latin-1. The encoding declaration is rewritten to
UTF-8 on output. Other declared encodings
and BOM/declaration mismatches are rejected.

Invalid syntax raises the XML library's parsing exceptions or `FormatException`;
invalid limits raise `ArgumentError`. ZCodec's format errors propagate with their
compression diagnostics. Do not treat a successful decode as an SVG conformance
certificate or an HTML sanitization decision.

Edited/imported trees are preflighted for depth, node count and character lower
bounds before recursive copying/serialization. Snapshot creation then applies the
exact XML-event/UTF-8 checks. Directly constructing objects is not streaming I/O;
the authoring session and output snapshot coexist in memory.

## Compatibility evidence

The ordinary tests run on Dart VM and JavaScript/Node. The external corpus
contains W3C SVG 1.1 Second Edition fixtures for paths, shapes, transforms,
gradients, patterns, masks, clipping, filters, text, CSS and reusable elements.
An internal-entity fixture is an explicit expected rejection. The 94-file
manifest includes 93 accepted documents. Independent librsvg comparisons cover
retained markup, rewritten typed attributes and a visible-edit oracle; see
[the detailed evidence](validation.md). This does not constitute kit rendering.
Linked test-suite assets are not downloaded; comparisons use the same local
resource availability for both files and do not prove external-resource fidelity.

## References

- [W3C SVG 2 document structure](https://www.w3.org/TR/SVG/struct.html)
- [W3C SVG coordinate systems](https://www.w3.org/TR/SVG/coords.html)
- [W3C SVG path grammar and normalization rules](https://www.w3.org/TR/SVG2/paths.html)
- [W3C SVG styling](https://www.w3.org/TR/SVG2/styling.html)
- [W3C SVG linking](https://www.w3.org/TR/SVG2/linking.html)
- [W3C CSS syntax](https://www.w3.org/TR/css-syntax-3/)
- [W3C SVG test suite, 2011-08-16](https://www.w3.org/Graphics/SVG/Test/20110816/)
- [XML package](https://pub.dev/packages/xml)
- [ZCodec](https://pub.dev/packages/zcodec)
