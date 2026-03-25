import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';

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
    // If staffExtendWidth is set, extend staff lines beyond content
    if (staffExtendWidth != null && measureRendereres.isNotEmpty) {
      _renderExtendedStaffLines(canvas);
    }
    for (final measure in measureRendereres) {
      measure.render(canvas, size);
    }
    if (showBarlines) _renderBarlines(canvas);
    if (showEndBarline) _renderEndBarline(canvas);
    if (showFinalBarline) _renderFinalBarline(canvas);
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
