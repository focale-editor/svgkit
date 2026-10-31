import 'package:checks/checks.dart';
import 'package:svgkit/svgkit.dart';
import 'package:test/test.dart';

/// Verifies recognized static references and collision-free subtree duplication.
void main() {
  test('renames href, XLink, paint, timing and accessibility references', () {
    final SvgEditor editor = _editor('''<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/1999/xlink">
      <defs><linearGradient id="paint"/></defs><rect id="shape" fill="url( #paint )" style="stroke: URL('#paint');color:#paint" aria-labelledby="paint shape"/>
      <use id="instance" href="#shape" x:href="#shape"/>
      <animate begin="shape.click; shape.end+1s; 2s" end="shape.repeat(2)"/>
      <image href="external.svg#shape"/>
    </svg>''');
    editor.renameId(
      element: editor.elementById(id: 'paint')!,
      id: 'newPaint',
    );
    editor.renameId(
      element: editor.elementById(id: 'shape')!,
      id: 'newShape',
    );
    final SvgEditableElement shape = editor.elementById(id: 'newShape')!;
    check(shape.attribute(name: 'fill')).equals('url("#newPaint")');
    check(shape.attribute(name: 'aria-labelledby')).equals('newPaint newShape');
    check(shape.style.property(name: 'stroke')!.value).equals('url("#newPaint")');
    check(shape.style.property(name: 'color')!.value).equals('#paint');
    check(editor.elementById(id: 'instance')!.href).equals('#newShape');
    check(editor.elementById(id: 'instance')!.attribute(name: 'href', namespace: svgXlinkNamespace)).equals('#newShape');
    final SvgEditableElement animation = editor.elements.firstWhere((element) => element.name == 'animate');
    check(animation.attribute(name: 'begin')).equals('newShape.click; newShape.end+1s; 2s');
    check(animation.attribute(name: 'end')).equals('newShape.repeat(2)');
    check(editor.elements.firstWhere((element) => element.name == 'image').href).equals('external.svg#shape');
    check(editor.danglingReferences).isEmpty();
  });

  test('rewrites CSS ID selectors including escapes while preserving colors and strings', () {
    final SvgEditor editor = _editor(r'''<svg><rect id="abc"/><style><![CDATA[
      /* #abc url(#abc) */ #abc, #\61 bc:hover {fill:#abc;stroke:url('#abc');content:"#abc url(#abc)"}
      @media screen { #abc { fill: URL(#abc); } }
    ]]></style></svg>''');
    editor.renameId(
      element: editor.elementById(id: 'abc')!,
      id: 'new',
    );
    final String css = editor.elements.firstWhere((element) => element.name == 'style').text;
    check(css.contains('/* #abc url(#abc) */')).isTrue();
    check(css.contains('fill:#abc')).isTrue();
    check(css.contains('content:"#abc url(#abc)"')).isTrue();
    check(css.contains('#\\6e \\65 \\77 ')).isTrue();
    check(css.contains('url("#new")')).isTrue();
    check(editor.references.where((reference) => reference.targetId == 'abc')).isEmpty();
    check(editor.references.where((reference) => reference.targetId == 'new').length).equals(5);
  });

  test('handles percent-encoded IDs and escaped CSS URLs', () {
    final SvgEditor editor = _editor(r'''<svg><g id="été"/><use href="#%C3%A9t%C3%A9"/><rect fill="url(#\e9 t\e9 )"/></svg>''');
    editor.renameId(
      element: editor.elementById(id: 'été')!,
      id: 'été-2',
    );
    check(editor.root.children[1].href).equals('#%C3%A9t%C3%A9-2');
    check(editor.root.children[2].attribute(name: 'fill')).equals('url("#%C3%A9t%C3%A9-2")');
    check(editor.danglingReferences).isEmpty();
  });

  test('recognizes escaped URL function names without rewriting other identifiers', () {
    final SvgEditor editor = _editor(r'''<svg><g id="abc"/><style>#abc {fill:u\72l(#abc);--unused:éurl(#abc)} @supports (color:#abc) {#abc {fill:red}}</style></svg>''');
    editor.renameId(
      element: editor.elementById(id: 'abc')!,
      id: 'new',
    );
    final String css = editor.root.children.last.text;
    check(css.contains('fill:url("#new")')).isTrue();
    check(css.contains('éurl(#abc)')).isTrue();
    check(css.contains('@supports (color:#abc)')).isTrue();
  });

  test('duplicate remaps all subtree IDs and internal links without changing originals', () {
    final SvgEditor editor = _editor(
      '<svg><g id="group"><defs><linearGradient id="paint"/></defs><rect id="shape" fill="url(#paint)"/><use href="#shape"/><use href="#outside"/></g><g id="outside"/></svg>',
    );
    final SvgEditableElement original = editor.elementById(id: 'group')!;
    final SvgEditableElement clone = editor.duplicate(element: original);
    check(clone.id).equals('group-copy');
    check(editor.elementById(id: 'shape-copy')!.attribute(name: 'fill')).equals('url("#paint-copy")');
    check(clone.children[2].href).equals('#shape-copy');
    check(clone.children[3].href).equals('#outside');
    check(editor.elementById(id: 'shape')!.attribute(name: 'fill')).equals('url(#paint)');
    check(editor.duplicate(element: original).id).equals('group-copy-2');
    check(editor.danglingReferences).isEmpty();
    editor.build();
  });

  test('ID collisions and ambiguous subtree duplication fail before changing originals', () {
    final SvgEditor editor = _editor('<svg><g id="a"/><g id="b"/></svg>');
    check(
      () => editor.renameId(
        element: editor.elementById(id: 'a')!,
        id: 'b',
      ),
    ).throws<StateError>();
    check(
      () => editor.renameId(
        element: editor.elementById(id: 'a')!,
        id: 'bad id',
      ),
    ).throws<ArgumentError>();
    check(editor.elementById(id: 'a')).isNotNull();
    check(() => editor.importElement(element: XmlDocument.parse('<g><g id="x"/><g id="x"/></g>').rootElement)).throws<StateError>();
    check(editor.root.children.length).equals(2);
  });

  test('deletion exposes dangling links and automatic resource IDs stay unique', () {
    final SvgEditor editor = SvgEditor.empty();
    final SvgEditableElement gradient = editor.createElement(name: 'linearGradient');
    final SvgEditableElement shape = editor.createElement(name: 'rect');
    shape.setReference(property: 'fill', target: gradient);
    editor.definitions.insert(child: gradient);
    editor.root.insert(child: shape);
    check(gradient.id).equals('linearGradient');
    check(editor.uniqueId(prefix: 'linearGradient')).equals('linearGradient-2');
    check(editor.danglingReferences).isEmpty();
    gradient.remove();
    check(editor.danglingReferences.single.targetId).equals('linearGradient');
    editor.definitions.insert(child: gradient);
    check(editor.danglingReferences).isEmpty();
  });

  test('href setters synchronize legacy links and remove both forms', () {
    final SvgEditor editor = _editor('<svg xmlns:l="http://www.w3.org/1999/xlink"><use l:href="#old"/></svg>');
    final SvgEditableElement use = editor.root.children.single;
    use.setHref(value: '#new');
    check(use.attribute(name: 'l:href')).equals('#new');
    check(use.attribute(name: 'href')).equals('#new');
    use.setHref(value: null);
    check(use.href).isNull();
    use.setHref(value: '#again', includeXlink: true);
    check(use.attribute(name: 'href', namespace: svgXlinkNamespace)).equals('#again');
  });

  test('explicit XML base keeps potentially external fragments caller-managed', () {
    final SvgEditor editor = _editor('<svg><g id="target"/><g xml:base="external.svg"><use href="#target"/><rect fill="url(#target)"/></g></svg>');
    final SvgEditableElement target = editor.elementById(id: 'target')!;
    editor.renameId(element: target, id: 'new');
    final SvgEditableElement instance = editor.root.children.last.children.first;
    check(instance.href).equals('#target');
    check(instance.hrefTarget).isNull();
    check(editor.root.children.last.children.last.attribute(name: 'fill')).equals('url(#target)');
    check(() => instance.setReference(property: 'href', target: target)).throws<StateError>();
  });
}

/// Creates an authoring session for reference tests.
SvgEditor _editor(String source) => SvgEditor(document: SvgDocument.parse(source: source));
