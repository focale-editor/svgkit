import 'dart:convert';
import 'dart:typed_data';

import 'package:svgkit/src/model/svg_document.dart';
import 'package:zcodec/zcodec.dart';

/// Reads UTF-8, UTF-16 and Latin-1 SVG/SVGZ; writes UTF-8 SVG or SVGZ.
final class SvgCodec extends Codec<SvgDocument, List<int>> {
  /// Limits shared by both conversion directions.
  final SvgLimits limits;

  /// Whether encoded output uses the SVGZ gzip envelope.
  final bool compressed;

  /// Creates a complete-document codec.
  const SvgCodec({this.limits = const SvgLimits(), this.compressed = false});

  @override
  SvgDecoder get decoder => SvgDecoder(limits: limits);

  @override
  SvgEncoder get encoder => SvgEncoder(limits: limits, compressed: compressed);

  @override
  Uint8List encode(SvgDocument input) => encoder.convert(input);
}

/// Decodes SVG bytes without using file extensions or performing I/O.
final class SvgDecoder extends Converter<List<int>, SvgDocument> {
  /// Resource ceilings for both envelopes and XML.
  final SvgLimits limits;

  /// Creates a bounded SVG decoder.
  const SvgDecoder({this.limits = const SvgLimits()});

  @override
  SvgDocument convert(List<int> input) {
    if (input.length > limits.maxBytes) {
      throw const FormatException('SVG input exceeds the byte limit.');
    }
    final List<int> bytes = input.length >= 2 && input[0] == 0x1f && input[1] == 0x8b ? GzipDecoder(maxOutputBytes: limits.maxBytes).convert(input) : input;
    final String source = _decodeXml(bytes);
    return SvgDocument.parse(source: source, limits: limits);
  }
}

/// Encodes XML without changing text-node whitespace.
final class SvgEncoder extends Converter<SvgDocument, List<int>> {
  /// Resource ceilings for serialized XML.
  final SvgLimits limits;

  /// Whether output uses gzip via ZCodec.
  final bool compressed;

  /// Creates an SVG or SVGZ encoder.
  const SvgEncoder({this.limits = const SvgLimits(), this.compressed = false});

  @override
  Uint8List convert(SvgDocument input) {
    // UTF-16 input must not retain a now-incorrect encoding declaration.
    final String source = input.toXmlString().replaceFirstMapped(
      RegExp(r'''^(<\?xml\s+[^?]*encoding\s*=\s*)["'][^"']+["']'''),
      (match) => '${match[1]}"UTF-8"',
    );
    SvgDocument.parse(source: source, limits: limits);
    final Uint8List bytes = utf8.encode(source);
    if (bytes.length > limits.maxBytes) {
      throw const FormatException('SVG output exceeds the byte limit.');
    }
    final Uint8List output = compressed ? const GzipEncoder().convert(bytes) : bytes;
    if (output.length > limits.maxBytes) {
      throw const FormatException('SVG envelope exceeds the output byte limit.');
    }
    return output;
  }
}

/// Honors XML's declared byte encoding, with strict Unicode validation.
String _decodeXml(List<int> bytes) {
  final bool little = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;
  final bool big = bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff;
  if (!little && !big) {
    // XML declarations are ASCII-compatible in both UTF-8 and Latin-1. Inspect
    // the declaration before interpreting non-ASCII text, never by trial decode.
    int declarationEnd = 0;
    if (bytes.length >= 5 && bytes[0] == 60 && bytes[1] == 63 && bytes[2] == 120 && bytes[3] == 109 && bytes[4] == 108) {
      for (int index = 5; index + 1 < bytes.length; index++) {
        if (bytes[index] == 63 && bytes[index + 1] == 62) {
          declarationEnd = index + 2;
          break;
        }
      }
    }
    final String prefix = latin1.decode(bytes.take(declarationEnd).toList());
    final String? declared = _declaredEncoding(prefix);
    if (declared == 'ISO-8859-1') {
      return latin1.decode(bytes);
    }
    final String source = utf8.decode(bytes);
    _validateEncoding(source, utf16: false);
    return source;
  }
  if (bytes.length.isOdd) {
    throw const FormatException('Truncated UTF-16 SVG.');
  }
  final List<int> units = [];
  for (int index = 2; index < bytes.length; index += 2) {
    units.add(little ? bytes[index] | bytes[index + 1] << 8 : bytes[index] << 8 | bytes[index + 1]);
  }
  for (int index = 0; index < units.length; index++) {
    final int unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= units.length || units[index] < 0xdc00 || units[index] > 0xdfff) {
        throw const FormatException('Invalid UTF-16 surrogate.');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Unpaired UTF-16 surrogate.');
    }
  }
  final String source = String.fromCharCodes(units);
  _validateEncoding(source, utf16: true, little: little);
  return source;
}

/// Rejects declarations that would reinterpret bytes under another encoding.
void _validateEncoding(String source, {required bool utf16, bool little = false}) {
  final String? encoding = _declaredEncoding(source);
  if (encoding == null) {
    return;
  }
  final bool supported = utf16 ? encoding == 'UTF-16' || encoding == (little ? 'UTF-16LE' : 'UTF-16BE') : encoding == 'UTF-8';
  if (!supported) {
    throw FormatException('Unsupported or mismatched SVG encoding: $encoding.');
  }
}

/// Reads the XML declaration without interpreting body bytes as text.
String? _declaredEncoding(String source) => RegExp(r'''^<\?xml\s+[^?]*encoding\s*=\s*["']([^"']+)["']''').firstMatch(source)?[1]?.toUpperCase();
