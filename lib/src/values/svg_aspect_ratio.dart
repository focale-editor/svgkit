/// How a viewBox fits a viewport while preserving its aspect ratio.
enum SvgAspectRatioFit {
  /// Fits the entire viewBox inside the viewport, possibly leaving empty space.
  meet,

  /// Covers the viewport, possibly cropping part of the viewBox.
  slice,
}

/// Editable preserveAspectRatio syntax for SVG viewports and referenced images.
final class SvgPreserveAspectRatio {
  /// SVG alignment keyword, including `none` for independent axis scaling.
  final String alignment;

  /// Whether to fit inside or cover the viewport; ignored with alignment `none`.
  final SvgAspectRatioFit fit;

  /// Legacy SVG 1.1 defer flag, retained for referenced images.
  final bool defer;

  /// Creates a validated preserveAspectRatio value.
  SvgPreserveAspectRatio({
    this.alignment = 'xMidYMid',
    this.fit = SvgAspectRatioFit.meet,
    this.defer = false,
  }) {
    if (alignment != 'none' && !RegExp(r'^x(Min|Mid|Max)Y(Min|Mid|Max)$').hasMatch(alignment)) {
      throw const FormatException('Invalid SVG aspect ratio alignment.');
    }
  }

  /// Parses SVG 1.1/2 aspect ratio syntax without computing viewport layout.
  factory SvgPreserveAspectRatio.parse({
    required String source,
  }) {
    final List<String> tokens = source.trim().split(RegExp(r'[ \t\r\n]+'));
    final bool defer = tokens.first == 'defer';
    if (defer) {
      tokens.removeAt(0);
    }
    if (tokens.isEmpty || tokens.length > 2 || (tokens.length == 2 && tokens[1] != 'meet' && tokens[1] != 'slice')) {
      throw const FormatException('Invalid SVG aspect ratio syntax.');
    }
    return SvgPreserveAspectRatio(alignment: tokens.first, fit: tokens.length == 2 && tokens[1] == 'slice' ? SvgAspectRatioFit.slice : SvgAspectRatioFit.meet, defer: defer);
  }

  @override
  String toString() => '${defer ? 'defer ' : ''}$alignment ${fit.name}';
}
