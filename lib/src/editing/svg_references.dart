import 'package:svgkit/src/values/svg_css_syntax.dart';
import 'package:xml/xml.dart';

/// Namespace used by SVG 1.1 resource links.
const String svgXlinkNamespace = 'http://www.w3.org/1999/xlink';

/// A recognized local reference in source markup.
final class SvgLocalReference {
  /// Referencing element's ID, if present.
  final String? sourceId;

  /// Attribute name or `style` for a stylesheet text node.
  final String location;

  /// Decoded fragment identifier.
  final String targetId;

  /// Creates a reference diagnostic without exposing mutable XML.
  const SvgLocalReference({
    required this.sourceId,
    required this.location,
    required this.targetId,
  });
}

/// Rewrites or collects understood local references without evaluating them.
///
/// Dynamic scripts, external files, application extensions and arbitrary CSS
/// attribute selectors require caller-managed edits. CSS ID selectors and URL
/// tokens are understood; declaration colors and quoted content stay untouched.
List<SvgLocalReference> rewriteSvgReferences({required XmlElement root, Map<String, String> replacements = const {}, bool renameIds = false}) {
  final List<SvgLocalReference> references = [];
  for (final XmlElement element in [root, ...root.descendantElements]) {
    final String? sourceId = element.getAttribute('id');
    final bool localUrls = !svgHasExplicitBase(element);

    /// Records a link and supplies its replacement, if requested.
    String target(String id, String location) {
      references.add(SvgLocalReference(sourceId: sourceId, location: location, targetId: id));
      return replacements[id] ?? id;
    }

    for (final XmlAttribute attribute in element.attributes) {
      final String name = attribute.name.local;
      String value = attribute.value;
      final bool unqualified = attribute.name.prefix == null;
      if (name == 'href' && (unqualified || attribute.namespaceUri == svgXlinkNamespace)) {
        if (localUrls) {
          value = _fragment(value, (id) => target(id, attribute.name.qualified));
        }
      } else if (unqualified && const ['aria-labelledby', 'aria-describedby', 'aria-controls', 'aria-owns', 'aria-flowto', 'aria-activedescendant'].contains(name)) {
        value = value.replaceAllMapped(RegExp(r'[^\s]+'), (match) => target(match[0]!, name));
      } else if (unqualified && (name == 'begin' || name == 'end')) {
        // The greedy prefix permits dots in IDs, followed by an event/syncbase.
        value = value.replaceAllMapped(RegExp(r'(^|;)(\s*)([^;\s]+)\.([A-Za-z_][\w]*(?:\([^;]*?\))?)'), (match) => '${match[1]}${match[2]}${target(match[3]!, name)}.${match[4]}');
      } else if (unqualified && (name == 'style' || _urlAttributes.contains(name))) {
        value = _rewriteCss(value, (id) => target(id, name), stylesheet: false, localUrls: localUrls);
      }
      if (replacements.isNotEmpty && value != attribute.value) {
        attribute.value = value;
      }
    }
    if (element.name.local == 'style' && (element.namespaceUri == null || element.namespaceUri == 'http://www.w3.org/2000/svg')) {
      for (final XmlNode node in element.children) {
        if (node is XmlText || node is XmlCDATA) {
          final String value = _rewriteCss(node.value!, (id) => target(id, 'style'), stylesheet: true, localUrls: localUrls);
          if (replacements.isNotEmpty && value != node.value) {
            if (node is XmlText) {
              node.value = value;
            } else if (node is XmlCDATA) {
              node.value = value;
            }
          }
        }
      }
    }
    if (renameIds && sourceId != null && replacements.containsKey(sourceId)) {
      element.setAttribute('id', replacements[sourceId]);
    }
  }
  return List.unmodifiable(references);
}

/// Presentation attributes whose SVG/CSS values can contain resource URLs.
const Set<String> _urlAttributes = {
  'fill',
  'stroke',
  'filter',
  'clip-path',
  'mask',
  'marker',
  'marker-start',
  'marker-mid',
  'marker-end',
  'cursor',
  'color-profile',
};

/// Rewrites a fragment-only URI, retaining external URIs exactly.
String _fragment(String value, String Function(String) replace) {
  final String trimmed = value.trim();
  if (!trimmed.startsWith('#')) {
    return value;
  }
  final String encoded = trimmed.substring(1);
  final String? decoded = decodeSvgFragment(encoded);
  if (decoded == null) {
    return value;
  }
  final String replacement = replace(decoded);
  if (replacement == decoded) {
    return value;
  }
  final int offset = value.indexOf('#');
  return '${value.substring(0, offset)}#${Uri.encodeComponent(replacement)}${value.substring(offset + trimmed.length)}';
}

