import 'package:svgkit/src/editing/svg_editor.dart';
import 'package:svgkit/src/model/svg_document.dart';
import 'package:svgkit/src/values/svg_number_reader.dart';
import 'package:svgkit/src/values/svg_path.dart';

/// A gradient stop with an editable CSS color and normalized offset/opacity.
final class SvgGradientStop {
  /// Offset in the inclusive range zero to one.
  final double offset;

  /// CSS paint color, including currentColor and var() expressions.
  final String color;

  /// Opacity in the inclusive range zero to one.
  final double opacity;

  /// Creates a finite stop without assuming a color space or color-management engine.
  SvgGradientStop({
    required this.offset,
    required this.color,
    this.opacity = 1,
  }) {
    if (!offset.isFinite || offset < 0 || offset > 1 || !opacity.isFinite || opacity < 0 || opacity > 1 || color.trim().isEmpty) {
      throw const FormatException('Invalid SVG gradient stop.');
    }
  }
}

/// Convenient constructors for editable SVG graphics and reusable resources.
///
/// Every constructor returns a detached element. Insert it into a parent or
/// [SvgEditor.definitions] explicitly, so creation never changes painting order.
/// Arbitrary SVG elements and extension data use [SvgEditor.createElement].
extension SvgAuthoring on SvgEditor {
  /// Creates an editable path, retaining curves, arcs and subpaths.
  SvgEditableElement path({required SvgPathData data, String? id}) => createElement(name: 'path', attributes: {'id': ?id, 'd': data.toString()});

  /// Creates a rectangle with optional independent corner radii.
  SvgEditableElement rectangle({required SvgLength width, required SvgLength height, SvgLength? x, SvgLength? y, SvgLength? radiusX, SvgLength? radiusY, String? id}) {
    _nonnegative(width);
    _nonnegative(height);
    if (radiusX != null) {
      _nonnegative(radiusX);
    }
    if (radiusY != null) {
      _nonnegative(radiusY);
    }
    return createElement(
      name: 'rect',
      attributes: {
        'id': ?id,
        'width': width.toString(),
        'height': height.toString(),
        if (x != null) 'x': x.toString(),
        if (y != null) 'y': y.toString(),
        if (radiusX != null) 'rx': radiusX.toString(),
        if (radiusY != null) 'ry': radiusY.toString(),
      },
    );
  }

  /// Creates a circle using SVG length units.
  SvgEditableElement circle({required SvgLength radius, SvgLength? centerX, SvgLength? centerY, String? id}) {
    _nonnegative(radius);
    return createElement(
      name: 'circle',
      attributes: {
        'id': ?id,
        'r': radius.toString(),
        if (centerX != null) 'cx': centerX.toString(),
        if (centerY != null) 'cy': centerY.toString(),
      },
    );
  }

  /// Creates an ellipse with independent horizontal and vertical radii.
  SvgEditableElement ellipse({required SvgLength radiusX, required SvgLength radiusY, SvgLength? centerX, SvgLength? centerY, String? id}) {
    _nonnegative(radiusX);
    _nonnegative(radiusY);
    return createElement(
      name: 'ellipse',
      attributes: {
        'id': ?id,
        'rx': radiusX.toString(),
        'ry': radiusY.toString(),
        if (centerX != null) 'cx': centerX.toString(),
        if (centerY != null) 'cy': centerY.toString(),
      },
    );
  }

  /// Creates a line segment with length-valued endpoints.
  SvgEditableElement line({required SvgLength x1, required SvgLength y1, required SvgLength x2, required SvgLength y2, String? id}) => createElement(
    name: 'line',
    attributes: {
      'id': ?id,
      'x1': x1.toString(),
      'y1': y1.toString(),
      'x2': x2.toString(),
      'y2': y2.toString(),
    },
  );

  /// Creates a polygon or an open polyline from editable coordinate pairs.
  SvgEditableElement polygon({required SvgPointList points, bool closed = true, String? id}) => createElement(
    name: closed ? 'polygon' : 'polyline',
    attributes: {
      'id': ?id,
      'points': points.toString(),
    },
  );

  /// Creates text with one run; insert spans/text paths for rich text.
  SvgEditableElement text({required String value, SvgLength? x, SvgLength? y, String? id}) => createElement(
    name: 'text',
    text: value,
    attributes: {
      'id': ?id,
      if (x != null) 'x': x.toString(),
      if (y != null) 'y': y.toString(),
    },
  );

  /// Creates a reusable symbol with its own optional viewBox.
  SvgEditableElement symbol({required String id, SvgViewBox? viewBox}) => createElement(name: 'symbol', attributes: {'id': id, if (viewBox != null) 'viewBox': viewBox.toString()});

  /// Creates a use instance without expanding or flattening its source.
  SvgEditableElement use({required String href, SvgLength? x, SvgLength? y, SvgLength? width, SvgLength? height, String? id}) => createElement(
    name: 'use',
    attributes: {
      'id': ?id,
      'href': href,
      if (x != null) 'x': x.toString(),
      if (y != null) 'y': y.toString(),
      if (width != null) 'width': width.toString(),
      if (height != null) 'height': height.toString(),
    },
  );

