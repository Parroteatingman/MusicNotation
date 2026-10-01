import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/chord_note.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/sheet_symbol_box.dart';
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
    this.spreadOnlyNotes = false,
    this.caretIndex,
    this.caretColor,
    this.spaceBelowStaff = 0,
  });

  /// Room kept under every staff, in canvas units, on top of what its own
  /// notes need: where a caller writes under the notes (see
  /// [symbolBoxes]).
  final double spaceBelowStaff;

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

  /// When a line is pulled out, pull only its notes and rests apart. A clef,
  /// a key or time signature or a barline spread along with them opens a hole
  /// the width of the signature beside it; an engraver sets them at their own
  /// width and gives the room to the music.
  final bool spreadOnlyNotes;

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
      currentY += staffMetrics.lowerHeight + spaceBelowStaff;
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

  /// The sum of the heights of all the staffs, with the room kept under
  /// each.
  double get _staffsHeightsSum => spaceBelowStaff == 0
      ? metrics.staffsHeightSum
      : metrics.staffsHeightSum +
          spaceBelowStaff * metrics.staffsMetricses.length;

  /// Every note, rest and chord where it is drawn, in the widget's
  /// coordinates (the canvas is only scaled, never moved), with the lines
  /// of its staff.
  List<SheetSymbolBox> symbolBoxes() {
    final scale = canvasScale;
    final toWidget = Matrix4.diagonal3Values(scale, scale, 1).storage;
    final staffs = staffRenderers;
    final staffMetricses = metrics.staffsMetricses.toList();
    final boxes = <SheetSymbolBox>[];
    var centerY = _upperPaddingOnCanvas;
    var order = 0;
    var measureIndex = 0;
    for (var line = 0; line < staffs.length; line++) {
      centerY += staffMetricses[line].upperHeight;
      final staffTop = (centerY - Constants.staffSpace * 2) * scale;
      final staffBottom = (centerY + Constants.staffSpace * 2) * scale;
      for (final measure in staffs[line].measureRendereres) {
        final inks = measure.symbolInkBottoms();
        final measureLeft = measure.measureOriginX * scale;
        final measureRight = (measure.measureOriginX + measure.width) * scale;
        for (var i = 0; i < measure.symbolRenderers.length; i++) {
          final symbol = measure.symbolRenderers[i];
          SheetSymbolKind kind;
          List<Path> heads;
          Rect? label;
          if (symbol is NoteRenderer) {
            kind = SheetSymbolKind.note;
            heads = [symbol.noteHeadRenderPath];
            label = symbol.chordLabelRect;
          } else if (symbol is ChordNoteRenderer) {
            kind = SheetSymbolKind.chord;
            heads = symbol.noteHeadRenderPaths;
          } else if (symbol is RestRenderer) {
            kind = SheetSymbolKind.rest;
            heads = [symbol.renderPath];
            label = symbol.chordLabelRect;
          } else {
            continue;
          }
          if (heads.isEmpty) continue;
          final drawn = [for (final head in heads) head.transform(toWidget)];
          var inkBottom = inks[i] * scale;
          for (final head in drawn) {
            final bottom = head.getBounds().bottom;
            if (bottom > inkBottom) inkBottom = bottom;
          }
          boxes.add(SheetSymbolBox(
            order: order++,
            line: line,
            kind: kind,
            heads: drawn,
            staffTop: staffTop,
            staffBottom: staffBottom,
            inkBottom: inkBottom,
            measure: measureIndex,
            measureLeft: measureLeft,
            measureRight: measureRight,
            chordLabel: label == null
                ? null
                : Rect.fromLTRB(label.left * scale, label.top * scale, label.right * scale, label.bottom * scale),
          ));
        }
        measureIndex++;
      }
      centerY += staffMetricses[line].lowerHeight + spaceBelowStaff;
    }
    return boxes;
  }

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

    final fixed = spreadOnlyNotes ? staff.fixedWidth : 0.0;
    final content = staff.objectsWidth - fixed;
    if (content <= 0) return 1;
    // A line is pulled out to the same margin on the right as it starts
    // from on the left. When the page is drawn at the size its height allows
    // and centred, that is the widest line's width, not the page's: pulled
    // out to the page's width from a centred start, a line ran off the right.
    final leftPadding = _leftPaddingOnCanvas * canvasScale;
    final available =
        (widgetWidth - leftPadding * 2 - staff.horizontalMarginSum) /
                canvasScale -
            fixed;
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
