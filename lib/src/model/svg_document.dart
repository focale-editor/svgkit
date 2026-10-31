import 'dart:convert';
import 'dart:math' as math;

import 'package:svgkit/src/values/svg_number_reader.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

/// SVG's namespace URI, including in prefixed documents.
const String svgNamespace = 'http://www.w3.org/2000/svg';

/// Resource ceilings applied before building the XML tree.
final class SvgLimits {
  /// Maximum compressed input and uncompressed UTF-8 document size.
  final int maxBytes;

  /// Maximum XML nesting depth.
  final int maxDepth;

  /// Maximum number of XML events, including text and comments.
  final int maxNodes;

  /// Creates bounded defaults suitable for complete in-memory documents.
  const SvgLimits({this.maxBytes = 64 * 1024 * 1024, this.maxDepth = 256, this.maxNodes = 1000000});
}

/// An immutable snapshot of SVG markup, including unknown extension data.
///
/// [xml] returns an independent mutable copy. Create a replacement with
/// [SvgDocument.fromXml] after editing it. No scripts, styles or external
/// references are executed or fetched; this class is not an SVG sanitizer.
final class SvgDocument {
  /// Retained XML tree, never exposed for mutation.
  final XmlDocument _xml;

  /// Creates a snapshot after validating XML and the SVG root.
  factory SvgDocument.parse({required String source, SvgLimits limits = const SvgLimits()}) {
    if (limits.maxBytes <= 0 || limits.maxDepth <= 0 || limits.maxNodes <= 0) {
      throw ArgumentError('SVG limits must be positive.');
    }
    if (source.length > limits.maxBytes || utf8.encode(source).length > limits.maxBytes) {
      throw const FormatException('SVG exceeds the document limit.');
    }
    int depth = 0;
    int nodes = 0;
    // The event reader checks nesting before the DOM builder can recurse.
    for (final XmlEvent event in parseEvents(source)) {
      if (++nodes > limits.maxNodes) {
        throw const FormatException('SVG exceeds the node limit.');
      }
      if (event is XmlDoctypeEvent) {
        // External SVG 1.1 declarations are common. Internal declarations can
        // introduce entity expansion and are outside the portable contract.
        if (event.internalSubset != null) {
          throw const FormatException('SVG internal DTD subsets are unsupported.');
        }
      }
      if (event is XmlStartElementEvent) {
        if (depth + 1 > limits.maxDepth) {
          throw const FormatException('SVG exceeds the nesting limit.');
        }
        if (!event.isSelfClosing) {
          depth++;
        }
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
    }
    final XmlDocument document = XmlDocument.parse(source);
    final XmlElement root = document.rootElement;
    if (root.name.local != 'svg' || (root.name.prefix != null && root.namespaceUri == null) || (root.namespaceUri != null && root.namespaceUri != svgNamespace)) {
      throw const FormatException('Expected an SVG document root.');
    }
    return SvgDocument._(document: document);
  }

  /// Copies a mutable XML tree into a validated snapshot.
  factory SvgDocument.fromXml({required XmlDocument document, SvgLimits limits = const SvgLimits()}) => SvgDocument.parse(source: document.toXmlString(), limits: limits);

  /// Stores the validated private tree.
  SvgDocument._({required XmlDocument document}) : _xml = document;

  /// Returns a mutable tree detached from this document.
  XmlDocument get xml => _xml.copy();

  /// Returns a detached root element for inspection or editing.
  XmlElement get root => _xml.rootElement.copy();

  /// Returns the root viewport's optional user-space rectangle.
  SvgViewBox? get viewBox {
    final String? value = _xml.rootElement.getAttribute('viewBox');
    return value == null ? null : SvgViewBox.parse(value: value);
  }

  /// Root width, preserving relative units rather than guessing a viewport.
  SvgLength? get width => _length('width');

  /// Root height, preserving relative units rather than guessing a viewport.
  SvgLength? get height => _length('height');

  /// Looks up an element by its exact ID and returns a detached copy.
  XmlElement? elementById(String id) {
    if (_xml.rootElement.getAttribute('id') == id) {
      return root;
    }
    for (final XmlElement element in _xml.rootElement.descendantElements) {
      if (element.getAttribute('id') == id) {
        return element.copy();
      }
    }
    return null;
  }

  /// Serializes without pretty printing, which can change SVG text spacing.
  String toXmlString() => _xml.toXmlString();

  /// Parses an optional root length.
  SvgLength? _length(String name) {
    final String? value = _xml.rootElement.getAttribute(name);
    return value == null || value == 'auto' ? null : SvgLength.parse(value: value);
  }
}

/// A viewport rectangle in SVG user units.
final class SvgViewBox {
  /// Minimum horizontal coordinate.
  final double minX;

