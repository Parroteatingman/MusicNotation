import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';

/// The renderer for a staff, which is responsible for rendering measures and handling hit tests.
class StaffRenderer {
  const StaffRenderer(this.measureRendereres, {this.showBarlines = true});

  final List<MeasureRenderer> measureRendereres;
  final bool showBarlines;

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
    for (final measure in measureRendereres) {
      measure.render(canvas, size);
    }
    if (showBarlines) _renderBarlines(canvas);
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
}
