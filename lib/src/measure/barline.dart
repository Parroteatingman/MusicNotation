import 'package:flutter/material.dart';

import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// How a measure ends.
enum BarlineType {
  /// One thin line — what every measure gets when nothing is asked for.
  single,

  /// Two thin lines: the end of a section.
  doubleLine,

  /// Thin and thick: the end of the piece.
  finalLine,

  /// Dots, thin and thick: back to the start repeat.
  repeatEnd,
}

/// Draws barlines to the fonts' engraving defaults (SMuFL): a thin line as
/// wide as the package's plain barline, a thick one, 0.4 spaces between them,
/// repeat dots 0.4 spaces across set 0.16 spaces from the thin line, in the
/// second and third spaces of the staff.
class BarlinePainter {
  const BarlinePainter(this.staffLineThickness);

  final double staffLineThickness;

  static const double _space = Constants.staffSpace;
  static const double separation = 0.4 * _space;
  static const double dotSeparation = 0.16 * _space;
  static const double dotDiameter = 0.4 * _space;

  /// Room left between the dots and the notes beside them.
  static const double clearance = 0.3 * _space;

  double get thin => staffLineThickness * 1.5;
  double get thick => staffLineThickness * 4;

  /// From the thick line of `‖:` to the far side of its dots.
  double get repeatWidth =>
      thick + separation + thin + dotSeparation + dotDiameter;

  /// How far an end barline of [type] reaches back from where it ends.
  double widthOf(BarlineType type) {
    switch (type) {
      case BarlineType.single:
        return thin;
      case BarlineType.doubleLine:
        return thin + separation + thin;
      case BarlineType.finalLine:
        return thin + separation + thick;
      case BarlineType.repeatEnd:
        return repeatWidth;
    }
  }

  /// The room a measure keeps before its end so an end barline of [type]
  /// doesn't run into the last note. A single line stands on the boundary and
  /// needs none.
  double roomFor(BarlineType type) {
    if (type == BarlineType.single) return 0;
    if (type == BarlineType.repeatEnd) return widthOf(type) + clearance;
    return widthOf(type);
  }

  void _line(Canvas canvas, Paint paint, double left, double width,
          double centerY) =>
      canvas.drawRect(
        Rect.fromLTWH(left, centerY - 2 * _space, width, 4 * _space),
        paint,
      );

  void _dots(Canvas canvas, Paint paint, double left, double centerY) {
    const r = dotDiameter / 2;
    for (final y in [centerY - _space / 2, centerY + _space / 2]) {
      canvas.drawCircle(Offset(left + r, y), r, paint);
    }
  }

  /// `‖:` from [left]: thick, thin, dots.
  void repeatStart(Canvas canvas, Color color, double left, double centerY) {
    final paint = Paint()..color = color;
    _line(canvas, paint, left, thick, centerY);
    var x = left + thick + separation;
    _line(canvas, paint, x, thin, centerY);
    x += thin + dotSeparation;
    _dots(canvas, paint, x, centerY);
  }

  /// An end barline of [type] whose right edge is [right]. With [shareThick]
  /// a repeat end leaves out its thick line: a `‖:` starts right there and
  /// its thick line is the one they share (`:‖:`).
  void end(
    Canvas canvas,
    Color color,
    BarlineType type,
    double right,
    double centerY, {
    bool shareThick = false,
  }) {
    final paint = Paint()..color = color;
    switch (type) {
      case BarlineType.single:
        _line(canvas, paint, right - thin, thin, centerY);
        break;
      case BarlineType.doubleLine:
        _line(canvas, paint, right - thin, thin, centerY);
        _line(canvas, paint, right - 2 * thin - separation, thin, centerY);
        break;
      case BarlineType.finalLine:
        _line(canvas, paint, right - thick, thick, centerY);
        _line(canvas, paint, right - thick - separation - thin, thin, centerY);
        break;
      case BarlineType.repeatEnd:
        final thinLeft =
            (shareThick ? right : right - thick) - separation - thin;
        if (!shareThick) _line(canvas, paint, right - thick, thick, centerY);
        _line(canvas, paint, thinLeft, thin, centerY);
        _dots(canvas, paint, thinLeft - dotSeparation - dotDiameter, centerY);
        break;
    }
  }
}

/// The `‖:` a measure opens with: set like a symbol so the notes make room
/// for it, after the clef, key and time signature a measure starts with.
class RepeatStartMetrics implements MusicalSymbolMetrics {
  const RepeatStartMetrics(this.painter);

  final BarlinePainter painter;

  @override
  double get width => painter.repeatWidth + BarlinePainter.clearance;

  @override
  double get upperHeight => 2 * Constants.staffSpace;

  @override
  double get lowerHeight => 2 * Constants.staffSpace;

  @override
  EdgeInsets get margin => EdgeInsets.zero;

  @override
  double get durationUnits => 0;

  @override
  double get leadingWidth => 0;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      RepeatStartRenderer(
        painter,
        layout,
        symbolX: symbolX,
        staffLineCenterY: staffLineCenterY,
      );
}

class RepeatStartRenderer implements MusicalSymbolRenderer {
  const RepeatStartRenderer(
    this.painter,
    this.layout, {
    required this.symbolX,
    required this.staffLineCenterY,
  });

  final BarlinePainter painter;
  final SheetMusicLayout layout;
  final double staffLineCenterY;

  @override
  final double symbolX;

  @override
  bool isHit(Offset position) => false;

  @override
  void render(Canvas canvas) =>
      painter.repeatStart(canvas, layout.lineColor, symbolX, staffLineCenterY);
}

/// Blank room at a measure's end for the barline the staff draws there.
class BarlineRoomMetrics implements MusicalSymbolMetrics {
  const BarlineRoomMetrics(this.width);

  @override
  final double width;

  @override
  double get upperHeight => 2 * Constants.staffSpace;

  @override
  double get lowerHeight => 2 * Constants.staffSpace;

  @override
  EdgeInsets get margin => EdgeInsets.zero;

  @override
  double get durationUnits => 0;

  @override
  double get leadingWidth => 0;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      _BlankRenderer(symbolX);
}

class _BlankRenderer implements MusicalSymbolRenderer {
  _BlankRenderer(this.symbolX);

  @override
  final double symbolX;

  @override
  bool isHit(Offset position) => false;

  @override
  void render(Canvas canvas) {}
}
