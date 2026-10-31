# SVG editing validation

Validated locally on 2026-10-27, Dart 3.13.5, Linux x64. No application integration,
publication, browser runtime or hosted CI was performed.

## Automated checks

- `dart fix --apply` and `dart format`: clean.
- `dart analyze`: no issues.
- `dart test`: 84 passing tests.
- `dart test --platform node`: the same 84 tests pass in JavaScript/Node.
- Both codec and editing examples execute successfully.
- The 94 pinned external fixtures produce 94 expected outcomes: 93 accepted,
  one explicit rejection of internal DTD entities.

Tests cover immutable snapshots and transaction failures; ownership/cycle/index
checks; namespace-preserving imports and moves; typed authoring and SVGZ saves;
group/ungroup semantics; text runs and arbitrary mixed content; all path command
kinds and malformed grammar; transforms/lengths/viewports; inline styles;
reference renaming, duplication, CSS escapes, Unicode, XLink and xml:base.

## Independent rendering

[The machine-readable report](validation/editing.json) records librsvg 2.62.4
results at 480 × 360 with identical local resource availability.

Across 93 accepted W3C documents, the editing pass parses and rewrites:

- 224 paths containing 936 commands, expanded to absolute coordinates and
  explicit control points without approximating arcs.
- 262 transform attributes, including gradient/pattern transforms.
- 16 polygon/polyline point lists, plus retained inline CSS.

All 93 edited documents are saved as SVGZ, reopened, written as SVG and rendered.
Every resulting PNG hash is **identical** to the source document render.
Seven deliberately malformed paths in `paths-data-18-f.svg` and
`paths-data-20-f.svg` are rejected by the optional strict path parser, reported
individually, and retained verbatim. They are not silently normalized or counted
as supported grammar.

A separate authoring scenario changes path control points, gradient stops and
IDs, shape dimensions, inline styles, rich text, a filter primitive, transforms,
use positioning, duplication and grouping. Its output renders identically to
[a handwritten expected SVG](../test/fixtures/editing_expected.svg), independently
of the editor implementation. The verifier also checks that the input differs
from this expected output, so a no-op cannot pass that oracle.

This totals **94 independent render comparisons** for editing. The
[codec corpus checker](../test/corpus/README.md) separately checks unchanged XML
round-trips. Neither result establishes a complete SVG renderer inside SvgKit,
computed CSS, text shaping, animation playback or arbitrary source fidelity.
Linked suite assets were not downloaded; both sides have the same availability.

## Reproduction

From the SvgKit directory, with Dart/Node and `/usr/bin/rsvg-convert` installed:

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test tool example
dart analyze
dart test
dart test --platform node
dart run example/svgkit_example.dart
dart run example/svgkit_editing_example.dart
python3 tool/fetch_corpus.py
dart run tool/check_corpus.dart
dart run tool/check_editing_corpus.dart
python3 tool/verify_editing.py
```

The Python verifier uses only the standard library and librsvg. Network access
is confined to the explicit corpus fetcher. Ordinary unit tests remain offline;
missing corpus files fail the opt-in checker. Downloaded fixtures/generated SVGs
are ignored and excluded from package publication; provenance and licenses stay
in the manifest.
