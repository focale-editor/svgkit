/// Strict, bounded cursor for SVG number and flag grammar.
final class SvgNumberReader {
  /// Source attribute.
  final String source;

  /// Current UTF-16 offset.
  int position = 0;

  /// SVG decimal/exponent grammar, excluding infinities and hexadecimal.
  static final RegExp _number = RegExp(r'[+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?');

  /// Creates a cursor over one attribute.
  SvgNumberReader({
    required this.source,
  });

  /// Whether all remaining characters are SVG whitespace.
  bool get done {
    whitespace();
    return position == source.length;
  }

  /// Skips only the whitespace allowed by SVG attribute syntax.
  void whitespace() {
    while (position < source.length && ' \t\r\n'.contains(source[position])) {
      position++;
    }
  }

  /// Reads a finite number, optionally preceded by one comma.
  double number({bool comma = true, bool flag = false}) {
    whitespace();
    if (comma && position < source.length && source[position] == ',') {
      position++;
      whitespace();
    }
    if (flag) {
      if (position >= source.length || !'01'.contains(source[position])) {
        throw FormatException('Expected an SVG arc flag.', source, position);
      }
      return double.parse(source[position++]);
    }
    final Match? match = _number.matchAsPrefix(source, position);
    if (match == null) {
      throw FormatException('Expected an SVG number.', source, position);
    }
    position = match.end;
    final double value = double.parse(match[0]!);
    if (!value.isFinite) {
      throw FormatException('Non-finite SVG number.', source, match.start);
    }
    return value;
  }
}

/// Writes a finite SVG number without unnecessary decimal zeroes.
String svgNumber(double value) {
  if (!value.isFinite) {
    throw const FormatException('Non-finite SVG number.');
  }
  if (value == 0) {
    return '0';
  }
  final String result = value.toString();
  return result.endsWith('.0') ? result.substring(0, result.length - 2) : result;
}
