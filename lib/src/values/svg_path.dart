import 'package:svgkit/src/values/svg_number_reader.dart';

/// One SVG command and its editable operands, without approximating arcs.
final class SvgPathCommand {
  /// Case-sensitive command letter; lowercase operands are relative.
  final String command;

  /// Immutable operands in SVG order, including numeric arc flags.
  final List<double> values;

  /// Required operand counts by uppercase command.
  static const Map<String, int> _counts = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7, 'Z': 0};

  /// Creates and validates exactly one command.
  SvgPathCommand({
    required this.command,
    Iterable<double> values = const [],
  }) : values = List.unmodifiable(values) {
    if (!RegExp(r'^[MmLlHhVvCcSsQqTtAaZz]$').hasMatch(command) || _counts[command.toUpperCase()] != this.values.length || !this.values.every((value) => value.isFinite)) {
      throw const FormatException('Invalid SVG path command or operands.');
    }
    if (command.toUpperCase() == 'A' && (!const [0.0, 1.0].contains(this.values[3]) || !const [0.0, 1.0].contains(this.values[4]))) {
      throw const FormatException('Arc flags must be zero or one.');
    }
  }

  /// Starts a subpath.
  factory SvgPathCommand.moveTo({
    required double x,
    required double y,
    bool relative = false,
  }) => SvgPathCommand(command: relative ? 'm' : 'M', values: [x, y]);

  /// Adds a straight segment.
  factory SvgPathCommand.lineTo({
    required double x,
    required double y,
    bool relative = false,
  }) => SvgPathCommand(command: relative ? 'l' : 'L', values: [x, y]);

  /// Adds a cubic Bézier segment with both control points.
  factory SvgPathCommand.cubicTo({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double x,
    required double y,
    bool relative = false,
  }) => SvgPathCommand(command: relative ? 'c' : 'C', values: [x1, y1, x2, y2, x, y]);

  /// Adds a quadratic Bézier segment.
  factory SvgPathCommand.quadraticTo({
    required double x1,
    required double y1,
    required double x,
    required double y,
    bool relative = false,
  }) => SvgPathCommand(command: relative ? 'q' : 'Q', values: [x1, y1, x, y]);

  /// Adds an exact elliptical arc; rotation is in degrees.
  factory SvgPathCommand.arcTo({
    required double radiusX,
    required double radiusY,
    double rotation = 0,
    bool largeArc = false,
    bool sweep = false,
    required double x,
    required double y,
    bool relative = false,
  }) => SvgPathCommand(command: relative ? 'a' : 'A', values: [radiusX, radiusY, rotation, if (largeArc) 1 else 0, if (sweep) 1 else 0, x, y]);

  /// Closes the current subpath.
  factory SvgPathCommand.close() => SvgPathCommand(command: 'Z');

  /// Whether coordinates are relative to the previous endpoint.
  bool get isRelative => command == command.toLowerCase();

  /// Replaces operands while retaining the command kind.
  SvgPathCommand withValues({required Iterable<double> values}) => SvgPathCommand(command: command, values: values);

  @override
  String toString() => '$command${values.map(svgNumber).join(' ')}';
}

/// Immutable, editable SVG path syntax covering every SVG 1.1/2 command.
final class SvgPathData {
  /// Commands with repeated operand groups expanded into individual commands.
  final List<SvgPathCommand> commands;

  /// Creates a path that is empty or begins with a move command.
  SvgPathData({
    Iterable<SvgPathCommand> commands = const [],
  }) : commands = List.unmodifiable(commands) {
    if (this.commands.isNotEmpty && this.commands.first.command.toUpperCase() != 'M') {
      throw const FormatException('SVG paths must begin with moveto.');
    }
  }

  /// Parses all path commands, including compact arc flags and implicit lines.
  factory SvgPathData.parse({
    required String source,
    int maxCommands = 1000000,
    int maxCharacters = 16000000,
  }) {
    if (maxCommands <= 0 || maxCharacters <= 0) {
      throw ArgumentError('Path limits must be positive.');
    }
    if (source.length > maxCharacters) {
      throw const FormatException('SVG path exceeds the character limit.');
    }
    final SvgNumberReader reader = SvgNumberReader(source: source);
    final List<SvgPathCommand> commands = [];
    String? active;
    while (!reader.done) {
      final String next = source[reader.position];
      final bool explicit = RegExp('[A-Za-z]').hasMatch(next);
      if (explicit) {
        active = next;
        reader.position++;
      }
      if (active == null || !SvgPathCommand._counts.containsKey(active.toUpperCase())) {
        throw FormatException('Expected an SVG path command.', source, reader.position);
      }
      final String kind = active.toUpperCase();
      final int count = SvgPathCommand._counts[kind]!;
      if (commands.length >= maxCommands) {
        throw const FormatException('SVG path exceeds the command limit.');
      }
      final List<double> values = [];
      for (int index = 0; index < count; index++) {
        values.add(reader.number(comma: !explicit || index > 0, flag: kind == 'A' && (index == 3 || index == 4)));
      }
      commands.add(SvgPathCommand(command: active, values: values));
      if (kind == 'M') {
        active = active == 'm' ? 'l' : 'L';
      } else if (kind == 'Z') {
        active = null;
      }
    }
    return SvgPathData(commands: commands);
  }

