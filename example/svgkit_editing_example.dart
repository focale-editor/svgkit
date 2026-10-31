import 'package:svgkit/svgkit.dart';

/// Authors reusable resources, edits path nodes and persists the result as SVGZ.
void main() {
  final SvgEditor editor = SvgEditor.empty(width: SvgLength(value: 200), height: SvgLength(value: 120), viewBox: SvgViewBox(minX: 0, minY: 0, width: 200, height: 120));
  final SvgEditableElement gradient = editor.linearGradient(
    id: 'paint',
    stops: [
      SvgGradientStop(offset: 0, color: '#4e8cff'),
      SvgGradientStop(offset: 1, color: '#b9f0ff'),
    ],
  );
  editor.definitions.insert(child: gradient);
  final SvgEditableElement shape = editor.path(
    id: 'outline',
    data: SvgPathData.parse(source: 'm10 10 h140 v70 h-140 z'),
  );
  shape.setReference(property: 'fill', target: gradient);
  shape.setStyleProperty(name: 'stroke', value: '#152c58');
  shape.setStyleProperty(name: 'stroke-width', value: '2');
  editor.root.insert(child: shape);
  final SvgEditableElement caption = editor.text(value: 'Editable SVG', x: SvgLength(value: 10), y: SvgLength(value: 105));
  editor.root.insert(child: caption);
  final SvgDocument original = editor.build();
  final SvgDocument edited = original.edit((session) {
    final SvgEditableElement path = session.elementById(id: 'outline')!;
    final SvgPathData normalized = path.pathData.normalized();
    path.setPathData(value: normalized.replace(start: 1, end: 2, replacement: [SvgPathCommand.lineTo(x: 180, y: 10)]));
    path.setTransforms(value: SvgTransformList(transforms: [SvgTransform.translate(x: 3)]));
    session.renameId(
      element: session.elementById(id: 'paint')!,
      id: 'sky',
    );
  });
  final List<int> bytes = const SvgCodec(compressed: true).encode(edited);
  final SvgDocument reopened = const SvgCodec().decode(bytes);
  print('${reopened.viewBox!.width} × ${reopened.viewBox!.height}; ${bytes.length} SVGZ bytes; ${reopened.elementById('outline')!.getAttribute('d')}');
}
