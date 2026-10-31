import 'package:checks/checks.dart';
import 'package:svgkit/svgkit.dart';
import 'package:test/test.dart';

/// Verifies transforms, length contexts and loss-preserving inline style edits.
void main() {
  test('edits viewport alignment, meet/slice and legacy defer syntax', () {
    final SvgEditor editor = SvgEditor.empty();
    check(editor.root.preserveAspectRatio.alignment).equals('xMidYMid');
    editor.root.setPreserveAspectRatio(value: SvgPreserveAspectRatio.parse(source: 'defer xMaxYMin slice'));
    final SvgPreserveAspectRatio value = editor.root.preserveAspectRatio;
    check(value.alignment).equals('xMaxYMin');
    check(value.fit).equals(SvgAspectRatioFit.slice);
    check(value.defer).isTrue();
    check(SvgPreserveAspectRatio.parse(source: 'none').alignment).equals('none');
    for (final String invalid in ['', 'defer', 'xMidYMid cover', 'xMidYMid meet trailing', 'xMidYMid,meet']) {
      check(() => SvgPreserveAspectRatio.parse(source: invalid)).throws<FormatException>();
    }
  });

  test('parses all SVG transform functions without changing order', () {
    final SvgTransformList list = SvgTransformList.parse(source: 'translate(10,20)scale(2) rotate(45 1 2),skewX(5) skewY(-5) matrix(1 0 0 1 3 4)');
    check(list.transforms.map((transform) => transform.name).join(',')).equals('translate,scale,rotate,skewX,skewY,matrix');
    check(SvgTransformList.parse(source: list.toString()).toString()).equals(list.toString());
    check(list.prepend(transform: SvgTransform.translate(x: 4)).transforms.first.values).deepEquals([4.0, 0.0]);
    check(list.append(transform: SvgTransform.scale(x: 2, y: 3)).transforms.last.values).deepEquals([2.0, 3.0]);
    check(list.transforms.length).equals(6);
    check(SvgTransform.rotate(degrees: 90).toString()).equals('rotate(90 0 0)');
    check(SvgTransform.skewX(degrees: 3).name).equals('skewX');
    check(SvgTransform.skewY(degrees: 4).name).equals('skewY');
    check(SvgTransform.matrix(a: 1, b: 0, c: 0, d: 1, e: 5, f: 6).values.last).equals(6);
  });

  for (final String source in [
    'translate()',
    'matrix(1 2)',
    'rotate(1 2)',
    'scale(1,)',
    'translate(,1)',
    'translate(1,,2)',
    'translate(1',
    'rotate(1rad)',
    'scale(2),',
    'spin(2)',
    'matrix(1 2 3 4 5 6 7)',
  ]) {
    test('rejects invalid transform $source', () => check(() => SvgTransformList.parse(source: source)).throws<FormatException>());
  }

  test('limits transform function count', () {
    check(() => SvgTransformList.parse(source: 'scale(1)scale(2)', maxTransforms: 1)).throws<FormatException>();
    check(() => SvgTransformList.parse(source: '', maxTransforms: 0)).throws<ArgumentError>();
  });

  test('resolves lengths only with the appropriate supplied metric', () {
    check(SvgLength.parse(value: '50%').resolve(percentageBasis: 80)).equals(40);
    check(SvgLength.parse(value: '50%').resolve(viewportWidth: 80)).isNull();
    check(SvgLength.parse(value: '2em').resolve(fontSize: 12)).equals(24);
    check(SvgLength.parse(value: '2rem').resolve(rootFontSize: 10)).equals(20);
    check(SvgLength.parse(value: '2ex').resolve(xHeight: 6)).equals(12);
    check(SvgLength.parse(value: '2ch').resolve(zeroAdvance: 7)).equals(14);
    check(SvgLength.parse(value: '10vw').resolve(viewportWidth: 200)).equals(20);
    check(SvgLength.parse(value: '10vh').resolve(viewportHeight: 100)).equals(10);
    check(SvgLength.parse(value: '10vmin').resolve(viewportWidth: 200, viewportHeight: 100)).equals(10);
    check(SvgLength.parse(value: '10vmax').resolve(viewportWidth: 200, viewportHeight: 100)).equals(20);
    check(SvgLength.parse(value: '1in').resolve()).equals(96);
    check(SvgLength.parse(value: '2.50mm').toString()).equals('2.5mm');
    check(() => SvgLength(value: 1).resolve(fontSize: -1)).throws<ArgumentError>();
  });

  test('CSS editing respects strings, data URIs, comments and nested values', () {
    const String source = 'fill:red; --data: {a:b;c:d}; font-family:"A;B"; /* note */ stroke: url("data:x;a:b;c"); broken; opacity:.5';
    final SvgStyle original = SvgStyle(source: source);
    final SvgStyle edited = original.set(name: 'fill', value: 'blue');
    check(original.toString()).equals(source);
    check(edited.property(name: 'fill')!.value).equals('blue');
    check(edited.property(name: '--data')!.value).equals('{a:b;c:d}');
    check(edited.property(name: 'font-family')!.value).equals('"A;B"');
    check(edited.property(name: 'stroke')!.value).equals('url("data:x;a:b;c")');
    check(edited.toString().contains('broken;')).isTrue();
    check(edited.toString().contains('/* note */')).isTrue();
  });

  test('inline duplicate resolution honors importance and custom-property case', () {
    final SvgStyle style = SvgStyle(source: 'FILL:red !important;fill:blue;fill:green ! /*keep*/ IMPORTANT;--X:1;--x:2;');
    check(style.property(name: 'fill')!.value).equals('green');
    check(style.property(name: '--X')!.value).equals('1');
    check(style.property(name: '--x')!.value).equals('2');
    final SvgStyle replaced = style.set(name: 'FILL', value: 'black');
    check(replaced.declarations.where((value) => value.name == 'fill').length).equals(1);
    check(replaced.property(name: 'fill')!.important).isFalse();
    check(replaced.remove(name: 'fill').property(name: 'fill')).isNull();
    check(SvgStyle(source: 'content:"!important"').property(name: 'content')!.value).equals('"!important"');
  });

  test('rejects unsafe single-property edits and unbalanced syntax', () {
    check(() => SvgStyle().set(name: 'fill', value: 'red;stroke:blue')).throws<FormatException>();
    check(() => SvgStyle().set(name: 'fill', value: 'red!important')).throws<FormatException>();
    check(() => SvgStyle().set(name: 'fill:bad', value: 'red')).throws<FormatException>();
    for (final String source in ['fill:url(', 'fill:"x', '/* x', 'fill:)', 'fill:red\\']) {
      check(() => SvgStyle(source: source)).throws<FormatException>();
    }
  });

  test('recognizes escaped property names and importance without merging tokens', () {
    final SvgStyle style = SvgStyle(source: r'f\69 ll:red !\69mportant;f/**/ill:invalid;--empty:;');
    check(style.property(name: 'fill')!.important).isTrue();
    check(style.property(name: '--empty')!.value).equals('');
    final SvgStyle edited = style.set(name: 'fill', value: 'blue');
    check(edited.property(name: 'fill')!.value).equals('blue');
    check(edited.property(name: 'fill')!.important).isFalse();
    check(edited.source.contains('f/**/ill:invalid')).isTrue();
    check(SvgStyle().set(name: '--empty', value: '').property(name: '--empty')!.value).equals('');
  });
}
