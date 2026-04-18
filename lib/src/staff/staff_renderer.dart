import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
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
  });

  final List<MeasureRenderer> measureRendereres;
  final bool showBarlines;
  final bool showEndBarline;
  final bool showFinalBarline;

  /// If set, extend staff lines to this width (in canvas coordinates).
  final double? staffExtendWidth;

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
    if (staffExtendWidth != null && measureRendereres.isNotEmpty) {
      _renderExtendedStaffLines(canvas);
    }
    for (int i = 0; i < measureRendereres.length; i++) {
      measureRendereres[i].render(
        canvas,
        size,
        suppressLeadingTie: suppressedLeadingTies.contains(i),
        suppressTrailingTie: suppressedTrailingTies.contains(i),
      );
    }
    if (showBarlines) _renderBarlines(canvas);
    if (showEndBarline) _renderEndBarline(canvas);
    if (showFinalBarline) _renderFinalBarline(canvas);
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

  /// Draws vertical barlines between measures.
  void _renderBarlines(Canvas canvas) {
    if (measureRendereres.length < 2) return;

    for (int i = 0; i < measureRendereres.length - 1; i++) {
      final measure = measureRendereres[i];
      final barlineX = measure.measureOriginX + measure.width;
      final centerY = measure.staffLineCenterY;
      final topY = centerY - Constants.staffSpace * 2;
      final bottomY = centerY + Constants.staffSpace * 2;

      canvas.drawLine(
        Offset(barlineX, topY),
        Offset(barlineX, bottomY),
        Paint()
          ..color = measure.layout.lineColor
          ..strokeWidth = measure.measureMetrics.staffLineThickness * 1.5,
      );
    }
  }

  /// Draws a single thin barline at the end of the staff.
  void _renderEndBarline(Canvas canvas) {
    if (measureRendereres.isEmpty) return;
    final last = measureRendereres.last;
    final barlineX = staffExtendWidth ?? (last.measureOriginX + last.width);
    final centerY = last.staffLineCenterY;
    final topY = centerY - Constants.staffSpace * 2;
    final bottomY = centerY + Constants.staffSpace * 2;
    canvas.drawLine(
      Offset(barlineX, topY),
      Offset(barlineX, bottomY),
      Paint()
        ..color = last.layout.lineColor
        ..strokeWidth = last.measureMetrics.staffLineThickness * 1.5,
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

  /// Extends staff lines to the full width when staffExtendWidth is set.
  void _renderExtendedStaffLines(Canvas canvas) {
    final first = measureRendereres.first;
    final last = measureRendereres.last;
    final contentEndX = last.measureOriginX + last.width;
    final extendTo = staffExtendWidth!;
    if (extendTo <= contentEndX) return;

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
        Offset(contentEndX, h),
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
