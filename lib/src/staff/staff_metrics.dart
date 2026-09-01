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

  /// The number of symbols laid out across this staff.
  int get symbolCount => measuresMetricses.fold(
        0,
        (sum, measure) => sum + measure.musicalSymbolsMetricses.length,
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
  }) {
    var currentX = leftPadding;
    final distributedSpacing = layout.distributedSymbolSpacingOnCanvasFor(this);
    var hasPreviousSymbol = false;
    final measureRendereres = <MeasureRenderer>[];
    for (final measure in measuresMetricses) {
      final symbolCount = measure.musicalSymbolsMetricses.length;
      final includeLeadingSpacing = hasPreviousSymbol && symbolCount > 0;
      final m = measure.renderer(
        layout,
        measureInitialX: currentX,
        staffLineCenterY: staffLineCenterY,
        distributedSymbolSpacingOnCanvas: distributedSpacing,
        includeLeadingDistributedSpacing: includeLeadingSpacing,
      );
      currentX += m.width;
      measureRendereres.add(m);
      if (symbolCount > 0) {
        hasPreviousSymbol = true;
      }
    }

    return StaffRenderer(
      measureRendereres,
      showBarlines: showBarlines,
      showEndBarline: showEndBarline,
      showFinalBarline: showFinalBarline,
      staffExtendWidth: staffExtendWidth,
    );
  }
}
