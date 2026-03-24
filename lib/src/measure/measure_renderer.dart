import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// The renderer for a measure in sheet music.
class MeasureRenderer {
  const MeasureRenderer(
    this.symbolRenderers,
    this.measureMetrics,
    this.layout, {
    required this.measureOriginX,
    required this.staffLineCenterY,
  });

  final List<MusicalSymbolRenderer> symbolRenderers;
  final MeasureMetrics measureMetrics;
  final double measureOriginX;
  final double staffLineCenterY;

  /// Performs a hit test at the given [position] and returns the corresponding [MusicalSymbolRenderer].
  ///
  /// Returns `null` if no symbol is hit.
  MusicalSymbolRenderer? hitTest(Offset position) {
    for (final object in symbolRenderers) {
      if (object.isHit(position)) {
        return object;
      }
    }
    return null;
  }

  /// Renders the measure on the given [canvas] with the specified [size].
  void render(Canvas canvas, Size size) {
    _renderStaffLine(canvas);
    for (final symbol in symbolRenderers) {
      symbol.render(canvas);
    }
    _renderBeams(canvas);
    _renderTupletBrackets(canvas);
  }

  void _renderStaffLine(Canvas canvas) {
    final initX = measureOriginX;
    final staffLineHeights = [
      staffLineCenterY - Constants.staffSpace * 2,
      staffLineCenterY - Constants.staffSpace,
      staffLineCenterY,
      staffLineCenterY + Constants.staffSpace,
      staffLineCenterY + Constants.staffSpace * 2,
    ];
    for (final height in staffLineHeights) {
      canvas.drawLine(
        Offset(initX, height),
        Offset(initX + width, height),
        Paint()
          ..color = layout.lineColor
          ..strokeWidth = measureMetrics.staffLineThickness,
      );
    }
  }

  /// Draws beams connecting consecutive beamed notes.
  void _renderBeams(Canvas canvas) {
    final noteRenderers = <NoteRenderer>[];
    final noteIndices = <int>[];
    for (int i = 0; i < symbolRenderers.length; i++) {
      if (symbolRenderers[i] is NoteRenderer) {
        noteRenderers.add(symbolRenderers[i] as NoteRenderer);
        noteIndices.add(i);
      }
    }

    // Find groups of consecutive beamed notes, split by beamGroupId
    List<List<NoteRenderer>> groups = [];
    List<NoteRenderer> currentGroup = [];
    int currentGroupId = -1;

    for (final nr in noteRenderers) {
      if (nr.note.note.isBeamed) {
        final gid = nr.note.note.beamGroupId;
        if (currentGroup.isNotEmpty && gid != currentGroupId) {
          if (currentGroup.length >= 2) {
            groups.add(List.of(currentGroup));
          }
          currentGroup.clear();
        }
        currentGroup.add(nr);
        currentGroupId = gid;
      } else {
        if (currentGroup.length >= 2) {
          groups.add(List.of(currentGroup));
        }
        currentGroup.clear();
        currentGroupId = -1;
      }
    }
    if (currentGroup.length >= 2) {
      groups.add(List.of(currentGroup));
    }

    for (final group in groups) {
      _drawBeamGroup(canvas, group);
    }
  }

  void _drawBeamGroup(Canvas canvas, List<NoteRenderer> group) {
    if (group.length < 2) return;

    final bool stemUp = group.first.note.isStemUp;
    final beamThickness = measureMetrics.staffLineThickness * 5;

    // Collect stem tip positions for each note
    final stemTips = <Offset>[];
    final stemRoots = <Offset>[];
    for (final nr in group) {
      stemTips.add(nr.note.stemTipOffset + nr.renderOffset);
      stemRoots.add(nr.note.stemRootOffset + nr.renderOffset);
    }

    // Calculate beam Y: use average stem tip Y to avoid excessive stem lengths.
    // Then clamp so every stem is at least minStemLength from its root.
    final avgTipY = stemTips.map((o) => o.dy).reduce((a, b) => a + b) / stemTips.length;
    double beamY;
    if (stemUp) {
      // Beam above notes: use the minimum (highest) tip, but bias toward average
      final minTipY = stemTips.map((o) => o.dy).reduce(math.min);
      beamY = (minTipY + avgTipY) / 2;
      // Ensure beam is above all stem roots
      final maxRootY = stemRoots.map((o) => o.dy).reduce(math.max);
      if (beamY > maxRootY) beamY = maxRootY - group.first.note.note.margin.top;
    } else {
      final maxTipY = stemTips.map((o) => o.dy).reduce(math.max);
      beamY = (maxTipY + avgTipY) / 2;
      final minRootY = stemRoots.map((o) => o.dy).reduce(math.min);
      if (beamY < minRootY) beamY = minRootY + group.first.note.note.margin.top;
    }

    final firstX = stemTips.first.dx;
    final lastX = stemTips.last.dx;

    // Draw stems from root to beam inner edge (not past it)
    final stemPaint = Paint()
      ..color = group.first.note.color
      ..strokeWidth = group.first.note.stemThickness;
    // Stem ends at the inner edge of beam: for stem-up, beam is above,
    // inner edge = beamY + beamThickness/2; for stem-down, inner edge = beamY - beamThickness/2
    final stemEndY = stemUp
        ? beamY + beamThickness / 2
        : beamY - beamThickness / 2;
    for (int i = 0; i < group.length; i++) {
      canvas.drawLine(
        stemRoots[i],
        Offset(stemTips[i].dx, stemEndY),
        stemPaint,
      );
    }

    // Draw beam (thick horizontal line) on top of stems
    final beamPaint = Paint()
      ..color = group.first.note.color
      ..strokeWidth = beamThickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(firstX, beamY),
      Offset(lastX, beamY),
      beamPaint,
    );

