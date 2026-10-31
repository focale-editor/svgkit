/// Portable SVG and SVGZ documents, independent of a rendering engine.
library;

export 'package:svgkit/src/codec/svg_codec.dart';
export 'package:svgkit/src/editing/svg_authoring.dart';
export 'package:svgkit/src/editing/svg_editor.dart';
export 'package:svgkit/src/editing/svg_references.dart' show SvgLocalReference, svgXlinkNamespace;
export 'package:svgkit/src/model/svg_document.dart';
export 'package:svgkit/src/values/svg_aspect_ratio.dart';
export 'package:svgkit/src/values/svg_path.dart';
export 'package:svgkit/src/values/svg_style.dart';
export 'package:svgkit/src/values/svg_transform.dart';
export 'package:xml/xml.dart' show XmlAttribute, XmlCDATA, XmlComment, XmlDocument, XmlElement, XmlName, XmlNode, XmlStringExtension, XmlText;
