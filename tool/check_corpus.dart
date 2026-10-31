import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:svgkit/svgkit.dart';

/// Checks the explicitly downloaded corpus and emits files for independent QA.
Future<void> main() async {
  final File manifestFile = File('test/corpus/manifest.json');
  final Map<String, Object?> manifest = (jsonDecode(await manifestFile.readAsString()) as Map).cast<String, Object?>();
  final List<Object?> entries = (manifest['files']! as List).cast<Object?>();
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  await Directory('test/corpus/output').create(recursive: true);
  for (final Object? value in entries) {
    final Map<String, Object?> entry = (value! as Map).cast<String, Object?>();
    final String name = entry['file']! as String;
    final bool rejected = entry['expected'] == 'reject';
    try {
      final Uint8List bytes = await File('test/corpus/files/$name').readAsBytes();
      final SvgDocument decoded = const SvgCodec().decode(bytes);
      final Uint8List encoded = const SvgCodec().encode(decoded);
      final SvgDocument reopened = const SvgCodec().decode(encoded);
      if (decoded.toXmlString() != reopened.toXmlString()) {
        throw StateError('XML round-trip changed');
      }
      if (rejected) {
        throw StateError('Expected rejection but file decoded');
      }
      await File('test/corpus/output/$name').writeAsBytes(encoded);
      report.add({'file': name, 'status': 'accepted', 'bytes': encoded.length});
    } on FormatException catch (error) {
      report.add({'file': name, 'status': rejected ? 'rejected' : 'failed', 'error': error.toString()});
      if (!rejected) {
        failures++;
        stdout.writeln('$name: $error');
      }
    } on Object catch (error) {
      failures++;
      report.add({'file': name, 'status': 'failed', 'error': error.toString()});
      stdout.writeln('$name: $error');
    }
  }
  await File('test/corpus/output/report.json').writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('SvgKit: ${entries.length - failures}/${entries.length} expected outcomes');
  if (failures != 0) {
    exitCode = 1;
  }
}
