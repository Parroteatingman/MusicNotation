import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/notes/tie_type.dart';
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
  void render(
    Canvas canvas,
    Size size, {
    bool suppressLeadingTie = false,
    bool suppressTrailingTie = false,
  }) {
    _renderStaffLine(canvas);
    for (final symbol in symbolRenderers) {
      symbol.render(canvas);
    }
    _renderBeams(canvas);
    _renderTies(
      canvas,
      suppressLeadingTie: suppressLeadingTie,
      suppressTrailingTie: suppressTrailingTie,
    );
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
    final beamGap = beamThickness * 0.8;
    // Staff space height for constraining beam slope
    final staffSpace = measureMetrics.staffLineThickness * 4;

    // Collect stem tip positions for each note
    final stemTips = <Offset>[];
    final stemRoots = <Offset>[];
    for (final nr in group) {
      stemTips.add(nr.note.stemTipOffset + nr.renderOffset);
      stemRoots.add(nr.note.stemRootOffset + nr.renderOffset);
    }

    final firstX = stemTips.first.dx;
    final lastX = stemTips.last.dx;
    final xSpan = lastX - firstX;

    // Calculate slanted beam line following note movement direction.
    // Use linear regression on stem root positions (note positions) to
    // determine the natural slope, then constrain per standard notation rules.
    double startBeamY, endBeamY;

    if (xSpan < 0.001) {
      // All notes at same X (shouldn't happen), use flat beam
      final avgTipY =
          stemTips.map((o) => o.dy).reduce((a, b) => a + b) / stemTips.length;
      startBeamY = avgTipY;
      endBeamY = avgTipY;
    } else {
      // Calculate slope from first and last stem root positions
      final firstRootY = stemRoots.first.dy;
      final lastRootY = stemRoots.last.dy;
      double slope = (lastRootY - firstRootY) / xSpan;

      // Constrain slope: max one staff space across the beam span
      final maxSlope = staffSpace / xSpan;
      slope = slope.clamp(-maxSlope, maxSlope);

      // Start from average tip Y, then apply slope centered on the group
      final avgTipY =
          stemTips.map((o) => o.dy).reduce((a, b) => a + b) / stemTips.length;
      final midX = (firstX + lastX) / 2;
      startBeamY = avgTipY + slope * (firstX - midX);
      endBeamY = avgTipY + slope * (lastX - midX);

      // Ensure beam doesn't cross any stem root
      if (stemUp) {
        final margin = group.first.note.note.margin.top;
        for (int i = 0; i < stemRoots.length; i++) {
          final t = (stemTips[i].dx - firstX) / xSpan;
          final beamAtNote = startBeamY + (endBeamY - startBeamY) * t;
          if (beamAtNote > stemRoots[i].dy - margin) {
            final shift = beamAtNote - (stemRoots[i].dy - margin);
            startBeamY -= shift;
            endBeamY -= shift;
          }
        }
      } else {
        final margin = group.first.note.note.margin.top;
        for (int i = 0; i < stemRoots.length; i++) {
          final t = (stemTips[i].dx - firstX) / xSpan;
          final beamAtNote = startBeamY + (endBeamY - startBeamY) * t;
          if (beamAtNote < stemRoots[i].dy + margin) {
            final shift = (stemRoots[i].dy + margin) - beamAtNote;
            startBeamY += shift;
            endBeamY += shift;
          }
        }
      }
    }

    // Draw stems from root to slanted beam inner edge
    final stemPaint = Paint()
      ..color = group.first.note.color
      ..strokeWidth = group.first.note.stemThickness;
    for (int i = 0; i < group.length; i++) {
      final t = xSpan > 0.001 ? (stemTips[i].dx - firstX) / xSpan : 0.0;
      final beamAtNote = startBeamY + (endBeamY - startBeamY) * t;
      final stemEndY = stemUp
          ? beamAtNote + beamThickness / 2
          : beamAtNote - beamThickness / 2;
      canvas.drawLine(
        stemRoots[i],
        Offset(stemTips[i].dx, stemEndY),
        stemPaint,
      );
    }

    // Draw slanted beam
    final beamPaint = Paint()
      ..color = group.first.note.color
      ..strokeWidth = beamThickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(firstX, startBeamY),
      Offset(lastX, endBeamY),
      beamPaint,
    );

    // Draw secondary beams (double beam for sixteenth notes and shorter)
    _drawPartialBeams(canvas, group, stemTips, startBeamY, endBeamY, firstX,
        xSpan, beamThickness, beamGap, beamPaint, stemUp, 1);

    // Draw tertiary beams (triple beam for thirty-second notes and shorter)
    _drawPartialBeams(canvas, group, stemTips, startBeamY, endBeamY, firstX,
        xSpan, beamThickness, beamGap, beamPaint, stemUp, 2);
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
    double startBeamY,
    double endBeamY,
    double firstX,
    double xSpan,
    double beamThickness,
    double beamGap,
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
              canvas,
              group,
              stemTips,
              startBeamY,
              endBeamY,
              firstX,
              xSpan,
              beamThickness,
              beamGap,
              beamPaint,
              stemUp,
              beamLevel,
              runStart,
              runEnd);
        }
        // If this note qualifies but we broke due to beat boundary, start new run
        runStart = qualifies ? i : -1;
      }
    }
  }

  /// Returns the beam Y at a given note index, following the slanted beam line.
  double _beamYAt(int noteIndex, List<Offset> stemTips, double startBeamY,
      double endBeamY, double firstX, double xSpan) {
    if (xSpan < 0.001) return startBeamY;
    final t = (stemTips[noteIndex].dx - firstX) / xSpan;
    return startBeamY + (endBeamY - startBeamY) * t;
  }

  /// Draws a single beam segment (full or partial stub) for a sub-run of notes.
  void _drawBeamSegment(
    Canvas canvas,
    List<NoteRenderer> group,
    List<Offset> stemTips,
    double startBeamY,
    double endBeamY,
    double firstX,
    double xSpan,
    double beamThickness,
    double beamGap,
    Paint beamPaint,
    bool stemUp,
    int beamLevel,
    int runStart,
    int runEnd,
  ) {
    double yAt(int idx) {
      final baseY =
          _beamYAt(idx, stemTips, startBeamY, endBeamY, firstX, xSpan);
      final beamOffset = (beamThickness + beamGap) * beamLevel;
      return stemUp ? baseY + beamOffset : baseY - beamOffset;
    }

    final beamSlope = xSpan < 0.001 ? 0.0 : (endBeamY - startBeamY) / xSpan;

    if (runStart == runEnd) {
      // Single note: draw a short partial beam stub
      final x = stemTips[runStart].dx;
      final y = yAt(runStart);
      // Point the stub toward the nearest neighboring note in the group.
      final bool pointRight;
      if (runStart == 0 && group.length > 1) {
        pointRight = stemUp;
      } else if (runStart == group.length - 1) {
        pointRight = !stemUp;
      } else {
        final prevDistance =
            (stemTips[runStart].dx - stemTips[runStart - 1].dx).abs();
        final nextDistance =
            (stemTips[runStart + 1].dx - stemTips[runStart].dx).abs();
        pointRight = nextDistance <= prevDistance;
      }
      final previousGap = runStart > 0
          ? (stemTips[runStart].dx - stemTips[runStart - 1].dx).abs()
          : 0.0;
      final nextGap = runStart < group.length - 1
          ? (stemTips[runStart + 1].dx - stemTips[runStart].dx).abs()
          : 0.0;
      final referenceGap = pointRight ? nextGap : previousGap;
      final partialLen = referenceGap > 0
          ? (referenceGap * 9.2).clamp(160.0, 272.0).toDouble()
          : 192.0;
      final startX = pointRight ? x : x - partialLen;
      final endX = pointRight ? x + partialLen : x;
      final startY = pointRight ? y : y - beamSlope * partialLen;
      final endY = pointRight ? y + beamSlope * partialLen : y;
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), beamPaint);
    } else {
      // Multiple notes: draw slanted beam between them
      canvas.drawLine(
        Offset(stemTips[runStart].dx, yAt(runStart)),
        Offset(stemTips[runEnd].dx, yAt(runEnd)),
        beamPaint,
      );
    }
  }

  List<NoteRenderer> get noteRenderers {
    final notes = <NoteRenderer>[];
    for (final symbol in symbolRenderers) {
      if (symbol is NoteRenderer) {
        notes.add(symbol);
      }
    }
    return notes;
  }

  NoteRenderer? get firstNoteRenderer {
    for (final symbol in symbolRenderers) {
      if (symbol is NoteRenderer) return symbol;
    }
    return null;
  }

  NoteRenderer? get lastNoteRenderer {
    for (int i = symbolRenderers.length - 1; i >= 0; i--) {
      final symbol = symbolRenderers[i];
      if (symbol is NoteRenderer) return symbol;
    }
    return null;
  }

  void _renderTies(
    Canvas canvas, {
    required bool suppressLeadingTie,
    required bool suppressTrailingTie,
  }) {
    final noteRenderers = this.noteRenderers;

    for (var i = 0; i < noteRenderers.length; i++) {
      final current = noteRenderers[i];
      final tie = current.note.note.tie;
      if (tie == null || !tie.isStart) continue;

      final next = i + 1 < noteRenderers.length ? noteRenderers[i + 1] : null;
      if (next != null) {
        _drawTie(canvas, current, next);
      } else if (!suppressTrailingTie) {
        _drawTie(canvas, current, null);
      }
    }

    if (noteRenderers.isNotEmpty &&
        noteRenderers.first.note.note.tie == TieType.stop &&
        !suppressLeadingTie) {
      _drawLeadingTie(canvas, noteRenderers.first);
    }
  }

  void _drawTie(Canvas canvas, NoteRenderer start, NoteRenderer? end) {
    final startBounds = start.noteHeadBounds;
    final endBounds = end?.noteHeadBounds;
    final tieBelow = end != null && start.note.isStemUp != end.note.isStemUp
        ? false
        : start.note.isStemUp;
    final baselineY = tieBelow
        ? startBounds.bottom + Constants.staffSpace * 0.35
        : startBounds.top - Constants.staffSpace * 0.35;
    final archHeight = Constants.staffSpace * 0.7 * (tieBelow ? 1 : -1);
    final startX = startBounds.right - Constants.staffSpace * 0.1;
    final endX = endBounds != null
        ? endBounds.left + Constants.staffSpace * 0.1
        : measureOriginX + width - Constants.staffSpace * 0.3;
    final controlX = (startX + endX) / 2;
    final controlY = baselineY + archHeight;

    final tiePaint = Paint()
      ..color = start.note.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = measureMetrics.staffLineThickness * 2
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(startX, baselineY)
      ..quadraticBezierTo(controlX, controlY, endX, baselineY);

    canvas.drawPath(path, tiePaint);
  }

  void _drawLeadingTie(Canvas canvas, NoteRenderer end) {
    final endBounds = end.noteHeadBounds;
    final tieBelow = end.note.isStemUp;
    final baselineY = tieBelow
        ? endBounds.bottom + Constants.staffSpace * 0.35
        : endBounds.top - Constants.staffSpace * 0.35;
    final archHeight = Constants.staffSpace * 0.7 * (tieBelow ? 1 : -1);
    final startX = measureOriginX + Constants.staffSpace * 0.2;
    final endX = endBounds.left + Constants.staffSpace * 0.1;
    final controlX = (startX + endX) / 2;
    final controlY = baselineY + archHeight;

    final tiePaint = Paint()
      ..color = end.note.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = measureMetrics.staffLineThickness * 2
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(startX, baselineY)
      ..quadraticBezierTo(controlX, controlY, endX, baselineY);

    canvas.drawPath(path, tiePaint);
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
      return sr.renderOffset.dx +
          sr.note.margin.left / scale +
          sr.note.noteHeadWidth;
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
    canvas.drawLine(Offset(firstX, bracketY + hookLen),
        Offset(firstX, bracketY), bracketPaint);
    // Right hook
    canvas.drawLine(Offset(lastX, bracketY + hookLen), Offset(lastX, bracketY),
        bracketPaint);

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
    textPainter.paint(
        canvas,
        Offset(centerX - textPainter.width / 2,
            bracketY - textPainter.height / 2));

    // Bracket lines with gap for number
    final gapHalf = textPainter.width / 2 + Constants.staffSpace * 0.2;
    if (centerX - gapHalf > firstX) {
      canvas.drawLine(Offset(firstX, bracketY),
          Offset(centerX - gapHalf, bracketY), bracketPaint);
    }
    if (centerX + gapHalf < lastX) {
      canvas.drawLine(Offset(centerX + gapHalf, bracketY),
          Offset(lastX, bracketY), bracketPaint);
    }
  }
}
