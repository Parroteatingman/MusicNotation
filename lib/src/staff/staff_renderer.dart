import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/barline.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';

/// The renderer for a staff, which is responsible for rendering measures and handling hit tests.
class StaffRenderer {
  const StaffRenderer(
    this.measureRendereres, {
    this.showBarlines = true,
    this.showEndBarline = false,
    this.showFinalBarline = false,
    this.staffExtendWidth,
    this.caretIndex,
    this.caretColor,
  });

  final List<MeasureRenderer> measureRendereres;
  final bool showBarlines;
  final bool showEndBarline;
  final bool showFinalBarline;

  /// If set, extend staff lines to this width (in canvas coordinates).
  final double? staffExtendWidth;

  /// Where the caret stands on this line, counted in notes and rests: 0 is
  /// before the first, the count is after the last. Null when the caret is
  /// on another line.
  final int? caretIndex;

  /// The colour of the caret.
  final Color? caretColor;

  /// Performs a hit test at the given position on the staff.
  ///
  /// Returns the [MusicalSymbolRenderer] that was hit, or `null` if no object was hit.
  MusicalSymbolRenderer? hitTest(Offset position) {
    for (final measure in measureRendereres) {
      final hit = measure.hitTest(position);
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  int? hitTestSelectableIndex(Offset position, int startIndex) {
    var selectableIndex = startIndex;
    for (final measure in measureRendereres) {
      final hit = measure.hitTestSelectableIndex(position, selectableIndex);
      if (hit != null) return hit;
      selectableIndex += measure.selectableSymbolCount;
    }
    return null;
  }

  int get selectableSymbolCount => measureRendereres.fold<int>(
        0,
        (sum, measure) => sum + measure.selectableSymbolCount,
      );

  /// Renders the staff on the given canvas with the specified size and font family.
  void render(Canvas canvas, Size size) {
    final suppressedLeadingTies = <int>{};
    final suppressedTrailingTies = <int>{};
    final crossMeasureTies = <_CrossMeasureTie>[];

    for (int i = 0; i < measureRendereres.length - 1; i++) {
      final crossTie =
          _buildCrossMeasureTie(measureRendereres[i], measureRendereres[i + 1]);
      if (crossTie == null) continue;

      suppressedTrailingTies.add(i);
      suppressedLeadingTies.add(i + 1);
      crossMeasureTies.add(crossTie);
    }

    // If staffExtendWidth is set, extend staff lines beyond content
    final extendsStaffLines =
        staffExtendWidth != null && measureRendereres.isNotEmpty;
    if (extendsStaffLines) {
      _renderExtendedStaffLines(canvas);
    }
    for (int i = 0; i < measureRendereres.length; i++) {
      measureRendereres[i].render(
        canvas,
        size,
        suppressLeadingTie: suppressedLeadingTies.contains(i),
        suppressTrailingTie: suppressedTrailingTies.contains(i),
        drawStaffLines: !extendsStaffLines,
      );
    }
    _renderBarlines(canvas);
    final lastType = measureRendereres.isEmpty
        ? null
        : measureRendereres.last.measureMetrics.endBarline;
    if (lastType != null) {
      _renderTypedEndBarline(canvas, lastType);
    } else {
      if (showEndBarline) _renderEndBarline(canvas);
      if (showFinalBarline) _renderFinalBarline(canvas);
    }
    _renderCaret(canvas);
    for (final tie in crossMeasureTies) {
      _drawCrossMeasureTie(canvas, tie);
    }
  }

  _CrossMeasureTie? _buildCrossMeasureTie(
    MeasureRenderer currentMeasure,
    MeasureRenderer nextMeasure,
  ) {
    final start = currentMeasure.lastNoteRenderer;
    final end = nextMeasure.firstNoteRenderer;
    if (start == null || end == null) return null;

    final startTie = start.note.note.tie;
    final endTie = end.note.note.tie;
    if (startTie == null ||
        !startTie.isStart ||
        endTie == null ||
        !endTie.isStop ||
        start.note.pitch != end.note.pitch) {
      return null;
    }

    return _CrossMeasureTie(
      start: start,
      end: end,
      strokeWidth: currentMeasure.measureMetrics.staffLineThickness * 2,
    );
  }

  void _drawCrossMeasureTie(Canvas canvas, _CrossMeasureTie tie) {
    final startBounds = tie.start.noteHeadBounds;
    final endBounds = tie.end.noteHeadBounds;
    final tieBelow = tie.start.note.isStemUp != tie.end.note.isStemUp
        ? false
        : tie.start.note.isStemUp;
    final baselineY = tieBelow
        ? startBounds.bottom + Constants.staffSpace * 0.35
        : startBounds.top - Constants.staffSpace * 0.35;
    final archHeight = Constants.staffSpace * 0.7 * (tieBelow ? 1 : -1);
    final startX = startBounds.right - Constants.staffSpace * 0.1;
    final endX = endBounds.left + Constants.staffSpace * 0.1;
    final controlX = (startX + endX) / 2;
    final controlY = baselineY + archHeight;

    final tiePaint = Paint()
      ..color = tie.start.note.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = tie.strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(startX, baselineY)
      ..quadraticBezierTo(controlX, controlY, endX, baselineY);

    canvas.drawPath(path, tiePaint);
  }

  /// Draws vertical barlines between measures: the plain line when
  /// [showBarlines] is set, and whatever a measure asks for either way.
  void _renderBarlines(Canvas canvas) {
    if (measureRendereres.length < 2) return;

    for (int i = 0; i < measureRendereres.length - 1; i++) {
      final measure = measureRendereres[i];
      final barlineX = measure.measureOriginX + measure.width;
      final centerY = measure.staffLineCenterY;
      final topY = centerY - Constants.staffSpace * 2;
      final bottomY = centerY + Constants.staffSpace * 2;
      final type = measure.measureMetrics.endBarline;
      final repeatNext = measureRendereres[i + 1].startsWithRepeat;
      if (type != null && type != BarlineType.single) {
        BarlinePainter(measure.measureMetrics.staffLineThickness).end(
          canvas,
          measure.layout.lineColor,
          type,
          barlineX,
          centerY,
          shareThick: type == BarlineType.repeatEnd && repeatNext,
        );
        continue;
      }
      // the next measure's ‖: stands on this barline
      if (!showBarlines || repeatNext) continue;

      canvas.drawLine(
        Offset(barlineX, topY),
        Offset(barlineX, bottomY),
        Paint()
          ..color = measure.layout.lineColor
          ..strokeWidth = measure.measureMetrics.staffLineThickness * 1.5,
      );
    }
  }

  /// The barline the staff's last measure asks for, at the staff's end.
  void _renderTypedEndBarline(Canvas canvas, BarlineType type) {
    final last = measureRendereres.last;
    BarlinePainter(last.measureMetrics.staffLineThickness).end(
      canvas,
      last.layout.lineColor,
      type,
      staffExtendWidth ?? (last.measureOriginX + last.width),
      last.staffLineCenterY,
    );
  }

  /// Draws a single thin barline at the end of the staff.
  void _renderEndBarline(Canvas canvas) {
    if (measureRendereres.isEmpty) return;
    final last = measureRendereres.last;
    final thickness = last.measureMetrics.staffLineThickness;
    // Sit the line inside the staff's right edge; drawn on the edge itself,
    // half of it falls outside the canvas and it reads as a smudge.
    final barlineX = (staffExtendWidth ?? (last.measureOriginX + last.width)) -
        thickness * 0.75;
    final centerY = last.staffLineCenterY;
    final topY = centerY - Constants.staffSpace * 2;
    final bottomY = centerY + Constants.staffSpace * 2;
    canvas.drawLine(
      Offset(barlineX, topY),
      Offset(barlineX, bottomY),
      Paint()
        ..color = last.layout.lineColor
        ..strokeWidth = thickness * 1.5,
    );
  }

  /// Draws a final double barline (thin + thick) at the end of the staff.
  void _renderFinalBarline(Canvas canvas) {
    if (measureRendereres.isEmpty) return;
    final last = measureRendereres.last;
    final endX = staffExtendWidth ?? (last.measureOriginX + last.width);
    final centerY = last.staffLineCenterY;
    final topY = centerY - Constants.staffSpace * 2;
    final bottomY = centerY + Constants.staffSpace * 2;
    final thickness = last.measureMetrics.staffLineThickness;
    // Thin line
    canvas.drawLine(
      Offset(endX - thickness * 6, topY),
      Offset(endX - thickness * 6, bottomY),
      Paint()
        ..color = last.layout.lineColor
        ..strokeWidth = thickness * 1.5,
    );
    // Thick line
    canvas.drawLine(
      Offset(endX - thickness * 1.5, topY),
      Offset(endX - thickness * 1.5, bottomY),
      Paint()
        ..color = last.layout.lineColor
        ..strokeWidth = thickness * 4,
    );
  }

  /// Draws the caret: the line the next note will be written at.
  ///
  /// The editor knew where the next note would land, and never said. A page
  /// with a caret on it reads the way a text field does.
  void _renderCaret(Canvas canvas) {
    final caretIndex = this.caretIndex;
    final color = caretColor;
    if (caretIndex == null || color == null) return;
    if (measureRendereres.isEmpty) return;

    final xs = <double>[
      for (final measure in measureRendereres) ...measure.selectableSymbolXs,
    ];

    final double x;
    if (caretIndex < xs.length) {
      // Right where the next symbol's own layout position is: its ink starts
      // a little after that, so the caret lands in the gap ahead of it rather
      // than against the note before.
      x = xs[caretIndex];
    } else if (xs.isNotEmpty) {
      // Past the last note on the line.
      final last = measureRendereres.last;
      x = last.measureOriginX + last.width - Constants.staffSpace * 0.3;
    } else {
      return;
    }

    final first = measureRendereres.first;
    final centerY = first.staffLineCenterY;
    final thickness = first.measureMetrics.staffLineThickness;
    canvas.drawLine(
      Offset(x, centerY - Constants.staffSpace * 2.6),
      Offset(x, centerY + Constants.staffSpace * 2.6),
      Paint()
        ..color = color
        ..strokeWidth = thickness * 2
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Extends staff lines across the full width when staffExtendWidth is set.
  void _renderExtendedStaffLines(Canvas canvas) {
    final first = measureRendereres.first;
    final extendTo = staffExtendWidth!;
    if (extendTo <= 0) {
      return;
    }

    final centerY = first.staffLineCenterY;
    final staffLineHeights = [
      centerY - Constants.staffSpace * 2,
      centerY - Constants.staffSpace,
      centerY,
      centerY + Constants.staffSpace,
      centerY + Constants.staffSpace * 2,
    ];
    for (final h in staffLineHeights) {
      canvas.drawLine(
        Offset(0, h),
        Offset(extendTo, h),
        Paint()
          ..color = first.layout.lineColor
          ..strokeWidth = first.measureMetrics.staffLineThickness,
      );
    }
  }
}

class _CrossMeasureTie {
  const _CrossMeasureTie({
    required this.start,
    required this.end,
    required this.strokeWidth,
  });

  final NoteRenderer start;
  final NoteRenderer end;
  final double strokeWidth;
}
