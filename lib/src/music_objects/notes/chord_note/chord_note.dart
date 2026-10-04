import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/extension/list_extension.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/accidental_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/chord_note_part.dart';
import 'package:simple_sheet_music/src/music_objects/notes/legerline.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/notes/noteflag_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/notehead_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/positions.dart';
import 'package:simple_sheet_music/src/music_objects/notes/stem_direction.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// Represents a chord note in sheet music.
class ChordNote implements MusicalSymbol {
  const ChordNote(
    this.noteParts, {
    this.noteDuration = NoteDuration.quarter,
    this.margin = const EdgeInsets.all(10),
    this.color = Colors.black,
    this.stemDirection,
  });

  @override
  final EdgeInsets margin;

  /// The stem direction of the chord note.
  final StemDirection? stemDirection;

  /// The list of chord note parts that make up the chord note.
  final List<ChordNotePart> noteParts;

  @override
  final Color color;

  /// The duration of the chord note.
  final NoteDuration noteDuration;

  /// The type of note head for the chord note.
  NoteHeadType get noteHeadType => noteDuration.noteHeadType;

  /// The key used to retrieve the path for the note head.
  String get noteHeadPathKey => noteHeadType.pathKey;

  @override
  MusicalSymbolMetrics setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) =>
      ChordNoteMetrics(
        this,
        context,
        metadata,
        paths,
      );
}

/// Represents the metrics (size and position) of a [ChordNote].
class ChordNoteMetrics implements MusicalSymbolMetrics {
  const ChordNoteMetrics(
    this.note,
    this.context,
    this.metadata,
    this.path,
  );

  final MusicalContext context;
  final GlyphMetadata metadata;
  final GlyphPaths path;
  final ChordNote note;

  List<ChordNotePart> get _noteParts => note.noteParts;

  List<ChordNoteHeadMetrics> get _noteHeads {
    final displaced = _displacedHeads;
    return [
      for (var i = 0; i < _noteParts.length; i++)
        ChordNoteHeadMetrics(
          _noteHeadPath(_noteParts[i], displaced: displaced[i]),
          _noteParts[i],
        ),
    ];
  }

  /// thickness of the leger lines.
  double get legerLineThickness => metadata.legerLineThickness;

  /// extension of the leger lines.
  double get legerLineExtension => metadata.legerLineExtension;

  /// path of the note head for a specific [ChordNotePart].
  Path _noteHeadPath(ChordNotePart part, {required bool displaced}) {
    final noteHeadLeftX =
        displaced ? _displacedColumnLeftX : _normalColumnLeftX;
    return _noteHeadOriginPath
        .shift(Offset(noteHeadLeftX, 0) + _positionOffset(part));
  }

