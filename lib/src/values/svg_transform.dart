import 'package:svgkit/src/values/svg_number_reader.dart';

/// An SVG transform function, retaining its order and editable arguments.
final class SvgTransform {
  /// SVG function name, including the case-sensitive skewX/skewY spellings.
  final String name;

  /// Finite operands; angles use degrees.
  final List<double> values;

  /// Creates a validated SVG transform function.
  SvgTransform({
    required this.name,
    required Iterable<double> values,
  }) : values = List.unmodifiable(values) {
    final bool validCount = switch (name) {
      'matrix' => this.values.length == 6,
      'translate' || 'scale' => this.values.length == 1 || this.values.length == 2,
      'rotate' => this.values.length == 1 || this.values.length == 3,
      'skewX' || 'skewY' => this.values.length == 1,
      _ => false,
    };
    if (!validCount || !this.values.every((value) => value.isFinite)) {
      throw const FormatException('Invalid SVG transform.');
    }
  }

  /// Translates in SVG user units.
  factory SvgTransform.translate({
    required double x,
    double y = 0,
  }) => SvgTransform(name: 'translate', values: [x, y]);

  /// Scales uniformly unless a separate vertical factor is supplied.
  factory SvgTransform.scale({
    required double x,
    double? y,
  }) => SvgTransform(name: 'scale', values: [x, y ?? x]);

  /// Rotates in degrees about the supplied center.
  factory SvgTransform.rotate({
    required double degrees,
    double centerX = 0,
    double centerY = 0,
  }) => SvgTransform(name: 'rotate', values: [degrees, centerX, centerY]);

  /// Stores the six SVG affine matrix operands without an editor geometry type.
  factory SvgTransform.matrix({
    required double a,
    required double b,
    required double c,
    required double d,
    required double e,
    required double f,
  }) => SvgTransform(name: 'matrix', values: [a, b, c, d, e, f]);

  /// Skews the horizontal axis by an angle in degrees.
  factory SvgTransform.skewX({
    required double degrees,
  }) => SvgTransform(name: 'skewX', values: [degrees]);

  /// Skews the vertical axis by an angle in degrees.
  factory SvgTransform.skewY({
    required double degrees,
  }) => SvgTransform(name: 'skewY', values: [degrees]);

  @override
  String toString() => '$name(${values.map(svgNumber).join(' ')})';
}

/// An immutable SVG transform attribute, independent of CSS computed layout.
final class SvgTransformList {
  /// Functions in source order; this order must not be reversed during editing.
  final List<SvgTransform> transforms;

  /// Copies the ordered functions.
  SvgTransformList({
    Iterable<SvgTransform> transforms = const [],
  }) : transforms = List.unmodifiable(transforms);

  /// Parses every SVG transform attribute function, with bounded function count.
  ///
  /// CSS transforms with length/angle units and `calc()` remain editable through
  /// style text; this parser implements SVG's numeric attribute grammar.
  factory SvgTransformList.parse({
    required String source,
    int maxTransforms = 100000,
  }) {
    if (maxTransforms <= 0) {
      throw ArgumentError.value(maxTransforms, 'maxTransforms');
    }
    final SvgNumberReader reader = SvgNumberReader(source: source);
    final List<SvgTransform> transforms = [];
    while (!reader.done) {
      if (transforms.length >= maxTransforms) {
        throw const FormatException('SVG transform limit exceeded.');
      }
      if (transforms.isNotEmpty && source[reader.position] == ',') {
        reader.position++;
        reader.whitespace();
      }
      final Match? function = RegExp(r'[A-Za-z]+').matchAsPrefix(source, reader.position);
      if (function == null) {
        throw FormatException('Expected SVG transform function.', source, reader.position);
      }
      reader.position = function.end;
      reader.whitespace();
      if (reader.position >= source.length || source[reader.position++] != '(') {
        throw const FormatException('Expected transform opening parenthesis.');
      }
      final List<double> values = [];
      reader.whitespace();
      while (reader.position < source.length && source[reader.position] != ')') {
        if (values.length >= 6) {
          throw const FormatException('Too many transform arguments.');
        }
        values.add(reader.number(comma: values.isNotEmpty));
        reader.whitespace();
      }
      if (reader.position >= source.length) {
        throw const FormatException('Unclosed SVG transform.');
      }
      reader.position++;
      transforms.add(SvgTransform(name: function[0]!, values: values));
    }
    return SvgTransformList(transforms: transforms);
  }

  /// Places an operation before the existing list (outside its coordinate space).
  SvgTransformList prepend({required SvgTransform transform}) => SvgTransformList(transforms: [transform, ...transforms]);

  /// Places an operation after the existing list (inside its coordinate space).
  SvgTransformList append({required SvgTransform transform}) => SvgTransformList(transforms: [...transforms, transform]);

  @override
  String toString() => transforms.join(' ');
}
