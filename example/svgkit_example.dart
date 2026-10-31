import 'dart:convert';
import 'dart:typed_data';

import 'package:svgkit/svgkit.dart';

/// Edits SVG markup and performs an SVGZ round trip without a renderer.
void main() {
  final SvgDocument original = const SvgCodec().decode(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="80"><path id="triangle" d="M10 70L50 10L90 70Z" fill="red"/></svg>'));
  final XmlDocument xml = original.xml;
  xml.rootElement.setAttribute('viewBox', '0 0 100 80');
  final SvgDocument edited = SvgDocument.fromXml(document: xml);
  final Uint8List compressed = const SvgCodec(compressed: true).encode(edited);
  final SvgDocument reopened = const SvgCodec().decode(compressed);
  print('${reopened.width!.pixels} × ${reopened.height!.pixels}; SVGZ: ${compressed.length} bytes');
}
