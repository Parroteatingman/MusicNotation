import 'dart:math';

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/staff/staff_renderer.dart';

/// Represents the layout of the sheet music.
class SheetMusicLayout {
  SheetMusicLayout(
    this.metrics,
    this.lineColor, {
    required this.widgetHeight,
    required this.widgetWidth,
    this.showBarlines = true,
    this.showEndBarline = false,
    this.showFinalBarline = false,
    this.extendStaffToFullWidth = false,
    this.maxCanvasScale,
  });

  /// The height of the widget.
  final double widgetHeight;

  /// The width of the widget.
  final double widgetWidth;

  /// The metrics for the sheet music.
  final SheetMusicMetrics metrics;

  /// The color of the lines in the sheet music.
  final Color lineColor;

  /// Whether to draw barlines between measures.
  final bool showBarlines;

  final bool showEndBarline;
  final bool showFinalBarline;
  final bool extendStaffToFullWidth;

  /// If set, caps the canvas scale to this value for consistent sizing across lines.
  final double? maxCanvasScale;

  /// The maximum width of a staff.
  double get _maximumStaffWidth => metrics.maximumStaffWidth;

  /// The sum of the horizontal margins of all the staffs.
  double get _maximumStaffHorizontalMarginSum =>
      metrics.maximumStaffHorizontalMarginSum;

  /// The horizontal padding of the sheet music.
  double get _horizontalPadding =>
      widgetWidth -
      (_maximumStaffWidth * canvasScale + _maximumStaffHorizontalMarginSum);

  /// The horizontal padding on the canvas.
  double get _horizontalPaddingOnCanvas => _horizontalPadding / canvasScale;

  /// The left padding on the canvas — left-aligned when maxCanvasScale is active.
  double get _leftPaddingOnCanvas {
    if (maxCanvasScale != null) {
      // Left-align: use minimal padding
      return _maximumStaffHorizontalMarginSum > 0
          ? _maximumStaffHorizontalMarginSum / (2 * canvasScale)
          : 0;
    }
    return _horizontalPaddingOnCanvas / 2;
  }

  /// The vertical padding of the sheet music.
  double get _verticalPadding => widgetHeight - _staffsHeightsSum * canvasScale;

  /// The vertical padding on the canvas.
  double get _verticalPaddingOnCanvas => _verticalPadding / canvasScale;

  /// The upper padding on the canvas.
  double get _upperPaddingOnCanvas => _verticalPaddingOnCanvas / 2;

  /// Full width in canvas coordinates (for staff extension).
  double get _fullWidthOnCanvas => widgetWidth / canvasScale;

  /// The list of staff renderers.
  List<StaffRenderer> get staffRenderers {
    var currentY = _upperPaddingOnCanvas;
    return metrics.staffsMetricses.map((staffMetrics) {
      currentY += staffMetrics.upperHeight;
      final staffRenderer = staffMetrics.renderer(
        this,
        staffLineCenterY: currentY,
        leftPadding: _leftPaddingOnCanvas,
        showBarlines: showBarlines,
        showEndBarline: showEndBarline,
        showFinalBarline: showFinalBarline,
        staffExtendWidth: extendStaffToFullWidth ? _fullWidthOnCanvas : null,
      );
      currentY += staffMetrics.lowerHeight;
      return staffRenderer;
    }).toList();
  }

  /// The sum of the heights of all the staffs.
  double get _staffsHeightsSum => metrics.staffsHeightSum;

  /// The scale factor for the width of the sheet music.
  double get _widthScale =>
      (widgetWidth - _maximumStaffHorizontalMarginSum) / _maximumStaffWidth;

  /// The scale factor for the height of the sheet music.
  double get _heightScale => widgetHeight / _staffsHeightsSum;

  /// The natural (uncapped) scale factor.
  double get _naturalScale => min(_widthScale, _heightScale);

  /// The scale factor for the canvas, capped by maxCanvasScale if set.
  double get canvasScale {
    final natural = _naturalScale;
    if (maxCanvasScale != null && natural > maxCanvasScale!) {
      return maxCanvasScale!;
    }
    return natural;
  }

  /// Renders the sheet music on the canvas.
  void render(Canvas canvas, Size size) {
    for (final staff in staffRenderers) {
      staff.render(canvas, size);
    }
  }
}