  /// Which heads sit on the far side of the stem, one flag per note part.
  ///
  /// The engraving rule for seconds (Gould, *Behind Bars*; Read; the
  /// Wikipedia "Stem (music)" article): the two notes of a second can't share
  /// a column, so one of them goes to the other side of the stem. Most heads
  /// stay on the stem's normal side — left of an up-stem, right of a
  /// down-stem. Walking the chord from the stem's root end (from the bottom
  /// for an up-stem, from the top for a down-stem), a head a step from the
  /// head before it is displaced unless that one already was, so a run of
  /// seconds alternates sides: G B C D E stem up is G B D on the left, C E on
  /// the right. Stemless notes (whole notes) follow the up-stem pattern.
  List<bool> get _displacedHeads {
    final count = _noteParts.length;
    final positions = [
      for (final part in _noteParts) _getNotePosition(part).localPosition,
    ];
    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) => positions[a].compareTo(positions[b]));
    final walk = _displacedGoLeft ? order.reversed.toList() : order;
    final displaced = List<bool>.filled(count, false);
    for (var k = 1; k < walk.length; k++) {
      final previous = walk[k - 1];
      final current = walk[k];
      if ((positions[current] - positions[previous]).abs() <= 1 &&
          !displaced[previous]) {
        displaced[current] = true;
      }
    }
    return displaced;
  }

  /// A down-stem chord puts its displaced heads left of the stem; an up-stem
  /// or stemless one puts them on the right.
  bool get _displacedGoLeft => hasStem && !_isStemUp;

  /// Whether any head sits in a column left of the normal one, which then
  /// moves right by one head to make room.
  bool get _hasLeftColumn => _displacedGoLeft && _displacedHeads.contains(true);

  /// How far the second column sits from the first: heads on a stem share
  /// its thickness; stemless heads (whole notes) just touch.
  double get _columnStep =>
      hasStem ? _noteHeadWidth - stemThickness : _noteHeadWidth;

  /// list of [ChordNotePart]s that have accidental note heads.
  List<ChordNotePart> get _hasAccidentalNoteHeads =>
      _noteParts.where((e) => e.accidental != null).toList();

  /// the metrics for the accidental of a specific [ChordNotePart].
  AccidentalMetrics _accidentalMetrics(ChordNotePart note, double offsetX) =>
      AccidentalMetrics(
        _getNotePosition(note).localPosition,
        _getPath(note.accidental!.pathKey),
        offsetX,
      );

  /// the list of accidental metrics for all the accidental note heads.
  List<AccidentalMetrics> get accidentalMetricses {
    final metricses = <AccidentalMetrics>[];
    var offsetX = 0.0;
    for (final note in _hasAccidentalNoteHeads) {
      final accidental = _accidentalMetrics(note, offsetX);
      metricses.add(accidental);
      offsetX += accidental.width;
    }
    return metricses;
  }

  /// the list of bounding boxes for all the accidental note heads.
  List<Rect> get _accidentalBboxes =>
      accidentalMetricses.map((e) => e.bbox).toList();

  /// get path from a path key.
  Path _getPath(String pathKey) => path.parsePath(pathKey);

  /// Gets the position of a note on the stave.
  StavePosition _getNotePosition(ChordNotePart note) =>
      StavePosition(note.pitch, _clefType);

  /// clefType of this chord note.
  ClefType get _clefType => context.clefType;

  /// Checks if the chord note has any accidental.
  bool get _hasAccidental => _noteParts.any((e) => e.accidental != null);

  /// Gets the bounding box of the accidentals.
  Rect get _accidentalsBbox {
    if (!_hasAccidental) {
      return Rect.zero;
    }
    final bboxes = _accidentalBboxes;
    final l = bboxes.map((e) => e.left).min;
    final t = bboxes.map((e) => e.top).min;
    final r = bboxes.map((e) => e.right).max;
    final b = bboxes.map((e) => e.bottom).max;
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Gets the sum of the widths of the accidentals.
  double get _accidentalsWidthSum => _accidentalsBbox.width;

  /// The left x of the column the stem's normal-side heads sit in.
  double get _normalColumnLeftX =>
      _accidentalsBbox.right + (_hasLeftColumn ? _columnStep : 0);

  /// The left x of the column the displaced heads sit in.
  double get _displacedColumnLeftX => _displacedGoLeft
      ? _accidentalsBbox.right
      : _normalColumnLeftX + _columnStep;

  /// Gets the original path of the note head.
  Path get _noteHeadOriginPath => _getPath(_noteHeadPathKey);

  /// Gets the width of the note head.
  double get _noteHeadWidth => _noteHeadOriginPath.getBounds().width;

  /// What stands in front of the normal-side heads: the accidentals, and a
  /// down-stem chord's displaced heads.
  @override
  double get leadingWidth =>
      _accidentalsWidthSum + (_hasLeftColumn ? _columnStep : 0);

  @override
  double get durationUnits =>
      NoteSpacing.unitsOf(note.noteDuration.quarterUnits);

  @override
  double get lowerHeight => _bbox.bottom;

  /// Gets the bounding box of the chord note.
  Rect get _bbox => Rect.fromLTRB(_left, _top, _right, _bottom);

  /// Gets the left coordinate of the bounding box.
  double get _left => [noteHeadsBbox.left, _accidentalsBbox.left].min;

  /// Gets the top coordinate of the bounding box.
  double get _top => [
        noteHeadsBbox.top,
        (stemTipOffset?.dy ?? double.infinity),
        (_flagBbox?.top ?? double.infinity),
        _accidentalsBbox.top,
      ].min;

  /// Gets the right coordinate of the bounding box.
  double get _right => [
        noteHeadsBbox.right,
        (_flagBbox?.right ?? double.negativeInfinity),
        _accidentalsBbox.right,
      ].max;

  /// Gets the bottom coordinate of the bounding box.
  double get _bottom => [
        noteHeadsBbox.bottom,
        (stemTipOffset?.dy ?? double.negativeInfinity),
        (_flagBbox?.bottom ?? double.negativeInfinity),
        _accidentalsBbox.bottom,
      ].max;

  @override
  EdgeInsets get margin => note.margin;

  @override
  double get upperHeight => -_bbox.top;

  /// The bounding box already runs from the first accidental to the last
  /// note head, so the accidentals are not added again: counting them twice
  /// made a chord with a sharp the widest thing on the page, and the spacing
  /// model, which measures every note against the widest of the shortest
  /// value, then spread a run of whole notes after it far apart.
  @override
  double get width => _bbox.width;

  /// Gets the list of bounding boxes for all the note heads.
  List<Rect> get _noteHeadsBboxes =>
      _noteHeads.map((e) => e.noteHeadRect).toList();

  /// Gets the bounding box that encompasses all the note heads.
  Rect get noteHeadsBbox => _noteHeadsBboxes.fold(
        _noteHeadsBboxes.first,
        (previousValue, element) => previousValue.expandToInclude(element),
      );

  /// Gets the path key of the note head.
  String get _noteHeadPathKey => _noteHeadType.pathKey;

  /// Gets the sum of the local positions of the note parts.
  int get _notePositionsSum => _noteParts
      .map((e) => _getNotePosition(e).localPosition)
      .fold(0, (a, b) => a + b);

  /// Gets the offset of the stem root for the highest note.
  Offset get _uppestNoteStemRootOffset => _noteStemRootOffset(_uppestNote);

  /// Gets the offset of the stem root for the lowest note.
  Offset get _lowestNoteStemRootOffset => _noteStemRootOffset(_lowestNote);

  /// Gets the minimum length of the stem.
  double get _minStemLength => metadata.minStemLength;

  double get _tipNoteStemRootToStaffCenterDist => _isStemUp
      ? _uppestNoteStemRootOffset.dy
      : -1 * _lowestNoteStemRootOffset.dy;

  /// Checks if the stem is centered.
  bool get _isStemCentered =>
      _tipNoteStemRootToStaffCenterDist > _minStemLength;

  /// Gets the length of the stem.
  double get _stemLength =>
      _isStemCentered ? _tipNoteStemRootToStaffCenterDist : _minStemLength;

  /// Gets the thickness of the stem.
  double get stemThickness => metadata.stemThickness;

  /// The left edge of the normal-side heads, which the stem is set against.
  double get _noteHeadInitialX =>
      noteHeadsBbox.left + (_hasLeftColumn ? _columnStep : 0);

  /// Gets the offset of the stem root.
  Offset get stemRootOffset =>
      _isStemUp ? _lowestNoteStemRootOffset : _uppestNoteStemRootOffset;

  /// Gets the offset of the tip note root.
  Offset get _tipNoteRootOffset =>
      _isStemUp ? _uppestNoteStemRootOffset : _lowestNoteStemRootOffset;

  /// Calculates the offset of the stem root for a specific [ChordNoteHeadMetrics].
  Offset _noteStemRootOffset(ChordNoteHeadMetrics noteHead) =>
      Offset(_noteHeadInitialX, 0) +
      metadata.stemRootOffset(_noteHeadType.metadataKey, isStemUp: _isStemUp) +
      _stemThicknessOffset +
      _positionOffset(noteHead.part);

  /// Gets the offset for adjusting the stem thickness.
  Offset get _stemThicknessOffset =>
      Offset(_isStemUp ? -stemThickness / 2 : stemThickness / 2, 0);

  /// Gets the offset of the stem tip.
  Offset? get stemTipOffset {
    if (!hasStem) {
      return null;
    }
    if (hasFlag) {
      return _flagStemTipOffset! + Offset(stemThickness / 2, 0);
    }
    if (_isStemCentered) {
      return Offset(stemRootOffset.dx, 0);
    }
    return _tipNoteRootOffset +
        Offset(0, _isStemUp ? -_stemLength : _stemLength);
  }

  /// Gets the offset of the flag.
  Offset get _flagOffset {
    if (_isStemCentered) {
      return Offset(
        stemRootOffset.dx - stemThickness / 2,
        -(_isStemUp ? _flagBboxMetrics!.top : _flagBboxMetrics!.bottom),
      );
    }
    return _tipNoteRootOffset +
        Offset(0, _isStemUp ? -_stemLength : _stemLength);
  }

  /// Calculates the position offset for a specific [ChordNotePart].
  Offset _positionOffset(ChordNotePart note) {
    final position = _getNotePosition(note).localPosition;
    return Offset(0, -1 * (1 / 2) * position * Constants.staffSpace);
  }

  /// Gets the lowest note among the note heads.
  ChordNoteHeadMetrics get _lowestNote {
    var lowestNote = _noteHeads.first;
    for (final note in _noteHeads) {
      if (note.pitch <= lowestNote.pitch) {
        lowestNote = note;
      }
    }
    return lowestNote;
  }

  /// Gets the highest note among the note heads.
  ChordNoteHeadMetrics get _uppestNote {
    var uppest = _noteHeads.first;
    for (final note in _noteHeads) {
      if (note.pitch >= uppest.pitch) {
        uppest = note;
      }
    }
    return uppest;
  }

  /// Gets the stave position of the highest note.
  StavePosition get uppestNotePosition => _getNotePosition(_uppestNote.part);

  /// Gets the stave position of the lowest note.
  StavePosition get lowestNotePosition => _getNotePosition(_lowestNote.part);

  /// Checks if the chord note has a stem.
  bool get hasStem => note.noteDuration.hasStem;

  /// Checks if the stem direction is up.
  bool get _isStemUp => note.stemDirection?.isUp ?? _defaultStemDirection.isUp;

  /// Gets the default stem direction based on the note positions.
  StemDirection get _defaultStemDirection =>
      _notePositionsSum < 0 ? StemDirection.up : StemDirection.down;

  /// Gets the type of note head used in the chord note.
  NoteHeadType get _noteHeadType => note.noteHeadType;

  /// Checks if the chord note has a flag.
  bool get hasFlag => note.noteDuration.hasFlag;

  /// Gets the type of note flag used in the chord note.
  NoteFlagType? get _noteFlagType => note.noteDuration.noteFlagType;

  /// Gets the metadata key for the flag.
  String? get _flagMetadataKey {
    if (!hasFlag) {
      return null;
    }
    return _isStemUp
        ? _noteFlagType!.upMetadataKey
        : _noteFlagType!.downMetadataKey;
  }

  /// Gets the path key for the flag.
  String? get _flagPathKey {
    if (!hasFlag) {
      return null;
    }
    return _isStemUp ? _noteFlagType!.upPathKey : _noteFlagType!.downPathKey;
  }

  /// Gets the offset of the stem tip for the flag.
  Offset? get _flagStemTipOffset {
    if (!hasFlag) {
      return null;
    }
    return metadata.flagRootOffset(_flagMetadataKey!, isStemUp: _isStemUp) +
        _flagOffset;
  }

  /// Gets the path of the flag on the y-coordinate 0.
  Path? get _flagPathOnY0 {
    if (!hasFlag) {
      return null;
    }
    return path.parsePath(_flagPathKey!);
  }

  /// Gets the bounding box metrics of the flag.
  Rect? get _flagBboxMetrics {
    if (!hasFlag) {
      return null;
    }
    return _flagPathOnY0!.getBounds();
  }

  /// Gets the path of the flag.
  Path? get flagPath {
    if (!hasFlag) {
      return null;
    }
    return _flagPathOnY0!.shift(_flagOffset);
  }

  /// Gets the bounding box of the flag.
  Rect? get _flagBbox => flagPath?.getBounds();

  /// Gets the list of paths for all the note heads.
  List<Path> get noteHeadsPaths =>
      _noteHeads.map((e) => e.noteHeadPath).toList();

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      ChordNoteRenderer(
        this,
        layout,
        staffLineCenterY: staffLineCenterY,
        symbolX: symbolX,
      );
}

