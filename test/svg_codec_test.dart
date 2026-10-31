import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:svgkit/svgkit.dart';
import 'package:test/test.dart';
import 'package:zcodec/zcodec.dart';

/// Exercises document preservation, editing, encodings and parser boundaries.
void main() {
  const String source = '''<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:custom="urn:author" width="2.54cm" height="50%" viewBox="-10 -20 100 200">
<defs><linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient></defs>
<custom:data custom:key="keep"><![CDATA[author <data>]]></custom:data>
<g transform="translate(2,3)"><path id="shape" d="M0 0C1 2 3 4 5 6Z" fill="url(#g)"/></g>
<text xml:space="preserve"> a <tspan>b</tspan> c </text><!--keep-->
</svg>''';

  test('preserves unknown namespaces, graphics, metadata and text whitespace', () {
    final SvgDocument document = const SvgCodec().decode(utf8.encode(source));
    final SvgDocument reopened = const SvgCodec().decode(const SvgCodec().encode(document));
    check(reopened.toXmlString()).equals(document.toXmlString());
    check(reopened.width!.pixels).equals(96);
    check(reopened.height!.pixels).isNull();
    check(reopened.viewBox!.minX).equals(-10);
    check(reopened.elementById('shape')!.getAttribute('fill')).equals('url(#g)');
    check(reopened.toXmlString()).contains(' a <tspan>b</tspan> c ');
  });

  test('supports detached XML editing without mutating an earlier snapshot', () {
    final SvgDocument original = SvgDocument.parse(source: source);
    final XmlDocument edited = original.xml;
    edited.rootElement.setAttribute('width', '42px');
    final SvgDocument replacement = SvgDocument.fromXml(document: edited);
    check(original.width!.pixels).equals(96);
    check(replacement.width!.pixels).equals(42);
    final XmlElement root = original.root;
    root.setAttribute('height', '99');
    check(original.height!.unit).equals('%');
  });

  test('detects SVGZ by magic and bounds decompression', () {
    final SvgDocument document = SvgDocument.parse(source: source);
    final Uint8List bytes = const SvgCodec(compressed: true).encode(document);
    check(bytes.take(2)).deepEquals([31, 139]);
    check(const SvgCodec().decode(bytes).toXmlString()).equals(document.toXmlString());
    final Uint8List bomb = const GzipEncoder().convert(utf8.encode('<svg>${' ' * 10000}</svg>'));
    check(() => const SvgCodec(limits: SvgLimits(maxBytes: 1000)).decode(bomb)).throws<FormatException>();
  });

  for (final bool little in [true, false]) {
    test('reads UTF-16 ${little ? 'LE' : 'BE'} and emits a UTF-8 declaration', () {
      const String text = '<?xml version="1.0" encoding="UTF-16"?><svg><text>été 😀</text></svg>';
      final List<int> bytes = [
        if (little) ...[255, 254] else ...[254, 255],
        for (final int unit in text.codeUnits) ...little ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
      ];
      final SvgDocument document = const SvgCodec().decode(bytes);
      final String output = utf8.decode(const SvgCodec().encode(document));
      check(output).contains('encoding="UTF-8"');
      check(output).contains('été 😀');
    });
  }

  test('preserves external declarations without opening their URLs', () {
    const String xml = '<!DOCTYPE svg SYSTEM "file:///no-such-file"><svg xmlns="http://www.w3.org/2000/svg"/>';
    check(SvgDocument.parse(source: xml).toXmlString()).contains('file:///no-such-file');
  });

  test('preserves active content as data; does not claim sanitization', () {
    final SvgDocument document = SvgDocument.parse(source: '<svg><script>throw "not executed";</script><image href="https://example.invalid/image"/></svg>');
    check(document.toXmlString()).contains('example.invalid');
  });

  test('supports prefixed SVG roots and root ID lookup', () {
    final SvgDocument document = SvgDocument.parse(source: '<s:svg xmlns:s="http://www.w3.org/2000/svg" id="root"/>');
    check(document.elementById('root')!.name.qualified).equals('s:svg');
    check(document.elementById('missing')).isNull();
  });

  for (final String invalid in ['<html/>', '<svg xmlns="urn:wrong"/>', '<svg><g></svg>', '<svg/><svg/>', '<!DOCTYPE svg [<!ENTITY a "hello">]><svg>&a;</svg>']) {
    test('rejects invalid root/XML or internal entities: $invalid', () {
      check(() => SvgDocument.parse(source: invalid)).throws<Exception>();
    });
  }

  test('enforces depth and event budgets before DOM construction', () {
    check(() => SvgDocument.parse(source: '<svg><g><g/></g></svg>', limits: const SvgLimits(maxDepth: 2))).throws<FormatException>();
    check(() => SvgDocument.parse(source: '<svg><g/><g/></svg>', limits: const SvgLimits(maxNodes: 2))).throws<FormatException>();
    check(() => SvgDocument.parse(source: '<svg/>', limits: const SvgLimits(maxDepth: 0))).throws<ArgumentError>();
  });

  test('rejects corrupt gzip and malformed UTF-16', () {
    check(() => const SvgCodec().decode([31, 139, 0])).throws<FormatException>();
    check(() => const SvgCodec().decode([255, 254, 0])).throws<FormatException>();
    check(() => const SvgCodec().decode([255, 254, 0, 216])).throws<FormatException>();
  });

  test('bounds UTF-8 output in bytes rather than code units', () {
    final SvgDocument document = SvgDocument.parse(source: '<svg>ééé</svg>');
    check(() => const SvgCodec(limits: SvgLimits(maxBytes: 15)).encode(document)).throws<FormatException>();
  });

  test('converts physical units and retains relative lengths', () {
    for (final String value in ['1in', '72pt', '6pc', '25.4mm', '2.54cm', '101.6q', '96px']) {
      check((SvgLength.parse(value: value).pixels! - 96).abs()).isLessThan(1e-12);
    }
    check(SvgLength.parse(value: '1.2e2%').value).equals(120);
    check(() => SvgLength.parse(value: 'calc(1px + 2px)')).throws<FormatException>();
    check(() => SvgLength(value: double.nan)).throws<FormatException>();
  });

  test('validates viewBox and retains zero-sized viewports', () {
    check(SvgViewBox.parse(value: '-1, -2, 0, 4').width).equals(0);
    check(() => SvgViewBox.parse(value: '0 0 -1 2')).throws<FormatException>();
    check(() => SvgViewBox.parse(value: '0 0 2')).throws<FormatException>();
    check(() => SvgViewBox.parse(value: '0 0 NaN 2')).throws<FormatException>();
  });

  test('composes with standard dart:convert codecs', () {
    final Codec<SvgDocument, String> codec = const SvgCodec().fuse(base64);
    check(codec.decode(codec.encode(SvgDocument.parse(source: '<svg/>'))).root.name.local).equals('svg');
  });
  test('rejects mismatched encodings and unbound root prefixes', () {
    check(() => const SvgCodec().decode([0xef, 0xbb, 0xbf, ...utf8.encode('<?xml version="1.0" encoding="ISO-8859-1"?><svg>é</svg>')])).throws<FormatException>();
    check(() => SvgDocument.parse(source: '<x:svg/>')).throws<FormatException>();
    check(() => SvgDocument.parse(source: '<svg>ééé</svg>', limits: const SvgLimits(maxBytes: 15))).throws<FormatException>();
  });

  test('declared Latin-1 retains non-ASCII text through UTF-8 and SVGZ output', () {
    const String text = '<?xml version="1.0" encoding="iso-8859-1"?><svg><text>été £</text></svg>';
    final SvgDocument document = const SvgCodec().decode(latin1.encode(text));
    check(document.root.innerText).equals('été £');
    for (final bool compressed in [false, true]) {
      final SvgDocument reopened = const SvgCodec().decode(SvgCodec(compressed: compressed).encode(document));
      check(reopened.root.innerText).equals('été £');
      check(reopened.toXmlString()).contains('encoding="UTF-8"');
    }
  });
}