  /// Creates an image reference; data URIs are accepted without decoding pixels.
  SvgEditableElement image({required String href, required SvgLength width, required SvgLength height, SvgLength? x, SvgLength? y, String? id}) {
    _nonnegative(width);
    _nonnegative(height);
    return createElement(
      name: 'image',
      attributes: {
        'id': ?id,
        'href': href,
        'width': width.toString(),
        'height': height.toString(),
        if (x != null) 'x': x.toString(),
        if (y != null) 'y': y.toString(),
      },
    );
  }

  /// Creates a linear gradient; omitted coordinates retain SVG defaults.
  SvgEditableElement linearGradient({
    required String id,
    Iterable<SvgGradientStop> stops = const [],
    SvgLength? x1,
    SvgLength? y1,
    SvgLength? x2,
    SvgLength? y2,
    bool userSpace = false,
    String? href,
  }) {
    final SvgEditableElement gradient = createElement(
      name: 'linearGradient',
      attributes: {
        'id': id,
        'gradientUnits': userSpace ? 'userSpaceOnUse' : 'objectBoundingBox',
        'href': ?href,
        if (x1 != null) 'x1': x1.toString(),
        if (y1 != null) 'y1': y1.toString(),
        if (x2 != null) 'x2': x2.toString(),
        if (y2 != null) 'y2': y2.toString(),
      },
    );
    _insertStops(editor: this, gradient: gradient, stops: stops);
    return gradient;
  }

  /// Creates a radial gradient, including SVG 2's focal radius.
  SvgEditableElement radialGradient({
    required String id,
    Iterable<SvgGradientStop> stops = const [],
    SvgLength? centerX,
    SvgLength? centerY,
    SvgLength? radius,
    SvgLength? focalX,
    SvgLength? focalY,
    SvgLength? focalRadius,
    bool userSpace = false,
    String? href,
  }) {
    if (radius != null) {
      _nonnegative(radius);
    }
    if (focalRadius != null) {
      _nonnegative(focalRadius);
    }
    final SvgEditableElement gradient = createElement(
      name: 'radialGradient',
      attributes: {
        'id': id,
        'gradientUnits': userSpace ? 'userSpaceOnUse' : 'objectBoundingBox',
        'href': ?href,
        if (centerX != null) 'cx': centerX.toString(),
        if (centerY != null) 'cy': centerY.toString(),
        if (radius != null) 'r': radius.toString(),
        if (focalX != null) 'fx': focalX.toString(),
        if (focalY != null) 'fy': focalY.toString(),
        if (focalRadius != null) 'fr': focalRadius.toString(),
      },
    );
    _insertStops(editor: this, gradient: gradient, stops: stops);
    return gradient;
  }

  /// Creates a clipping resource; insert any SVG geometry into it.
  SvgEditableElement clipPath({required String id, bool objectBoundingBox = false}) =>
      createElement(name: 'clipPath', attributes: {'id': id, 'clipPathUnits': objectBoundingBox ? 'objectBoundingBox' : 'userSpaceOnUse'});

  /// Creates a mask with explicit region and content coordinate units.
  SvgEditableElement mask({required String id, bool userSpace = false, bool contentUserSpace = true}) => createElement(
    name: 'mask',
    attributes: {
      'id': id,
      'maskUnits': userSpace ? 'userSpaceOnUse' : 'objectBoundingBox',
      'maskContentUnits': contentUserSpace ? 'userSpaceOnUse' : 'objectBoundingBox',
    },
  );

  /// Creates an editable pattern tile without flattening its children.
  SvgEditableElement pattern({required String id, required SvgLength width, required SvgLength height, bool userSpace = false, SvgViewBox? viewBox}) {
    _nonnegative(width);
    _nonnegative(height);
    return createElement(
      name: 'pattern',
      attributes: {
        'id': id,
        'width': width.toString(),
        'height': height.toString(),
        'patternUnits': userSpace ? 'userSpaceOnUse' : 'objectBoundingBox',
        if (viewBox != null) 'viewBox': viewBox.toString(),
      },
    );
  }

  /// Creates an editable filter graph; insert ordered fe* primitive elements.
  SvgEditableElement filter({required String id, bool userSpace = false}) => createElement(name: 'filter', attributes: {'id': id, 'filterUnits': userSpace ? 'userSpaceOnUse' : 'objectBoundingBox'});

  /// Creates an editable marker definition for stroked paths.
  SvgEditableElement marker({required String id, SvgViewBox? viewBox, String orient = 'auto'}) =>
      createElement(name: 'marker', attributes: {'id': id, 'orient': orient, if (viewBox != null) 'viewBox': viewBox.toString()});
}

/// Adds validated gradient stops without modifying existing children.
void _insertStops({required SvgEditor editor, required SvgEditableElement gradient, required Iterable<SvgGradientStop> stops}) {
  for (final SvgGradientStop stop in stops) {
    gradient.insert(
      child: editor.createElement(name: 'stop', attributes: {'offset': svgNumber(stop.offset), 'stop-color': stop.color, 'stop-opacity': svgNumber(stop.opacity)}),
    );
  }
}

/// Rejects negative dimensions while allowing zero-sized SVG geometry.
void _nonnegative(SvgLength length) {
  if (length.value < 0) {
    throw const FormatException('SVG dimensions must be nonnegative.');
  }
}
