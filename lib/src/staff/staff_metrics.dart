import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/extension/list_extension.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';
import 'package:simple_sheet_music/src/staff/staff_renderer.dart';

/// Represents the metrics of a staff, including the metrics of its measures.
class StaffMetrics {
  const StaffMetrics(this.measuresMetricses);

  /// The list of measure metrics for each measure in the staff.
  final List<MeasureMetrics> measuresMetricses;

  /// The height of the upper part of the staff.
  double get upperHeight =>
      measuresMetricses.map((measure) => measure.upperHeight).max;

  /// The height of the lower part of the staff.
  double get lowerHeight =>
      measuresMetricses.map((measure) => measure.lowerHeight).max;

  /// The total width of the staff, including the width of its objects and margins.
  double get width => objectsWidth + horizontalMarginSum;

  /// The total width of the objects in the staff.
  double get objectsWidth =>
      measuresMetricses.map((measure) => measure.objectsWidth).sum;

  /// The width of every symbol's own glyph, set glyph to glyph.
  double get glyphWidth =>
      measuresMetricses.map((measure) => measure.glyphWidth).sum;

  /// The part of [objectsWidth] held by symbols that carry no time.
  double get fixedWidth =>
      measuresMetricses.map((measure) => measure.fixedWidth).sum;

  /// The number of symbols laid out across this staff.
  int get symbolCount => measuresMetricses.fold(
        0,
        (sum, measure) => sum + measure.musicalSymbolsMetricses.length,
      );

  /// How many of those symbols are notes and rests — the things a caret can
  /// stand between and a tap can pick out. Only they carry musical time, so
  /// that is what separates them from clefs and key signatures.
  int get selectableSymbolCount => measuresMetricses.fold(
        0,
        (sum, measure) =>
            sum +
            measure.musicalSymbolsMetricses
                .where((symbol) => symbol.durationUnits > 0)
                .length,
      );

  /// The sum of the horizontal margins between measures in the staff.
  double get horizontalMarginSum =>
      measuresMetricses.map((measure) => measure.horizontalMarginSum).sum;

  /// The total height of the staff.
  double get height => upperHeight + lowerHeight;

  /// Creates a [StaffRenderer] with the given layout and rendering parameters.
  StaffRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double leftPadding,
    bool showBarlines = true,
    bool showEndBarline = false,
    bool showFinalBarline = false,
    double? staffExtendWidth,
    double stretch = 1,
    double squeeze = 1,
    double marginScale = 1,
    int? caretIndex,
    Color? caretColor,
  }) {
    var currentX = leftPadding;
    final measureRendereres = <MeasureRenderer>[];
    for (final measure in measuresMetricses) {
      final m = measure.renderer(
        layout,
        measureInitialX: currentX,
        staffLineCenterY: staffLineCenterY,
        stretch: stretch,
        squeeze: squeeze,
        marginScale: marginScale,
      );
      currentX += m.width;
      measureRendereres.add(m);
    }

    return StaffRenderer(
      measureRendereres,
      showBarlines: showBarlines,
      showEndBarline: showEndBarline,
      showFinalBarline: showFinalBarline,
      staffExtendWidth: staffExtendWidth,
      caretIndex: caretIndex,
      caretColor: caretColor,
    );
  }
}
