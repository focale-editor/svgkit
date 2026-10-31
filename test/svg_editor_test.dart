import 'package:checks/checks.dart';
import 'package:svgkit/svgkit.dart';
import 'package:test/test.dart';

/// Exercises transactions, structural authoring, ownership and SVGZ persistence.
void main() {
  test('document edits isolate originals, returned snapshots and later sessions', () {
    final SvgDocument original = SvgDocument.parse(source: '<svg><rect id="r" width="10"/></svg>');
    final SvgEditor editor = SvgEditor(document: original);
    final SvgEditableElement rectangle = editor.elementById(id: 'r')!;
    rectangle.setLength(
      name: 'width',
      value: SvgLength(value: 25, unit: 'mm'),
    );
    final SvgDocument first = editor.build();
    rectangle.setLength(name: 'width', value: SvgLength(value: 50));
    check(original.elementById('r')!.getAttribute('width')).equals('10');
    check(first.elementById('r')!.getAttribute('width')).equals('25mm');
    check(editor.build().elementById('r')!.getAttribute('width')).equals('50');
    check(
      () => original.edit((editor) {
        editor.elementById(id: 'r')!.remove();
        throw StateError('abort');
      }),
    ).throws<StateError>();
    check(original.elementById('r')).isNotNull();
  });

  test('creates all basic geometry and persists typed edits through SVGZ', () {
    final SvgEditor editor = SvgEditor.empty(width: SvgLength(value: 100), height: SvgLength(value: 80), viewBox: SvgViewBox(minX: 0, minY: 0, width: 100, height: 80));
    final SvgEditableElement rectangle = editor.rectangle(id: 'rect', width: SvgLength(value: 30), height: SvgLength(value: 20), radiusX: SvgLength(value: 3));
    final SvgEditableElement path = editor.path(
      id: 'path',
      data: SvgPathData.parse(source: 'M0 0L10 10'),
    );
    final List<SvgEditableElement> shapes = [
      rectangle,
      path,
      editor.circle(radius: SvgLength(value: 5)),
      editor.ellipse(radiusX: SvgLength(value: 5), radiusY: SvgLength(value: 2)),
      editor.line(x1: SvgLength(value: 0), y1: SvgLength(value: 0), x2: SvgLength(value: 4), y2: SvgLength(value: 5)),
      editor.polygon(points: SvgPointList.parse(source: '0 0 10 0 5 5')),
      editor.polygon(points: SvgPointList.parse(source: '0 0 4 4'), closed: false),
    ];
    for (final SvgEditableElement shape in shapes) {
      editor.root.insert(child: shape);
    }
    path.setPathData(value: path.pathData.replace(start: 1, end: 2, replacement: [SvgPathCommand.cubicTo(x1: 2, y1: 3, x2: 4, y2: 5, x: 6, y: 7)]));
    rectangle.setClasses(values: ['shape', 'selected', 'shape']);
    rectangle.setTransforms(value: rectangle.transforms().append(transform: SvgTransform.translate(x: 4, y: 5)));
    rectangle.setStyleProperty(name: 'fill', value: 'red');
    rectangle.setStyleProperty(name: 'stroke', value: 'black');
    rectangle.removeStyleProperty(name: 'stroke');
    final SvgDocument result = const SvgCodec().decode(const SvgCodec(compressed: true).encode(editor.build()));
    check(result.width!.value).equals(100);
    check(result.viewBox!.height).equals(80);
    check(result.elementById('path')!.getAttribute('d')).equals('M0 0 C2 3 4 5 6 7');
    check(result.elementById('rect')!.getAttribute('class')).equals('shape selected');
    check(rectangle.classes.length).equals(2);
    check(rectangle.style.property(name: 'fill')!.value).equals('red');
    check(rectangle.style.property(name: 'stroke')).isNull();
    check(rectangle.length(name: 'rx')!.value).equals(3);
    check(() => editor.circle(radius: SvgLength(value: -1))).throws<FormatException>();
    check(() => rectangle.setClasses(values: ['two tokens'])).throws<ArgumentError>();
  });

  test('moves elements by final index and retains surrounding mixed content', () {
    final SvgEditor editor = _editor('<svg>before<g id="a"/>middle<g id="b"/><g id="c"/>after</svg>');
    final SvgEditableElement a = editor.elementById(id: 'a')!;
    editor.root.insert(child: a, index: 2);
    check(editor.root.children.map((element) => element.id).toList()).deepEquals(['b', 'c', 'a']);
    check(editor.root.text).equals('beforemiddleafter');
    check(identical(a, editor.elementById(id: 'a'))).isTrue();
    a.remove();
    check(a.isConnected).isFalse();
    editor.root.insert(child: a, index: 0);
    check(a.isConnected).isTrue();
    check(editor.root.children.first.id).equals('a');
  });

  test('rejects cross-session ownership, invalid indices and ancestry cycles before moving', () {
    final SvgEditor editor = _editor('<svg><g id="a"><g id="b"/></g></svg>');
    final SvgEditableElement a = editor.elementById(id: 'a')!;
    final SvgEditableElement b = editor.elementById(id: 'b')!;
    check(() => b.insert(child: a)).throws<ArgumentError>();
    check(() => a.insert(child: a)).throws<ArgumentError>();
    check(() => a.insert(child: editor.root)).throws<ArgumentError>();
    check(() => editor.root.insert(child: a, index: 99)).throws<RangeError>();
    check(() => editor.root.insert(child: SvgEditor.empty().createElement(name: 'g'))).throws<ArgumentError>();
    check(() => editor.root.remove()).throws<StateError>();
    check(a.parent).equals(editor.root);
  });

  test('preserves namespace meanings when moving across different default namespaces', () {
    final SvgEditor editor = _editor('<s:svg xmlns:s="http://www.w3.org/2000/svg" xmlns:m="urn:metadata"><s:g id="a"><m:data id="d" m:value="kept"/></s:g><s:g id="b" xmlns:m="urn:other"/></s:svg>');
    final SvgEditableElement data = editor.elementById(id: 'd')!;
    editor.elementById(id: 'b')!.insert(child: data);
    check(data.namespace).equals('urn:metadata');
    check(data.attribute(name: 'value', namespace: 'urn:metadata')).equals('kept');
    final SvgDocument built = editor.build();
    check(built.elementById('d')!.namespaceUri).equals('urn:metadata');
    final SvgEditableElement unnamespaced = editor.createElement(name: 'foreign', namespace: '');
    editor.root.insert(child: unnamespaced);
    check(unnamespaced.namespace).isNull();
  });

  test('extension attributes declare namespaces and reject conflicting prefixes', () {
    final SvgEditor editor = SvgEditor.empty();
    editor.root.setNamespacedAttribute(name: 'label', prefix: 'app', namespace: 'urn:app', value: 'Label');
    check(editor.build().root.getAttribute('label', namespaceUri: 'urn:app')).equals('Label');
    check(() => editor.root.setNamespacedAttribute(name: 'data', prefix: 'app', namespace: 'urn:other', value: 'x')).throws<ArgumentError>();
    check(() => editor.root.setNamespacedAttribute(name: 'data', prefix: 'xml', namespace: 'urn:other', value: 'x')).throws<ArgumentError>();
    check(() => editor.createElement(name: 'a:b')).throws<ArgumentError>();
  });

  test('import reconstructs inherited namespaces from detached document lookups', () {
    final SvgDocument source = SvgDocument.parse(source: '<svg xmlns="http://www.w3.org/2000/svg" xmlns:m="urn:meta"><g id="g"><m:data m:label="x"/></g></svg>');
    final SvgEditor editor = SvgEditor.empty();
    editor.root.insert(child: editor.importElement(element: source.elementById('g')!, remapIds: false));
    final XmlElement child = editor.build().elementById('g')!.childElements.single;
    check(child.namespaceUri).equals('urn:meta');
    check(child.getAttribute('label', namespaceUri: 'urn:meta')).equals('x');
  });

  test('grouping uses document order and preserves interstitial comments', () {
    final SvgEditor editor = _editor('<svg><rect id="a"/><!-- gap --><circle id="b"/><path id="c"/></svg>');
    final SvgEditableElement a = editor.elementById(id: 'a')!;
    final SvgEditableElement b = editor.elementById(id: 'b')!;
    final SvgEditableElement group = editor.group(selection: [b, a], id: 'group');
    check(group.children.map((element) => element.id).toList()).deepEquals(['a', 'b']);
    check(group.xml.toXmlString().contains('<!-- gap -->')).isTrue();
    check(editor.root.children.map((element) => element.id).toList()).deepEquals(['group', 'c']);
    editor.ungroup(group: group);
    check(editor.root.children.map((element) => element.id).toList()).deepEquals(['a', 'b', 'c']);
    check(group.isConnected).isFalse();
  });

  test('noncontiguous grouping and effect-dropping ungrouping fail explicitly', () {
    final SvgEditor editor = _editor('<svg><rect id="a"/><circle id="b"/><path id="c"/></svg>');
    check(
      () => editor.group(
        selection: [
          editor.elementById(id: 'a')!,
          editor.elementById(id: 'c')!,
        ],
      ),
    ).throws<ArgumentError>();
    final SvgEditableElement group = editor.group(selection: [editor.elementById(id: 'a')!]);
    group.setAttribute(name: 'opacity', value: '.5');
    check(() => editor.ungroup(group: group)).throws<StateError>();
    editor.ungroup(group: group, discardGroupAttributes: true);
    check(editor.elementById(id: 'a')!.parent).equals(editor.root);
  });

  test('edits rich text runs without removing spans, comments or text paths', () {
    final SvgEditor editor = _editor(
      '<svg><text id="t">Hello <tspan id="span" font-weight="bold">world</tspan><!--keep--><![CDATA[!]]><textPath href="#p">curve</textPath></text><path id="p"/></svg>',
    );
    final SvgEditableElement text = editor.elementById(id: 't')!;
    text.replaceTextRun(index: 0, value: 'Bonjour ');
    editor.elementById(id: 'span')!.setText(value: 'monde');
    text.replaceTextRun(index: 1, value: ' !');
    text.appendText(value: ' fin');
    check(text.text).equals('Bonjour monde !curve fin');
    check(text.children.length).equals(2);
    check(text.children.first.attribute(name: 'font-weight')).equals('bold');
    check(text.xml.toXmlString().contains('<!--keep-->')).isTrue();
    text.setText(value: '<plain & escaped>');
    check(text.children).isEmpty();
    check(editor.build().elementById('t')!.innerText).equals('<plain & escaped>');
  });

  test('replaces arbitrary mixed content with copies and preserves extension data', () {
    final SvgEditor editor = _editor('<svg><metadata id="m"><old/></metadata></svg>');
    final XmlDocument source = XmlDocument.parse('<root xmlns:x="urn:x"><x:value key="v"/><!--kept-->text</root>');
    final SvgEditableElement metadata = editor.elementById(id: 'm')!;
    metadata.replaceContent(nodes: source.rootElement.children);
    source.rootElement.children.clear();
    check(metadata.children.single.namespace).equals('urn:x');
    check(metadata.text).equals('text');
    check(metadata.xml.toXmlString().contains('<!--kept-->')).isTrue();
    final XmlElement detached = metadata.xml;
    detached.setAttribute('id', 'changed');
    check(metadata.id).equals('m');
  });

  test('authors editable paint servers, effects, instances and images', () {
    final SvgEditor editor = SvgEditor.empty();
    final SvgEditableElement gradient = editor.linearGradient(
      id: 'gradient',
      stops: [
        SvgGradientStop(offset: 0, color: 'red'),
        SvgGradientStop(offset: 1, color: 'blue', opacity: .5),
      ],
    );
    final SvgEditableElement radial = editor.radialGradient(id: 'radial', href: '#gradient', focalRadius: SvgLength(value: 0));
    final SvgEditableElement mask = editor.mask(id: 'mask');
    final SvgEditableElement clip = editor.clipPath(id: 'clip');
    final SvgEditableElement filter = editor.filter(id: 'filter');
    filter.insert(
      child: editor.createElement(name: 'feGaussianBlur', attributes: {'stdDeviation': '2', 'result': 'blur'}),
    );
    final SvgEditableElement pattern = editor.pattern(id: 'pattern', width: SvgLength(value: .5), height: SvgLength(value: .5));
    final SvgEditableElement symbol = editor.symbol(id: 'symbol');
    final SvgEditableElement marker = editor.marker(id: 'marker');
    for (final SvgEditableElement resource in [gradient, radial, mask, clip, filter, pattern, symbol, marker]) {
      editor.definitions.insert(child: resource);
    }
    gradient.children.last.setStyleProperty(name: 'stop-color', value: 'green');
    final SvgEditableElement circle = editor.circle(radius: SvgLength(value: 10));
    circle.setReference(property: 'fill', target: gradient);
    circle.setReference(property: 'clip-path', target: clip);
    editor.root.insert(child: circle);
    final SvgEditableElement instance = editor.use(href: '#symbol');
    editor.root.insert(child: instance);
    editor.root.insert(
      child: editor.image(href: 'data:image/png;base64,AA==', width: SvgLength(value: 1), height: SvgLength(value: 1)),
    );
    check(instance.hrefTarget).equals(symbol);
    check(editor.danglingReferences).isEmpty();
    check(editor.build().elementById('filter')!.childElements.single.getAttribute('stdDeviation')).equals('2');
    check(editor.definitions.children.length).equals(8);
    check(() => SvgGradientStop(offset: 2, color: 'red')).throws<FormatException>();
  });

  test('validation reports ambiguous IDs and enforces final snapshot limits', () {
    final SvgEditor editor = _editor('<svg><rect id="a"/><circle id="a"/></svg>');
    check(() => editor.elementById(id: 'a')).throws<StateError>();
    check(editor.build).throws<StateError>();
    check(editor.build(validateIds: false).root.childElements.length).equals(2);
    final SvgDocument original = SvgDocument.parse(source: '<svg/>');
    check(() => original.edit((editor) => editor.root.setText(value: 'x' * 100), limits: const SvgLimits(maxBytes: 50))).throws<FormatException>();
    check(original.root.innerText).isEmpty();
  });

  test('preflights edited and imported trees before recursive serialization', () {
    final SvgEditor editor = SvgEditor(
      document: SvgDocument.parse(source: '<svg/>'),
      limits: const SvgLimits(maxDepth: 3),
    );
    SvgEditableElement parent = editor.root;
    for (int index = 0; index < 4; index++) {
      final SvgEditableElement child = editor.createElement(name: 'g');
      parent.insert(child: child);
      parent = child;
    }
    check(editor.build).throws<FormatException>();
    check(() => editor.importElement(element: XmlDocument.parse('<g><g><g><g/></g></g></g>').rootElement)).throws<FormatException>();
    check(() => SvgEditor.empty(limits: const SvgLimits(maxDepth: 0))).throws<ArgumentError>();
  });
}

/// Creates an authoring session from a concise inline fixture.
SvgEditor _editor(String source) => SvgEditor(document: SvgDocument.parse(source: source));
