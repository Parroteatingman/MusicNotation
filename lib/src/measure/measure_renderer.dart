import 'dart:math';

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/measure/barline.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/chord_note.dart';
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
    this.stretch = 1,
  });

  final List<MusicalSymbolRenderer> symbolRenderers;
  final MeasureMetrics measureMetrics;
  final double measureOriginX;
  final double staffLineCenterY;

  /// How far the symbols of this measure were pulled apart to fill the line.
  final double stretch;

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

  int? hitTestSelectableIndex(Offset position, int startIndex) {
    var selectableIndex = startIndex;
    for (final object in symbolRenderers) {
      final isSelectable = object is NoteRenderer || object is RestRenderer;
      if (isSelectable && object.isHit(position)) {
        return selectableIndex;
      }
      if (isSelectable) selectableIndex++;
    }
    return null;
  }

  /// Where each note and rest of this measure begins, in order. The caret
  /// stands at one of these.
  List<double> get selectableSymbolXs => [
        for (final symbol in symbolRenderers)
          if (symbol is NoteRenderer || symbol is RestRenderer) symbol.symbolX,
      ];

  int get selectableSymbolCount => symbolRenderers
      .where((object) => object is NoteRenderer || object is RestRenderer)
      .length;

  /// Renders the measure on the given [canvas] with the specified [size].
  void render(
    Canvas canvas,
    Size size, {
    bool suppressLeadingTie = false,
    bool suppressTrailingTie = false,
    bool drawStaffLines = true,
  }) {
    // The staff draws its own lines right across when it is extended to the
    // full width; drawing them here as well would lay a second half-opaque
    // stroke over the part that holds notes, and the line would change shade
    // where the music stops.
    if (drawStaffLines) _renderStaffLine(canvas);
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
    for (final group in _beamGroups()) {
      _drawBeamGroup(canvas, group);
    }
  }

  /// The runs of consecutive beamed notes, split by beamGroupId.
  List<List<NoteRenderer>> _beamGroups() {
    final groups = <List<NoteRenderer>>[];
    final currentGroup = <NoteRenderer>[];
    int currentGroupId = -1;

    for (final symbol in symbolRenderers) {
      if (symbol is! NoteRenderer) continue;
      if (symbol.note.note.isBeamed) {
        final gid = symbol.note.note.beamGroupId;
        if (currentGroup.isNotEmpty && gid != currentGroupId) {
          if (currentGroup.length >= 2) {
            groups.add(List.of(currentGroup));
          }
          currentGroup.clear();
        }
        currentGroup.add(symbol);
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
    return groups;
  }

  /// Where a beamed group's beam lies.
  _BeamLine _beamLineOf(List<NoteRenderer> group) {
    final metadata = measureMetrics.metadata;
    final staffSpace = metadata.staffSpace;

    // Every note of a beamed group shares one stem direction; the caller has
    // already settled it, so the first note speaks for the group.
    final stemUp = group.first.note.isStemUp;

    // Where each stem leaves its note head. Stems are vertical, so these
    // carry the x of the whole stem as well.
    final stemRoots = <Offset>[
      for (final nr in group) nr.note.stemRootOffset + nr.renderOffset,
    ];
    final firstX = stemRoots.first.dx;
    final xSpan = stemRoots.last.dx - firstX;

    // The beam follows the outer note heads, but never slants more than a
    // staff space across the group — Gould's rule, and what stops a wide leap
    // from tipping the beam off the staff.
    var slope = 0.0;
    if (xSpan > 0.001) {
      final natural = (stemRoots.last.dy - stemRoots.first.dy) / xSpan;
      final maxSlope = staffSpace / xSpan;
      slope = natural.clamp(-maxSlope, maxSlope).toDouble();
    }

    // Hang the beam off whichever note would otherwise be left with the
    // shortest stem, so no stem in the group falls under its proper length.
    final standardStem = metadata.standardStemLength;
    var beamY = stemUp ? double.infinity : double.negativeInfinity;
    for (final root in stemRoots) {
      final wanted = stemUp
          ? root.dy - standardStem - slope * (root.dx - firstX)
          : root.dy + standardStem - slope * (root.dx - firstX);
      beamY = stemUp ? min(beamY, wanted) : max(beamY, wanted);
    }
    return _BeamLine(
      stemUp: stemUp,
      stemRoots: stemRoots,
      startY: beamY,
      slope: slope,
    );
  }

  void _drawBeamGroup(Canvas canvas, List<NoteRenderer> group) {
    if (group.length < 2) return;

    final metadata = measureMetrics.metadata;
    final beamThickness = metadata.beamThickness;
    final beamGap = metadata.beamSpacing;

    final beam = _beamLineOf(group);
    final stemUp = beam.stemUp;
    final stemRoots = beam.stemRoots;
    final firstX = beam.firstX;
    final lastX = beam.lastX;
    final xSpan = lastX - firstX;
    final startBeamY = beam.startY;
    final endBeamY = beam.endY;

    double beamYAtX(double x) => beam.yAt(x);

    // Stems run from the head to the inner edge of the beam.
    final stemPaint = Paint()
      ..color = group.first.note.color
      ..strokeWidth = group.first.note.stemThickness;
    for (final root in stemRoots) {
      final beamAtNote = beamYAtX(root.dx);
      final stemEndY = stemUp
          ? beamAtNote + beamThickness / 2
          : beamAtNote - beamThickness / 2;
      canvas.drawLine(root, Offset(root.dx, stemEndY), stemPaint);
    }

    final beamPaint = Paint()
      ..color = group.first.note.color
      ..strokeWidth = beamThickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(firstX, startBeamY),
      Offset(lastX, endBeamY),
      beamPaint,
    );

    // Sixteenths and shorter carry further beams, set inside the first one —
    // that is, on the side the note heads are on.
    _drawPartialBeams(canvas, group, stemRoots, startBeamY, endBeamY, firstX,
        xSpan, beamThickness, beamGap, beamPaint, stemUp, 1);
    _drawPartialBeams(canvas, group, stemRoots, startBeamY, endBeamY, firstX,
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
      // A stub runs a staff space, or half the way to its neighbour when the
      // notes stand closer than that.
      final staffSpace = measureMetrics.metadata.staffSpace;
      final partialLen =
          referenceGap > 0 ? min(staffSpace, referenceGap / 2) : staffSpace;
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

  /// The measure opens with `‖:` right on its barline — nothing set before
  /// it — so the `‖:` is that barline.
  bool get startsWithRepeat =>
      symbolRenderers.isNotEmpty &&
      symbolRenderers.first is RepeatStartRenderer;

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
  double get width {
    final fixed = layout.spreadOnlyNotes ? measureMetrics.fixedWidth : 0.0;
    return fixed +
        (measureMetrics.objectsWidth - fixed) * stretch +
        measureMetrics.horizontalMarginSum / scale;
  }

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
    for (final group in _tupletGroups()) {
      _drawTupletBracket(canvas, group);
    }
  }

  /// The runs of notes and rests under one tuplet bracket.
  List<List<MusicalSymbolRenderer>> _tupletGroups() {
    // Collect only note/rest renderers (skip clef, key sig, etc.)
    final musicRenderers = <MusicalSymbolRenderer>[];
    for (final sr in symbolRenderers) {
      if (sr is NoteRenderer || sr is RestRenderer) musicRenderers.add(sr);
    }

    // Group consecutive symbols with the same non-null tuplet value. Do not
    // merge adjacent tuplets into one long bracket; a triplet run of six
    // symbols should draw two separate "3" brackets.
    final tupletGroups = <List<MusicalSymbolRenderer>>[];
    final currentGroup = <MusicalSymbolRenderer>[];
    int? currentTuplet;

    void flushCurrentGroup() {
      if (currentGroup.length >= 2 && currentTuplet != null) {
        tupletGroups.add(List.of(currentGroup));
      }
      currentGroup.clear();
      currentTuplet = null;
    }

    for (final sr in musicRenderers) {
      final t = _getTuplet(sr);
      if (t == null || t <= 1) {
        flushCurrentGroup();
        continue;
      }

      if (currentGroup.isNotEmpty && t != currentTuplet) {
        flushCurrentGroup();
      }

      currentTuplet = t;
      currentGroup.add(sr);

      if (currentGroup.length >= t) {
        flushCurrentGroup();
      }
    }
    flushCurrentGroup();
    return tupletGroups;
  }

  /// Which side of a tuplet group its bracket goes, and at what height:
  /// beyond the stem tips (or the rests), on the stem side of the first note.
  _BracketPlace _tupletBracketPlace(List<MusicalSymbolRenderer> group) {
    var stemUp = true;
    for (final sr in group) {
      if (sr is NoteRenderer) {
        stemUp = sr.note.isStemUp;
        break;
      }
    }
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
      return _BracketPlace(stemUp: true, y: minY - Constants.staffSpace * 0.8);
    }
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
    return _BracketPlace(stemUp: false, y: maxY + Constants.staffSpace * 0.8);
  }

  /// How far down each of [symbolRenderers] reaches, in canvas units: the
  /// symbol itself with its stem and flag, the beam under it, the tuplet
  /// bracket under it. Anything written under the notes starts below this.
  List<double> symbolInkBottoms() {
    final bottoms = <double>[
      for (final symbol in symbolRenderers)
        if (symbol is NoteRenderer)
          symbol.staffLineCenterY + symbol.note.lowerHeight
        else if (symbol is ChordNoteRenderer)
          symbol.staffLineCenterY + symbol.note.lowerHeight
        else if (symbol is RestRenderer)
          symbol.renderArea.bottom
        else
          double.negativeInfinity,
    ];
    void lower(MusicalSymbolRenderer symbol, double y) {
      final i = symbolRenderers.indexOf(symbol);
      if (i >= 0 && y > bottoms[i]) bottoms[i] = y;
    }

    final beamThickness = measureMetrics.metadata.beamThickness;
    for (final group in _beamGroups()) {
      final beam = _beamLineOf(group);
      if (beam.stemUp) continue;
      for (var i = 0; i < group.length; i++) {
        lower(group[i], beam.yAt(beam.stemRoots[i].dx) + beamThickness / 2);
      }
    }
    for (final group in _tupletGroups()) {
      final place = _tupletBracketPlace(group);
      if (place.stemUp) continue;
      for (final symbol in group) {
        // The bracket's number hangs about half a space either side of it.
        lower(symbol, place.y + Constants.staffSpace * 0.55);
      }
    }
    return bottoms;
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

    // The bracket and its number take the first note's colour, as its beam
    // does, so they still show on a dark staff.
    Color ink = Colors.black;
    for (final sr in group) {
      if (sr is NoteRenderer) {
        ink = sr.note.color;
        break;
      }
    }
    final place = _tupletBracketPlace(group);
    final stemUp = place.stemUp;
    final bracketY = place.y;

    final firstX = _getSymbolLeftX(group.first);
    final lastX = _getSymbolRightX(group.last);
    final centerX = (firstX + lastX) / 2;

    final bracketPaint = Paint()
      ..color = ink
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
          color: ink,
          fontSize: Constants.staffSpace * 0.9,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
          // Same family as the chord symbols: engraved tuplet numerals are
          // serif italic, and leaving it null makes widget tests paint a box.
          fontFamily: 'serif',
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

/// Where a beamed group's beam lies: the side its stems go, where each stem
/// leaves its head, and the line of the beam.
class _BeamLine {
  const _BeamLine({
    required this.stemUp,
    required this.stemRoots,
    required this.startY,
    required this.slope,
  });

  final bool stemUp;
  final List<Offset> stemRoots;
  final double startY;
  final double slope;

  double get firstX => stemRoots.first.dx;
  double get lastX => stemRoots.last.dx;

  /// The beam's middle at [x].
  double yAt(double x) => startY + slope * (x - firstX);

  double get endY => yAt(lastX);
}

/// Which side of its notes a tuplet bracket goes, and at what height.
class _BracketPlace {
  const _BracketPlace({required this.stemUp, required this.y});

  final bool stemUp;
  final double y;
}
