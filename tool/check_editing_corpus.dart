import 'dart:convert';
import 'dart:io';

import 'package:svgkit/svgkit.dart';

/// Exercises editing APIs on pinned external documents and emits render inputs.
Future<void> main() async {
  final Map<String, Object?> manifest = (jsonDecode(await File('test/corpus/manifest.json').readAsString()) as Map).cast<String, Object?>();
  final List<Object?> entries = (manifest['files']! as List).cast<Object?>();
  final Directory output = Directory('test/corpus/output/editing');
  await output.create(recursive: true);
  final List<Map<String, Object?>> report = [];
  int failures = 0;
  for (final Object? raw in entries) {
    final Map<String, Object?> entry = (raw! as Map).cast<String, Object?>();
    if (entry['expected'] != 'accept') {
      continue;
    }
    final String file = entry['file']! as String;
    try {
      final SvgDocument document = const SvgCodec().decode(await File('test/corpus/files/$file').readAsBytes());
      final SvgEditor editor = SvgEditor(document: document);
      int paths = 0;
      int commands = 0;
      int transforms = 0;
      int points = 0;
      final List<Map<String, String>> preserved = [];
      for (final SvgEditableElement element in editor.elements) {
        if (element.namespace != svgNamespace && element.namespace != null) {
          continue;
        }
        if (element.name == 'path' && element.attribute(name: 'd') != null) {
          try {
            final SvgPathData normalized = element.pathData.normalized();
            element.setPathData(value: normalized);
            paths++;
            commands += normalized.commands.length;
          } on FormatException catch (error) {
            // W3C error-recovery tests can contain intentionally invalid data.
            preserved.add({'element': element.id ?? element.name, 'attribute': 'd', 'reason': '$error'});
          }
        }
        for (final String name in ['transform', 'gradientTransform', 'patternTransform']) {
          if (element.attribute(name: name) != null) {
            try {
              element.setTransforms(
                value: element.transforms(attribute: name),
                attribute: name,
              );
              transforms++;
            } on FormatException catch (error) {
              preserved.add({'element': element.id ?? element.name, 'attribute': name, 'reason': '$error'});
            }
          }
        }
        if (element.name == 'polyline' || element.name == 'polygon') {
          try {
            element.setPoints(value: element.points);
            points++;
          } on FormatException catch (error) {
            preserved.add({'element': element.id ?? element.name, 'attribute': 'points', 'reason': '$error'});
          }
        }
        if (element.attribute(name: 'style') != null) {
          try {
            // Re-applying the preserved style must not drop unknown declarations.
            element.setStyle(value: element.style);
          } on FormatException catch (error) {
            preserved.add({'element': element.id ?? element.name, 'attribute': 'style', 'reason': '$error'});
          }
        }
      }
      final SvgDocument edited = editor.build();
      final SvgDocument reopened = const SvgCodec().decode(const SvgCodec(compressed: true).encode(edited));
      if (edited.toXmlString() != reopened.toXmlString()) {
        throw StateError('Edited SVGZ round-trip changed markup.');
      }
      await File('${output.path}/$file').writeAsBytes(const SvgCodec().encode(reopened));
      report.add({'file': file, 'paths': paths, 'commands': commands, 'transforms': transforms, 'pointLists': points, 'preservedSyntax': preserved});
    } on Object catch (error) {
      failures++;
      report.add({'file': file, 'failure': '$error'});
      stderr.writeln('$file: $error');
    }
  }
  await File('${output.path}/report.json').writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  await _writeAuthoringScenario(output: output);
  stdout.writeln('SVG editing corpus: ${report.length - failures}/${report.length} documents; malformed/unsupported attributes reported and retained.');
  if (failures > 0) {
    exitCode = 1;
  }
}

/// Applies visible edits whose expected result is independently authored SVG.
Future<void> _writeAuthoringScenario({required Directory output}) async {
  final SvgDocument input = const SvgCodec().decode(await File('test/fixtures/editing_input.svg').readAsBytes());
  final SvgDocument edited = input.edit((editor) {
    final SvgEditableElement gradient = editor.elementById(id: 'paint')!;
    editor.renameId(element: gradient, id: 'sky');
    gradient.children.last.setAttribute(name: 'stop-color', value: 'gold');
    editor.elementById(id: 'blur')!.children.single.setAttribute(name: 'stdDeviation', value: '0.4');
    final SvgEditableElement panel = editor.elementById(id: 'panel')!;
    panel.setLength(name: 'width', value: SvgLength(value: 90));
    panel.setStyleProperty(name: 'stroke', value: 'purple');
    panel.setStyleProperty(name: 'stroke-width', value: '3');
    editor.elementById(id: 'caption')!.replaceTextRun(index: 0, value: 'After ');
    editor.elementById(id: 'word')!.setText(value: 'SVG');
    final SvgEditableElement curve = editor.elementById(id: 'curve')!;
    final SvgPathData normalized = curve.pathData.normalized();
    curve.setPathData(value: normalized.replace(start: 1, end: 2, replacement: [SvgPathCommand.quadraticTo(x1: 20, y1: 55, x: 40, y: 95)]));
    editor.elementById(id: 'art')!.setTransforms(value: SvgTransformList(transforms: [SvgTransform.translate(x: 15, y: 10)]));
    final SvgEditableElement instance = editor.elementById(id: 'copy')!;
    instance.setHref(value: '#panel');
    instance.setLength(name: 'y', value: SvgLength(value: 20));
    final SvgEditableElement circle = editor.circle(radius: SvgLength(value: 12), centerX: SvgLength(value: 200), centerY: SvgLength(value: 90));
    circle.setAttribute(name: 'fill', value: 'teal');
    editor.root.insert(child: circle);
    final SvgEditableElement second = editor.duplicate(element: circle);
    second.setLength(name: 'cy', value: SvgLength(value: 120));
    editor.group(selection: [circle, second]).setAttribute(name: 'opacity', value: '0.6');
  });
  // Saving to SVGZ and reopening also exercises the actual authoring boundary.
  final SvgDocument reopened = const SvgCodec().decode(const SvgCodec(compressed: true).encode(edited));
  await File('${output.path}/authoring.svg').writeAsBytes(const SvgCodec().encode(reopened));
}
