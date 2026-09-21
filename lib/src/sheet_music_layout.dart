import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/staff/staff_metrics.dart';
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
    this.distributeSymbolsToFullWidth = false,
    this.contentHorizontalPadding = 0,
    this.maxCanvasScale,
    this.justifyLines = true,
    this.caretIndex,
    this.caretColor,
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

  /// Whether to distribute the remaining width evenly between symbols.
  final bool distributeSymbolsToFullWidth;

  /// Fixed physical inset for the first and last glyph when distributing.
  final double contentHorizontalPadding;

  /// If set, caps the canvas scale to this value for consistent sizing across lines.
  final double? maxCanvasScale;

  /// Pull each line but the last out to the full width, the way an engraver
  /// justifies every system but the final one. A short middle line with a
  /// ragged right edge reads as a mistake.
  final bool justifyLines;

  /// Where the next note will be written, counted in notes and rests across
  /// the whole page. Null draws no caret.
  final int? caretIndex;

  /// The colour of the caret.
  final Color? caretColor;

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
  double get _leftPaddingOnCanvas => distributeSymbolsToFullWidth
      ? contentHorizontalPadding / canvasScale
      : alignLeft
          ? 0
          : _horizontalPaddingOnCanvas / 2;

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
    // The caret is given as a position on the page; each line needs it as a
    // position on itself, or not at all.
    var symbolsBefore = 0;
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
        stretch: stretchFor(staffMetrics, isLast: isLast),
        caretIndex: _caretOnLine(
          symbolsBefore,
          staffMetrics.selectableSymbolCount,
          isLast: isLast,
        ),
        caretColor: caretColor,
      );
      symbolsBefore += staffRenderer.selectableSymbolCount;
      currentY += staffMetrics.lowerHeight;
      result.add(staffRenderer);
    }
    return result;
  }

  /// Where the caret falls on a line that already holds [symbolsBefore]
  /// notes, or null when it belongs to another line.
  ///
  /// A caret sitting exactly at the end of a line belongs to the start of the
  /// next one, since that is where the next note will actually land — except
  /// on the last line, where there is no next.
  int? _caretOnLine(
    int symbolsBefore,
    int symbolCount, {
    required bool isLast,
  }) {
    final caretIndex = this.caretIndex;
    if (caretIndex == null) return null;
    final onThisLine = caretIndex - symbolsBefore;
    if (onThisLine < 0) return null;
    if (onThisLine > symbolCount) return null;
    if (onThisLine == symbolCount && !isLast) return null;
    return onThisLine;
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
  double get _widthScale => distributeSymbolsToFullWidth
      ? (widgetWidth -
              contentHorizontalPadding * 2 -
              _maximumStaffHorizontalMarginSum) /
          metrics.maximumStaffObjectsWidth
      : (widgetWidth - _maximumStaffHorizontalMarginSum) / _maximumStaffWidth;

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

  /// A line is never pulled out further than this, so a line holding one or
  /// two notes stays a line of music rather than a row of islands.
  static const double _maxStretch = 2.5;

  /// How far a line's symbols are pulled apart so the line fills the page.
  ///
  /// The width each symbol claims is scaled, rather than the same gap being
  /// dropped between every pair, so justifying a line does not flatten the
  /// difference between a whole note and a sixteenth.
  @visibleForTesting
  double stretchFor(StaffMetrics staff, {required bool isLast}) {
    final justify = distributeSymbolsToFullWidth || (justifyLines && !isLast);
    if (!justify || staff.symbolCount < 2) return 1;

    final content = staff.objectsWidth;
    if (content <= 0) return 1;
    final available = (widgetWidth -
            contentHorizontalPadding * 2 -
            staff.horizontalMarginSum) /
        canvasScale;
    if (available <= content) return 1;
    return min(_maxStretch, available / content);
  }

  /// Renders the sheet music on the canvas.
  void render(Canvas canvas, Size size) {
    for (final staff in staffRenderers) {
      staff.render(canvas, size);
    }
  }
}