class ChordNoteRenderer implements MusicalSymbolRenderer {
  const ChordNoteRenderer(
    this.note,
    this.layout, {
    required this.staffLineCenterY,
    required this.symbolX,
  });
  final double staffLineCenterY;
  final double symbolX;
  final ChordNoteMetrics note;
  final SheetMusicLayout layout;

  @override
  bool isHit(Offset position) => _renderArea.contains(position);

  @override
  void render(Canvas canvas) {
    _renderNoteHead(canvas);
    _renderFlag(canvas);
    _renderAccidentals(canvas);
    _renderStem(canvas);
    _renderLegerLine(canvas);
  }

  void _renderNoteHead(Canvas canvas) {
    for (final path in note.noteHeadsPaths) {
      canvas.drawPath(
        path.shift(_renderOffset),
        Paint()
          ..color = note.note.color
          ..strokeWidth = 2,
      );
    }
  }

  Rect get _renderArea => throw UnimplementedError();

  /// The heads as they are drawn, one for each note of the chord.
  List<Path> get noteHeadRenderPaths =>
      [for (final path in note.noteHeadsPaths) path.shift(_renderOffset)];

  void _renderAccidentals(Canvas canvas) {
    for (final accidental in note.accidentalMetricses) {
      canvas.drawPath(
        accidental.path.shift(_renderOffset),
        Paint()
          ..color = note.note.color
          ..strokeWidth = 2,
      );
    }
  }