/// Decodes both URI-escaped and literal Unicode SVG fragment identifiers.
String? decodeSvgFragment(String value) {
  final String ascii = value.runes.map((code) => code > 127 ? Uri.encodeComponent(String.fromCharCode(code)) : String.fromCharCode(code)).join();
  try {
    return Uri.decodeComponent(ascii);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// Escapes every code point to make arbitrary SVG IDs safe in CSS selectors.
String _cssIdentifier(String value) => value.runes.map((code) => '\\${code.toRadixString(16)} ').join();

/// Scans comments, strings, URL tokens and stylesheet selector/declaration blocks.
String _rewriteCss(String source, String Function(String) replace, {required bool stylesheet, required bool localUrls}) {
  final StringBuffer output = StringBuffer();
  final List<bool> declarationBlocks = [];
  int index = 0;
  int preludeStart = 0;
  while (index < source.length) {
    final int start = index;
    if (source.startsWith('/*', index)) {
      final int end = source.indexOf('*/', index + 2);
      index = end < 0 ? source.length : end + 2;
    } else if (source[index] == '"' || source[index] == "'") {
      index = _stringEnd(source, index);
    } else if (svgCssIdentifier.matchAsPrefix(source, index) case final Match match) {
      // Consume complete identifiers so embedded or escaped names are unambiguous.
      if (decodeSvgCssEscapes(match[0]!).toLowerCase() != 'url' || match.end >= source.length || source[match.end] != '(') {
        index = match.end;
      } else {
        int end = match.end + 1;
        String? quote;
        while (end < source.length) {
          final String char = source[end];
          if (char == '\\') {
            end += 2;
            continue;
          }
          if (quote != null) {
            if (char == quote) {
              quote = null;
            }
          } else if (char == '"' || char == "'") {
            quote = char;
          } else if (char == ')') {
            break;
          }
          end++;
        }
        if (end >= source.length) {
          output.write(source.substring(start));
          break;
        }
        String argument = source.substring(match.end + 1, end).trim();
        if (argument.length >= 2 && (argument.startsWith('"') || argument.startsWith("'")) && argument.endsWith(argument[0])) {
          argument = argument.substring(1, argument.length - 1);
        }
        final String decoded = decodeSvgCssEscapes(argument);
        final String updated = localUrls ? _fragment(decoded, replace) : decoded;
        output.write(updated == decoded ? source.substring(start, end + 1) : 'url("$updated")');
        index = end + 1;
        continue;
      }
    } else if (source[index] == '#' && stylesheet && (declarationBlocks.isEmpty || !declarationBlocks.last) && !source.substring(preludeStart, index).trimLeft().startsWith('@')) {
      final Match? identifier = svgCssIdentifier.matchAsPrefix(source, index + 1);
      if (identifier == null) {
        index++;
      } else {
        final String id = decodeSvgCssEscapes(identifier[0]!);
        final String updated = replace(id);
        output.write(updated == id ? source.substring(index, identifier.end) : '#${_cssIdentifier(updated)}');
        index = identifier.end;
        continue;
      }
    } else {
      final String char = source[index++];
      if (stylesheet && char == '{') {
        final String prelude = source.substring(preludeStart, start).replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').trimLeft();
        final bool groupingRule = RegExp(r'^@(media|supports|layer|container|document|scope|(?:-\w+-)?keyframes)\b', caseSensitive: false).hasMatch(prelude);
        declarationBlocks.add(!groupingRule);
        preludeStart = index;
      } else if (stylesheet && char == '}') {
        if (declarationBlocks.isNotEmpty) {
          declarationBlocks.removeLast();
        }
        preludeStart = index;
      } else if (stylesheet && char == ';') {
        preludeStart = index;
      } else if (char == '\\' && index < source.length) {
        index++;
      }
    }
    output.write(source.substring(start, index));
  }
  return output.toString();
}

/// Advances over a CSS string, ignoring escaped delimiters.
int _stringEnd(String source, int start) {
  final String quote = source[start];
  int index = start + 1;
  while (index < source.length) {
    if (source[index] == '\\') {
      index += 2;
    } else if (source[index++] == quote) {
      return index;
    }
  }
  return source.length;
}

/// Whether an explicit nonempty XML base makes fragment resolution host-specific.
bool svgHasExplicitBase(XmlElement element) =>
    [element, ...element.ancestors.whereType<XmlElement>()].any((node) => (node.getAttribute('base', namespaceUri: 'http://www.w3.org/XML/1998/namespace') ?? '').isNotEmpty);
