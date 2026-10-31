import 'package:checks/checks.dart';
import 'package:svgkit/svgkit.dart';
import 'package:test/test.dart';

/// Exercises editable path grammar and exact normalization independently of XML.
void main() {
  test('reads every command and expands repeated moveto pairs', () {
    final SvgPathData path = SvgPathData.parse(source: 'm1,2 3 4 H8 v9 C1 2 3 4 5 6 s1 2 3 4 Q2 3 4 5 t6 7 A2 3 45 0 1 9 8 z');
    check(path.commands.map((command) => command.command).join()).equals('mlHvCsQtAz');
    check(SvgPathData.parse(source: path.toString()).toString()).equals(path.toString());
  });

  test('normalizes relative coordinates with separate subpath origins', () {
    final SvgPathData path = SvgPathData.parse(source: 'm10 20 3 4 h5 v6 z m1 2 l2 3').normalized();
    check(path.toString()).equals('M10 20 L13 24 L18 24 L18 30 Z M11 22 L13 25');
    check(path.normalized().toString()).equals(path.toString());
  });

  test('expands smooth control points and resets reflection after other commands', () {
    final SvgPathData path = SvgPathData.parse(source: 'M0 0 C1 2 3 4 5 6 s2 2 4 4 L1 1 S2 3 4 5 Q6 7 8 9 t2 2 A1 2 0 0 1 5 5 T6 6').normalized();
    check(path.toString()).equals('M0 0 C1 2 3 4 5 6 C7 8 7 8 9 10 L1 1 C1 1 2 3 4 5 Q6 7 8 9 Q10 11 10 11 A1 2 0 0 1 5 5 Q5 5 6 6');
  });

  test('keeps elliptical arcs exact including compact adjacent flags', () {
    final SvgPathData path = SvgPathData.parse(source: 'M2 3 a-5 -6 90 0110-4').normalized();
    check(path.toString()).equals('M2 3 A5 6 90 0 1 12 -1');
    final SvgPathCommand arc = SvgPathCommand.arcTo(radiusX: 4, radiusY: 5, rotation: 45, largeArc: true, x: 9, y: 10);
    check(arc.values).deepEquals([4.0, 5.0, 45.0, 1.0, 0.0, 9.0, 10.0]);
  });

  test('supports number signs, decimals and exponent boundaries', () {
    check(SvgPathData.parse(source: 'M.5-.2L1e-3+2E2 1.2.3').toString()).equals('M0.5 -0.2 L0.001 200 L1.2 0.3');
    check(SvgPathData.parse(source: '').commands).isEmpty();
  });

  for (final String source in [
    'L0 0',
    'Z',
    'M',
    'M0',
    'M,0 0',
    'M0 0,',
    'M0 0,,1 1',
    'M0 0 X1 1',
    'M0 0z1 2',
    'M0 0 A1 2 0 2 1 3 4',
    'M0 0 A1 2 0 0.0 1 3 4',
    'M0 0 L1e999 0',
    'M0 NaN',
    'M0 0 C1 2 3',
  ]) {
    test('rejects malformed path $source', () => check(() => SvgPathData.parse(source: source)).throws<FormatException>());
  }

  test('path limits are enforced before allocating additional commands', () {
    check(() => SvgPathData.parse(source: 'M0 0L1 1', maxCommands: 1)).throws<FormatException>();
    check(() => SvgPathData.parse(source: 'M0 0', maxCharacters: 3)).throws<FormatException>();
    check(() => SvgPathData.parse(source: '', maxCommands: 0)).throws<ArgumentError>();
  });

  test('command and list edits preserve immutable source values', () {
    final List<double> operands = [1, 2];
    final SvgPathCommand command = SvgPathCommand(command: 'M', values: operands);
    operands[0] = 99;
    final SvgPathData original = SvgPathData(commands: [command, SvgPathCommand.lineTo(x: 4, y: 5)]);
    final SvgPathData edited = original.replace(start: 1, end: 2, replacement: [SvgPathCommand.quadraticTo(x1: 2, y1: 3, x: 6, y: 7), SvgPathCommand.close()]);
    check(original.toString()).equals('M1 2 L4 5');
    check(edited.toString()).equals('M1 2 Q2 3 6 7 Z');
    check(() => command.values.add(3)).throws<UnsupportedError>();
    check(original.commands.clear).throws<UnsupportedError>();
    check(() => SvgPathCommand(command: 'A', values: [1, 2, 3, 4, 5, 6, 7])).throws<FormatException>();
    check(() => SvgPathCommand.moveTo(x: double.infinity, y: 0)).throws<FormatException>();
  });

  test('polygon and polyline points remain editable and finite', () {
    final SvgPointList points = SvgPointList.parse(source: '0,1 2,3 -4.5,6');
    check(points.points.last.x).equals(-4.5);
    check(SvgPointList.parse(source: points.toString()).points).deepEquals(points.points);
    check(() => SvgPointList.parse(source: '0,1,2')).throws<FormatException>();
    check(() => SvgPointList.parse(source: '0 1 2 3', maxPoints: 1)).throws<FormatException>();
  });
}