  /// Replaces, inserts or removes a contiguous range of commands.
  SvgPathData replace({required int start, required int end, required Iterable<SvgPathCommand> replacement}) {
    final List<SvgPathCommand> updated = commands.toList()..replaceRange(start, end, replacement);
    return SvgPathData(commands: updated);
  }

  /// Expands relative, horizontal, vertical and smooth commands to M/L/C/Q/A/Z.
  ///
  /// Arc radii and flags remain exact; no flattening or curve approximation is
  /// performed. Explicit control points can be edited without hidden reflection.
  SvgPathData normalized() {
    final List<SvgPathCommand> result = [];
    double x = 0;
    double y = 0;
    double startX = 0;
    double startY = 0;
    double controlX = 0;
    double controlY = 0;
    String previous = '';
    for (final SvgPathCommand segment in commands) {
      final String kind = segment.command.toUpperCase();
      final List<double> values = segment.values.toList();
      final double originX = segment.isRelative ? x : 0;
      final double originY = segment.isRelative ? y : 0;
      String output = kind;
      switch (kind) {
        case 'Z':
          x = startX;
          y = startY;
        case 'H':
          values[0] += originX;
          values.add(y);
          output = 'L';
        case 'V':
          values[0] += originY;
          values.insert(0, x);
          output = 'L';
        case 'A':
          values[0] = values[0].abs();
          values[1] = values[1].abs();
          values[5] += originX;
          values[6] += originY;
        default:
          for (int index = 0; index < values.length; index += 2) {
            values[index] += originX;
            values[index + 1] += originY;
          }
          if (kind == 'S' || kind == 'T') {
            final bool reflected = kind == 'S' ? previous == 'C' || previous == 'S' : previous == 'Q' || previous == 'T';
            values.insertAll(0, [if (reflected) 2 * x - controlX else x, if (reflected) 2 * y - controlY else y]);
            output = kind == 'S' ? 'C' : 'Q';
          }
      }
      if (values.isNotEmpty) {
        x = values[values.length - 2];
        y = values.last;
        if (output == 'M') {
          startX = x;
          startY = y;
        }
        if (output == 'C' || output == 'Q') {
          controlX = values[values.length - 4];
          controlY = values[values.length - 3];
        }
      }
      previous = kind;
      result.add(SvgPathCommand(command: output, values: values));
    }
    return SvgPathData(commands: result);
  }

  @override
  String toString() => commands.join(' ');
}

/// One coordinate pair in a polygon or polyline's SVG attribute.
typedef SvgPoint = ({double x, double y});

/// Immutable editable coordinates for polygon and polyline elements.
final class SvgPointList {
  /// Ordered coordinate pairs.
  final List<SvgPoint> points;

  /// Copies finite coordinate pairs.
  SvgPointList({
    required Iterable<SvgPoint> points,
  }) : points = List.unmodifiable(points) {
    if (!this.points.every((point) => point.x.isFinite && point.y.isFinite)) {
      throw const FormatException('Non-finite SVG point.');
    }
  }

  /// Parses comma/whitespace-separated coordinate pairs.
  factory SvgPointList.parse({
    required String source,
    int maxPoints = 1000000,
  }) {
    if (maxPoints <= 0) {
      throw ArgumentError.value(maxPoints, 'maxPoints');
    }
    final SvgNumberReader reader = SvgNumberReader(source: source);
    final List<SvgPoint> points = [];
    while (!reader.done) {
      if (points.length >= maxPoints) {
        throw const FormatException('SVG point limit exceeded.');
      }
      final double x = reader.number(comma: points.isNotEmpty);
      final double y = reader.number();
      points.add((x: x, y: y));
    }
    return SvgPointList(points: points);
  }

  @override
  String toString() => points.map((point) => '${svgNumber(point.x)},${svgNumber(point.y)}').join(' ');
}
