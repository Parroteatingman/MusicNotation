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
    this.alignLeft = false,
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

  /// When true, content hugs the left edge instead of being horizontally
  /// centred within the widget width.
  final bool alignLeft;

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

  /// The left padding on the canvas. Centres content by default, or hugs the
  /// left edge when [alignLeft] is set.
  double get _leftPaddingOnCanvas =>
      alignLeft ? 0 : _horizontalPaddingOnCanvas / 2;

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
    final staffList = metrics.staffsMetricses.toList();
    final lastIndex = staffList.length - 1;
    final result = <StaffRenderer>[];
    for (int i = 0; i <= lastIndex; i++) {
      final staffMetrics = staffList[i];
      currentY += staffMetrics.upperHeight;
      final isLast = i == lastIndex;
      final staffRenderer = staffMetrics.renderer(
        this,
        staffLineCenterY: currentY,
        leftPadding: _leftPaddingOnCanvas,
        showBarlines: showBarlines,
        // 非末行画结尾小节线，末行画终止双线
        showEndBarline: !isLast && showEndBarline,
        showFinalBarline: isLast && showFinalBarline,
        staffExtendWidth: extendStaffToFullWidth ? _fullWidthOnCanvas : null,
      );
      currentY += staffMetrics.lowerHeight;
      result.add(staffRenderer);
    }
    return result;
  }

  int? hitTestSelectableIndex(Offset canvasPosition) {
    var selectableIndex = 0;
    for (final staff in staffRenderers) {
      final hit = staff.hitTestSelectableIndex(canvasPosition, selectableIndex);
      if (hit != null) return hit;
      selectableIndex += staff.selectableSymbolCount;
    }
    return null;
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
