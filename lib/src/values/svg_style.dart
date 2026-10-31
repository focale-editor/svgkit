import 'package:svgkit/src/values/svg_css_syntax.dart';

/// One inline CSS declaration; unknown property names and values are retained.
final class SvgStyleDeclaration {
  /// Case-normalized property name, except for case-sensitive custom properties.
  final String name;

  /// CSS value without the optional importance marker.
  final String value;

  /// Whether this declaration overrides ordinary declarations in this block.
  final bool important;

  /// Creates a syntactically balanced single declaration.
  SvgStyleDeclaration({
    required String name,
    required this.value,
    this.important = false,
  }) : name = _propertyName(name) {
    if ((value.trim().isEmpty && !this.name.startsWith('--')) || _topLevelSeparators(value, ';').isNotEmpty || _importance(value) != null) {
      throw const FormatException('Expected one CSS value without !important.');
    }
  }

  @override
  String toString() => '$name: $value${important ? ' !important' : ''}';
}

/// A loss-preserving inline CSS declaration block with property-level editing.
///
/// This manages specified styles, not the browser cascade. Selectors, inherited
/// styles, variables and external stylesheets are not evaluated.
final class SvgStyle {
  /// Original source, retained exactly until a property is changed.
  final String source;

  /// Creates a declaration block; balanced unknown fragments are preserved.
  SvgStyle({
    this.source = '',
  }) {
    _topLevelSeparators(source, ';');
  }

  /// Recognized declarations in source order, including duplicates.
  List<SvgStyleDeclaration> get declarations => List.unmodifiable(_parts.where((part) => part.declaration != null).map((part) => part.declaration!));

  /// The winning inline declaration, applying duplicate and !important rules.
  SvgStyleDeclaration? property({required String name}) {
    final String normalized = _propertyName(name);
    SvgStyleDeclaration? result;
    for (final SvgStyleDeclaration declaration in declarations) {
      if (declaration.name == normalized && (result == null || !result.important || declaration.important)) {
        result = declaration;
      }
    }
    return result;
  }

  /// Removes every declaration of a property, retaining all unrelated source.
  SvgStyle remove({required String name}) {
    final String normalized = _propertyName(name);
    return SvgStyle(source: _parts.where((part) => part.declaration?.name != normalized).map((part) => part.source).join());
  }

  /// Replaces all occurrences with a single declaration appended to the block.
  SvgStyle set({required String name, required String value, bool important = false}) {
    final SvgStyleDeclaration declaration = SvgStyleDeclaration(name: name, value: value, important: important);
    final String retained = remove(name: name).source;
    final String separator = retained.trim().isEmpty || retained.trimRight().endsWith(';') ? '' : ';';
    return SvgStyle(source: '$retained$separator$declaration;');
  }

  /// Splits declarations without splitting strings, functions or custom blocks.
  List<({String source, SvgStyleDeclaration? declaration})> get _parts {
    final List<int> ends = [..._topLevelSeparators(source, ';'), source.length];
    final List<({String source, SvgStyleDeclaration? declaration})> result = [];
    int start = 0;
    for (final int end in ends) {
      final String raw = source.substring(start, end);
      final List<int> colons = _topLevelSeparators(raw, ':');
      SvgStyleDeclaration? declaration;
      if (colons.isNotEmpty) {
        final int colon = colons.first;
        final String name = _withoutComments(raw.substring(0, colon)).trim();
        final String value = raw.substring(colon + 1).trim();
        final int? importance = _importance(value);
        try {
          declaration = SvgStyleDeclaration(name: name, value: importance == null ? value : value.substring(0, importance).trimRight(), important: importance != null);
        } on FormatException {
          // Invalid/extension fragments remain editable as source without loss.
        }
      }
      result.add((source: source.substring(start, end < source.length ? end + 1 : end), declaration: declaration));
      start = end + 1;
    }
    return result;
  }

  @override
  String toString() => source;
}

/// Normalizes ordinary property names while preserving custom-property case.
String _propertyName(String name) {
  final String decoded = decodeSvgCssEscapes(name);
  if (!RegExp(r'^(?:--[-_a-zA-Z0-9\u0080-\uffff]+|-?[_a-zA-Z\u0080-\uffff][-_a-zA-Z0-9\u0080-\uffff]*)$').hasMatch(decoded)) {
    throw const FormatException('Invalid CSS property name.');
  }
  return decoded.startsWith('--') ? decoded : decoded.toLowerCase();
}

/// Removes comments from a property name or the importance suffix.
String _withoutComments(String source) => source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');

/// Finds a trailing importance token only outside strings and nested blocks.
int? _importance(String source) {
  final List<int> marks = _topLevelSeparators(source, '!');
  if (marks.isEmpty) {
    return null;
  }
  final int mark = marks.last;
  return decodeSvgCssEscapes(_withoutComments(source.substring(mark + 1)).trim()).toLowerCase() == 'important' ? mark : null;
}

/// Finds delimiters while validating balanced CSS strings, comments and blocks.
List<int> _topLevelSeparators(String source, String delimiter) {
  final List<int> result = [];
  final List<String> stack = [];
  String? quote;
  for (int index = 0; index < source.length; index++) {
    final String char = source[index];
    if (char == '\\') {
      if (++index >= source.length) {
        throw const FormatException('Unfinished CSS escape.');
      }
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (source.startsWith('/*', index)) {
      final int end = source.indexOf('*/', index + 2);
      if (end < 0) {
        throw const FormatException('Unclosed CSS comment.');
      }
      index = end + 1;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if ('([{'.contains(char)) {
      stack.add(char);
    } else if (')]}'.contains(char)) {
      if (stack.isEmpty || '([{'.indexOf(stack.removeLast()) != ')]}'.indexOf(char)) {
        throw const FormatException('Unbalanced CSS block.');
      }
    } else if (stack.isEmpty && char == delimiter) {
      result.add(index);
    }
  }
  if (quote != null || stack.isNotEmpty) {
    throw const FormatException('Unclosed CSS string or block.');
  }
  return result;
}
