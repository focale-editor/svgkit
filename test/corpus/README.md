# SvgKit external corpus

The manifest pins 94 W3C internet fixtures with URL, revision, size, SHA-256,
license and expected outcome. One internal-DTD fixture is an expected rejection.
The editing expansion adds 72 approved SVG 1.1 Second Edition cases for path
grammar, transforms, gradients, markers, CSS, text paths and filters. Run the fetcher and checker from this package:

```sh
python3 tool/fetch_corpus.py
dart run tool/check_corpus.dart
dart run tool/check_editing_corpus.dart
python3 tool/verify_editing.py
```

`files/` and `output/` are ignored and excluded from publication. The checker
fails on missing files and unexpected outcomes; it does not silently skip
external coverage. Ordinary `dart test` stays offline and independent of this
corpus. See the [technical reference](../../docs/SVG.md).

Decoded documents are written under `output/` for independent validation.
Source works are not redistributed. Consult each manifest license before
copying third-party artwork elsewhere.

`check_editing_corpus.dart` rewrites paths, points and transform attributes through
the typed editing API and saves/reopens SVGZ. Seven deliberately malformed W3C
paths are reported and preserved verbatim. `verify_editing.py` requires exact
librsvg render equality for the 93 accepted documents, plus a separate handwritten
reference for visible edits. See [editing validation](../../docs/validation.md).

To check the existing downloads without network access or rewriting files:

```sh
python3 tool/fetch_corpus.py --verify-only
```