    // Draw secondary beams (double beam for sixteenth notes and shorter)
    _drawPartialBeams(canvas, group, stemTips, beamY, beamThickness, beamPaint, stemUp, 1);

    // Draw tertiary beams (triple beam for thirty-second notes and shorter)
    _drawPartialBeams(canvas, group, stemTips, beamY, beamThickness, beamPaint, stemUp, 2);
  }

  /// Whether a note duration qualifies for the given beam level.
  /// Level 1 = secondary beam (sixteenth+), level 2 = tertiary beam (thirty-second+).
  bool _qualifiesForBeamLevel(NoteDuration dur, int level) {
    if (level == 1) {
      return dur == NoteDuration.sixteenth ||
          dur == NoteDuration.thirtySecond ||
          dur == NoteDuration.sixtyFourth ||
          dur == NoteDuration.hundredsTwentyEighth;
    } else if (level == 2) {
      return dur == NoteDuration.thirtySecond ||
          dur == NoteDuration.sixtyFourth ||
          dur == NoteDuration.hundredsTwentyEighth;
    }
    return false;
  }

  /// Draws partial (broken) beams for sub-runs of notes that qualify for
  /// the given beam level within a beam group.
  /// Breaks secondary beams at beat boundaries and tertiary beams at half-beat
  /// boundaries, following standard music notation rules.
  void _drawPartialBeams(
    Canvas canvas,
    List<NoteRenderer> group,
    List<Offset> stemTips,
    double beamY,
    double beamThickness,
    Paint beamPaint,
    bool stemUp,
    int beamLevel,
  ) {
    int runStart = -1;
    for (int i = 0; i <= group.length; i++) {
      final qualifies = i < group.length &&
          _qualifiesForBeamLevel(group[i].note.note.noteDuration, beamLevel);

      // Check if a beat boundary should break the beam at this level
      bool beatBreak = false;
      if (qualifies && runStart != -1 && i > 0 && i < group.length) {
        final prevBeat = group[i - 1].note.note.beatPosition;
        final currBeat = group[i].note.note.beatPosition;
        if (beamLevel == 1) {
          // Secondary beam: break at beat boundaries (integer positions)
          beatBreak = prevBeat.floor() != currBeat.floor();
        } else if (beamLevel >= 2) {
          // Tertiary beam: break at half-beat boundaries
          beatBreak = (prevBeat * 2).floor() != (currBeat * 2).floor();
        }
      }

      if (qualifies && !beatBreak) {
        if (runStart == -1) runStart = i;
      } else {
        if (runStart != -1) {
          final runEnd = beatBreak ? i - 1 : i - 1;
          _drawBeamSegment(
              canvas, group, stemTips, beamY, beamThickness, beamPaint,
              stemUp, beamLevel, runStart, runEnd);
        }
        // If this note qualifies but we broke due to beat boundary, start new run
        runStart = qualifies ? i : -1;
      }
    }
  }

  /// Draws a single beam segment (full or partial stub) for a sub-run of notes.
  void _drawBeamSegment(
    Canvas canvas,
    List<NoteRenderer> group,
    List<Offset> stemTips,
    double beamY,
    double beamThickness,
    Paint beamPaint,
    bool stemUp,
    int beamLevel,
    int runStart,
    int runEnd,
  ) {
    final y = stemUp
        ? beamY + beamThickness * 1.5 * beamLevel
        : beamY - beamThickness * 1.5 * beamLevel;

    if (runStart == runEnd) {
      // Single note: draw a short partial beam stub
      final x = stemTips[runStart].dx;
      const partialLen = 8.0;
      // Point stub toward the neighboring notes in the beam group
      final bool pointRight = runStart == 0 ||
          (runStart > 0 &&
              group[runStart].note.note.beatPosition.floor() !=
                  group[runStart - 1].note.note.beatPosition.floor());
      final startX = pointRight ? x : x - partialLen;
      final endX = pointRight ? x + partialLen : x;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), beamPaint);
    } else {
      // Multiple notes: draw full beam between them
      canvas.drawLine(
        Offset(stemTips[runStart].dx, y),
        Offset(stemTips[runEnd].dx, y),
        beamPaint,
      );
    }
  }

  final SheetMusicLayout layout;

  /// The width of the measure.
  double get width =>
      measureMetrics.objectsWidth + measureMetrics.horizontalMarginSum / scale;

  /// The scale of the measure.
  double get scale => layout.canvasScale;

  /// Gets the tuplet value for any symbol renderer (Note or Rest).
  int? _getTuplet(MusicalSymbolRenderer sr) {
    if (sr is NoteRenderer) return sr.note.note.tuplet;
    if (sr is RestRenderer) return sr.restMetrics.rest.tuplet;
    return null;
  }

  /// Renders tuplet brackets (e.g., triplet "3") above/below note/rest groups.
  void _renderTupletBrackets(Canvas canvas) {
    // Collect only note/rest renderers (skip clef, key sig, etc.)
    final musicRenderers = <MusicalSymbolRenderer>[];
    for (final sr in symbolRenderers) {
      if (sr is NoteRenderer || sr is RestRenderer) musicRenderers.add(sr);
    }

    // Group consecutive symbols with the same non-null tuplet value
    List<List<MusicalSymbolRenderer>> tupletGroups = [];
    List<MusicalSymbolRenderer> currentGroup = [];
    int? currentTuplet;

    for (final sr in musicRenderers) {
      final t = _getTuplet(sr);
      if (t != null && t == currentTuplet) {
        currentGroup.add(sr);
      } else {
        if (currentGroup.length >= 2 && currentTuplet != null) {
          tupletGroups.add(List.of(currentGroup));
        }
        if (t != null) {
          currentGroup = [sr];
          currentTuplet = t;
        } else {
          currentGroup = [];
          currentTuplet = null;
        }
      }
    }
    if (currentGroup.length >= 2 && currentTuplet != null) {
      tupletGroups.add(List.of(currentGroup));
    }

    for (final group in tupletGroups) {
      _drawTupletBracket(canvas, group);
    }
  }

  /// Get the left X of a symbol renderer for bracket drawing.
  double _getSymbolLeftX(MusicalSymbolRenderer sr) {
    if (sr is NoteRenderer) {
      return sr.renderOffset.dx + sr.note.margin.left / scale;
    }
    if (sr is RestRenderer) {
      return sr.renderArea.left;
    }
    return 0;
  }

  /// Get the right X of a symbol renderer for bracket drawing.
  double _getSymbolRightX(MusicalSymbolRenderer sr) {
    if (sr is NoteRenderer) {
      return sr.renderOffset.dx + sr.note.margin.left / scale + sr.note.noteHeadWidth;
    }
    if (sr is RestRenderer) {
      return sr.renderArea.right;
    }
    return 0;
  }

  void _drawTupletBracket(Canvas canvas, List<MusicalSymbolRenderer> group) {
    if (group.isEmpty) return;
    final tupletNumber = _getTuplet(group.first) ?? 3;

    // Determine stem direction from the first note in the group
    bool stemUp = true;
    for (final sr in group) {
      if (sr is NoteRenderer) {
        stemUp = sr.note.isStemUp;
        break;
      }
    }

    final firstX = _getSymbolLeftX(group.first);
    final lastX = _getSymbolRightX(group.last);
    final centerX = (firstX + lastX) / 2;

    // Calculate bracket Y position
    double bracketY;
    if (stemUp) {
      double minY = double.infinity;
      for (final sr in group) {
        if (sr is NoteRenderer) {
          final tipY = sr.note.stemTipOffset.dy + sr.renderOffset.dy;
          if (tipY < minY) minY = tipY;
        } else if (sr is RestRenderer) {
          final topY = sr.renderArea.top;
          if (topY < minY) minY = topY;
        }
      }
      bracketY = minY - Constants.staffSpace * 0.8;
    } else {
      double maxY = double.negativeInfinity;
      for (final sr in group) {
        if (sr is NoteRenderer) {
          final tipY = sr.note.stemTipOffset.dy + sr.renderOffset.dy;
          if (tipY > maxY) maxY = tipY;
        } else if (sr is RestRenderer) {
          final botY = sr.renderArea.bottom;
          if (botY > maxY) maxY = botY;
        }
      }
      bracketY = maxY + Constants.staffSpace * 0.8;
    }

    final bracketPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = measureMetrics.staffLineThickness * 2
      ..style = PaintingStyle.stroke;

    final hookLen = Constants.staffSpace * 0.4 * (stemUp ? 1 : -1);

    // Left hook
    canvas.drawLine(Offset(firstX, bracketY + hookLen), Offset(firstX, bracketY), bracketPaint);
    // Right hook
    canvas.drawLine(Offset(lastX, bracketY + hookLen), Offset(lastX, bracketY), bracketPaint);

    // Draw number
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$tupletNumber',
        style: TextStyle(
          color: Colors.black,
          fontSize: Constants.staffSpace * 0.9,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(centerX - textPainter.width / 2, bracketY - textPainter.height / 2));

    // Bracket lines with gap for number
    final gapHalf = textPainter.width / 2 + Constants.staffSpace * 0.2;
    if (centerX - gapHalf > firstX) {
      canvas.drawLine(Offset(firstX, bracketY), Offset(centerX - gapHalf, bracketY), bracketPaint);
    }
    if (centerX + gapHalf < lastX) {
      canvas.drawLine(Offset(centerX + gapHalf, bracketY), Offset(lastX, bracketY), bracketPaint);
    }
  }
}