  void _renderStem(Canvas canvas) {
    if (!note.hasStem) {
      return;
    }
    canvas.drawLine(
      note.stemRootOffset + _renderOffset,
      note.stemTipOffset! + _renderOffset,
      Paint()
        ..color = note.note.color
        ..strokeWidth = note.stemThickness,
    );
  }

  void _renderFlag(Canvas canvas) {
    if (!note.hasFlag) {
      return;
    }
    canvas.drawPath(
      note.flagPath!.shift(_renderOffset),
      Paint()
        ..color = note.note.color
        ..strokeWidth = 2,
    );
  }

  Offset get _renderOffset => Offset(symbolX, staffLineCenterY) + _marginOffset;
  Offset get _marginOffset => Offset(note.margin.left / layout.canvasScale, 0);

  double get _legerLineWidth => note.legerLineExtension * 2 + _noteHeadWidth;

  double get _legerLineThickness => note.legerLineThickness;
  void _renderLegerLine(Canvas canvas) {
    LegerLineRenderer(
      layout.lineColor,
      _uppestNotePosition,
      staffLineCenterY: staffLineCenterY,
      noteCenterX: _noteHeadCenterX,
      legerLineWidth: _legerLineWidth,
      legerLineThickness: _legerLineThickness,
    ).render(canvas);
    LegerLineRenderer(
      layout.lineColor,
      _lowestNotePosition,
      staffLineCenterY: staffLineCenterY,
      noteCenterX: _noteHeadCenterX,
      legerLineWidth: _legerLineWidth,
      legerLineThickness: _legerLineThickness,
    ).render(canvas);
  }

  StavePosition get _uppestNotePosition => note.uppestNotePosition;
  StavePosition get _lowestNotePosition => note.lowestNotePosition;

  double get _noteHeadWidth => _noteHeadRenderArea.width;
  Rect get _noteHeadRenderArea => note.noteHeadsBbox.shift(_renderOffset);
  double get _noteHeadLeftX => _noteHeadRenderArea.left;

  double get _noteHeadCenterX => _noteHeadLeftX + _noteHeadWidth / 2;
}