  /// Minimum vertical coordinate.
  final double minY;

  /// Nonnegative width; zero disables rendering.
  final double width;

  /// Nonnegative height; zero disables rendering.
  final double height;

  /// Creates a finite viewport rectangle.
  SvgViewBox({required this.minX, required this.minY, required this.width, required this.height}) {
    if (![minX, minY, width, height].every((value) => value.isFinite) || width < 0 || height < 0) {
      throw const FormatException('Invalid SVG viewBox.');
    }
  }

  /// Parses a four-number SVG viewBox attribute.
  factory SvgViewBox.parse({required String value}) {
    final List<String> parts = value.trim().split(RegExp(r'[\s,]+'));
    if (parts.length != 4) {
      throw const FormatException('Expected four viewBox numbers.');
    }
    final List<double> values = parts.map(double.parse).toList();
    return SvgViewBox(minX: values[0], minY: values[1], width: values[2], height: values[3]);
  }

  @override
  String toString() => '$minX $minY $width $height';
}

/// A finite SVG length with its original CSS unit.
final class SvgLength {
  /// Numeric component before unit conversion.
  final double value;

  /// CSS unit, or an empty string for SVG user units.
  final String unit;

  /// Creates a length in a supported CSS unit.
  SvgLength({required this.value, this.unit = ''}) {
    if (!value.isFinite || !['', 'px', 'pt', 'pc', 'mm', 'cm', 'in', 'q', 'em', 'ex', 'rem', 'ch', 'vw', 'vh', 'vmin', 'vmax', '%'].contains(unit)) {
      throw const FormatException('Invalid SVG length.');
    }
  }

  /// Parses a numeric SVG length without resolving relative units.
  factory SvgLength.parse({required String value}) {
    final RegExpMatch? match = RegExp(r'^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*([a-zA-Z%]*)\s*$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid SVG length.');
    }
    return SvgLength(value: double.parse(match[1]!), unit: match[2]!.toLowerCase());
  }

  /// Resolves absolute lengths at 96 CSS pixels per inch.
  ///
  /// Relative units require host layout and return null.
  double? get pixels => switch (unit) {
    '' || 'px' => value,
    'in' => value * 96,
    'cm' => value * 96 / 2.54,
    'mm' => value * 96 / 25.4,
    'q' => value * 96 / 101.6,
    'pt' => value * 96 / 72,
    'pc' => value * 16,
    _ => null,
  };

  /// Resolves relative lengths using explicitly supplied host layout metrics.
  ///
  /// The percentage basis depends on the SVG attribute: widths use viewport
  /// width, heights use height and radii/strokes use the normalized diagonal.
  /// Missing metrics return null; the kit never guesses font or viewport sizes.
  double? resolve({double? percentageBasis, double? fontSize, double? rootFontSize, double? xHeight, double? zeroAdvance, double? viewportWidth, double? viewportHeight}) {
    for (final double metric in [percentageBasis, fontSize, rootFontSize, xHeight, zeroAdvance, viewportWidth, viewportHeight].whereType<double>()) {
      if (!metric.isFinite || metric < 0) {
        throw ArgumentError('Length context metrics must be finite and nonnegative.');
      }
    }
    final double? basis = switch (unit) {
      '%' => percentageBasis == null ? null : percentageBasis / 100,
      'em' => fontSize,
      'rem' => rootFontSize,
      'ex' => xHeight,
      'ch' => zeroAdvance,
      'vw' => viewportWidth == null ? null : viewportWidth / 100,
      'vh' => viewportHeight == null ? null : viewportHeight / 100,
      'vmin' => viewportWidth == null || viewportHeight == null ? null : math.min(viewportWidth, viewportHeight) / 100,
      'vmax' => viewportWidth == null || viewportHeight == null ? null : math.max(viewportWidth, viewportHeight) / 100,
      _ => null,
    };
    final double? result = pixels ?? (basis == null ? null : value * basis);
    if (result != null && !result.isFinite) {
      throw const FormatException('Resolved SVG length is non-finite.');
    }
    return result;
  }

  @override
  String toString() => '${svgNumber(value)}$unit';
}
