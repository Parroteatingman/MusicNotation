import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/extension/list_extension.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/accidental.dart';
import 'package:simple_sheet_music/src/music_objects/notes/legerline.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_pitch.dart';
import 'package:simple_sheet_music/src/music_objects/notes/noteflag_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/notehead_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/positions.dart';
import 'package:simple_sheet_music/src/music_objects/notes/stem_direction.dart';
import 'package:simple_sheet_music/src/music_objects/notes/tie_type.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// Represents a musical note.
class Note implements MusicalSymbol {
  const Note(
    this.pitch, {
    this.noteDuration = NoteDuration.quarter,
    this.accidental,
    this.margin = const EdgeInsets.all(10),
    this.color = Colors.black,
    this.noteHeadColor,
    this.isBeamed = false,
    this.forceStemUp,
    this.beamGroupId = 0,
    this.beatPosition = 0.0,
    this.chordLabel,
    this.isDotted = false,
    this.tuplet,
    this.tie,
  });

  @override
  final EdgeInsets margin;

  // /// The direction of the note stem.
  // final StemDirection? stemDirection;

  @override
  final Color color;

  /// The pitch of the note.
  final Pitch pitch;

  /// The duration of the note.
  final NoteDuration noteDuration;

  /// The accidental of the note (if any).
  final Accidental? accidental;

  /// Whether this note is part of a beamed group (suppresses individual flag).
  final bool isBeamed;

  /// Force stem direction: true = up, false = down, null = auto.
  final bool? forceStemUp;

  /// Beam group identifier. Notes with the same beamGroupId are beamed together.
  final int beamGroupId;

  /// Beat position within the measure (0.0 = beat 1, 1.0 = beat 2, etc.)
  /// Used by the renderer to break secondary/tertiary beams at beat boundaries.
  final double beatPosition;

  /// Optional chord label to display above this note (e.g., "Dm7", "G7").
  final String? chordLabel;

  /// Whether this note has a dot (extends duration by 50%).
  final bool isDotted;

  /// Tuplet grouping (e.g., 3 for triplet). Null means no tuplet.
  final int? tuplet;

  /// Tie connection type for this note.
  final TieType? tie;

  /// Optional color for the note head only. When set, stems/beams/flags stay
  /// at [color] while the note head uses this color.
  final Color? noteHeadColor;

  /// The type of note head based on the note duration.
  NoteHeadType get noteHeadType => noteDuration.noteHeadType;

  @override
  MusicalSymbolMetrics setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) =>
      NoteMetrics(this, context, metadata, paths);
}

/// Represents the metrics (size, position, etc.) of a single note in sheet music.
class NoteMetrics implements MusicalSymbolMetrics {
  const NoteMetrics(
    this.note,
    this.context,
    this.metadata,
    this.paths,
  );

  // The musical context in which the note appears.
  final MusicalContext context;

  // The metadata of the note's glyph.
  final GlyphMetadata metadata;

  // The paths of the note's glyph.
  final GlyphPaths paths;

  // The note object associated with these metrics.
  final Note note;

  @override
  double get lowerHeight => bbox.bottom;

  // The width of the note head.
  double get noteHeadWidth => _noteHeadBbox.width;

  // The bounding box of the note.
  Rect get bbox => Rect.fromLTRB(_left, _top, _right, _bottom);

  double get _left =>
      [_noteHeadBbox.left, (_accidentalBbox?.left ?? double.infinity)].min;

  double get _top => [
        _noteHeadBbox.top,
        hasStem ? stemTipOffset.dy : double.infinity,
        (_flagBbox?.top ?? double.infinity),
        (_accidentalBbox?.top ?? double.infinity),
      ].min;

  double get _right => [
        _noteHeadBbox.right + (note.isDotted ? _dotSpaceWidth : 0),
        (_flagBbox?.right ?? double.negativeInfinity),
        (_accidentalBbox?.right ?? double.negativeInfinity),
      ].max;

  /// Width of the dot + spacing after the note head.
  double get _dotSpaceWidth => noteHeadWidth * 0.8;

  double get _bottom => [
        _noteHeadBbox.bottom,
        hasStem ? stemTipOffset.dy : double.negativeInfinity,
        (_flagBbox?.bottom ?? double.negativeInfinity),
        (_accidentalBbox?.bottom ?? double.negativeInfinity),
      ].max;

  @override
  EdgeInsets get margin => note.margin;

  // The pitch of the note.
  Pitch get pitch => note.pitch;

  // The thickness of the leger lines.
  double get legerLineThickness => metadata.legerLineThickness;

  // The extension of the leger lines.
  double get legerLineExtension => metadata.legerLineExtension;

  // The color of the note.
  Color get color => note.color;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      NoteRenderer(
        this,
        layout,
        staffLineCenterY: staffLineCenterY,
        symbolX: symbolX,
      );

  @override
  double get upperHeight {
    final baseUpperHeight = -bbox.top;
    if (note.chordLabel == null || note.chordLabel!.isEmpty) {
      return baseUpperHeight;
    }
    return baseUpperHeight > Constants.staffSpace * 5.4
        ? baseUpperHeight
        : Constants.staffSpace * 5.4;
  }

  @override
  double get width => bbox.width;

  // The bounding box of the note head.
  Rect get _noteHeadBbox => noteHeadPath.getBounds();

  // The default offset of the note.
  Offset get _defaultOffset => Offset.zero;

  // The path of the note head.
  Path get noteHeadPath => paths
      .parsePath(note.noteHeadType.pathKey)
      .shift(_defaultOffset + _positionOffset + Offset(accidentalWidth, 0));

  // The left x-coordinate of the note head.
  double get noteHeadLeftX => _noteHeadBbox.left;

  // The width of the accidental (if any).
  double get accidentalWidth => _accidentalBbox?.width ?? 0;

  // The bounding box of the accidental (if any).
  Rect? get _accidentalBbox {
    if (!hasAccidental) {
      return null;
    }
    return accidentalPath!.getBounds();
  }

  // The offset of the note's position.
  Offset get _positionOffset => stavePosition.positionOffset;

  // The accidental of the note (if any).
  Accidental? get _accidental => note.accidental;

  // Whether the note has an accidental.
  bool get hasAccidental => _accidental != null;

  // The path of the accidental (if any).
  Path? get accidentalPath {
    if (!hasAccidental) {
      return null;
    }
    return paths
        .parsePath(_accidental!.pathKey)
        .shift(_defaultOffset + _positionOffset);
  }

  // The stave position of the note.
  StavePosition get stavePosition => StavePosition(pitch, _clefType);

  // The clef type of the note.
  ClefType get _clefType => context.clefType;

  // The minimum length of the stem.
  double get _minStemLength => metadata.minStemLength;

  // The distance from the stem root to the center of the staff.
  double get _stemRootToStaffCenterDist => stemRootOffset.dy.abs();

  // Whether the stem is centered.
  bool get _isStemCentered => _stemRootToStaffCenterDist > _minStemLength;

  // The length of the stem.
  double get _stemLength =>
      _isStemCentered ? _stemRootToStaffCenterDist : _minStemLength;

  // The thickness of the stem.
  double get stemThickness => metadata.stemThickness;

  // The initial x-coordinate of the note head.
  double get _noteHeadInitialX => _noteHeadBbox.left;

  // The offset of the stem root.
  Offset get stemRootOffset =>
      Offset(_noteHeadInitialX, 0) +
      metadata.stemRootOffset(_noteHeadType.metadataKey, isStemUp: isStemUp) +
      _stemThicknessOffset +
      _positionOffset;

  // The offset of the stem thickness.
  Offset get _stemThicknessOffset =>
      Offset(isStemUp ? -stemThickness / 2 : stemThickness / 2, 0);

  // The offset of the stem tip.
  Offset get stemTipOffset {
    if (hasFlag) {
      return _flagStemOffset! + Offset(stemThickness / 2, 0);
    }
    if (_isStemCentered) {
      return Offset(stemRootOffset.dx, 0);
    }
    return stemRootOffset + Offset(0, isStemUp ? -_stemLength : _stemLength);
  }

  // The offset of the flag.
  Offset get _flagOffset {
    if (_isStemCentered) {
      return Offset(
        stemRootOffset.dx - stemThickness / 2,
        -(isStemUp ? _flagBboxOnY0!.top : _flagBboxOnY0!.bottom),
      );
    }
    return stemRootOffset + Offset(0, isStemUp ? -_stemLength : _stemLength);
  }

  // Whether the note has a stem.
  bool get hasStem => note.noteDuration.hasStem;

  // Whether the stem is up.
  bool get isStemUp => note.forceStemUp ?? _defaultStemDirection.isUp;

  // The default stem direction based on the stave position.
  StemDirection get _defaultStemDirection => stavePosition.defaultStemDirection;

  // The type of the note head.
  NoteHeadType get _noteHeadType => note.noteHeadType;

  // Whether the note has a flag.
  bool get hasFlag => note.noteDuration.hasFlag;

  // The type of the note flag.
  NoteFlagType? get _noteFlagType => note.noteDuration.noteFlagType;

  // The metadata key of the flag.
  String? get _flagMetadataKey {
    if (!hasFlag) {
      return null;
    }
    return isStemUp
        ? _noteFlagType!.upMetadataKey
        : _noteFlagType!.downMetadataKey;
  }

  // The path key of the flag.
  String? get _flagPathKey {
    if (!hasFlag) {
      return null;
    }
    return isStemUp ? _noteFlagType!.upPathKey : _noteFlagType!.downPathKey;
  }

  // The offset of the flag stem.
  Offset? get _flagStemOffset {
    if (!hasFlag) {
      return null;
    }
    return metadata.flagRootOffset(_flagMetadataKey!, isStemUp: isStemUp) +
        _flagOffset;
  }

  // The path of the flag on the y=0 line.
  Path? get _flagPathOnY0 {
    if (!hasFlag) {
      return null;
    }
    return paths.parsePath(_flagPathKey!);
  }

  // The bounding box of the flag on the y=0 line.
  Rect? get _flagBboxOnY0 {
    if (!hasFlag) {
      return null;
    }
    return _flagPathOnY0!.getBounds();
  }

  // The path of the flag.
  Path? get flagPath {
    if (!hasFlag) {
      return null;
    }
    return _flagPathOnY0!.shift(_flagOffset);
  }

  // The bounding box of the flag.
  Rect? get _flagBbox => flagPath?.getBounds();
}

/// A class that renders a musical note symbol.
class NoteRenderer implements MusicalSymbolRenderer {
  const NoteRenderer(
    this.note,
    this.layout, {
    required this.staffLineCenterY,
    required this.symbolX,
  });

  final SheetMusicLayout layout;
  final double staffLineCenterY;
  final double symbolX;
  final NoteMetrics note;

  /// Returns the scale of the canvas.
  double get canvasScale => layout.canvasScale;

  @override
  bool isHit(Offset position) => _renderArea.contains(position);

  @override
  void render(Canvas canvas) {
    _renderChordLabel(canvas);
    _renderNoteHead(canvas);
    _renderDot(canvas);
    _renderFlag(canvas);
    _renderAccidental(canvas);
    _renderStem(canvas);
    _renderLegerLine(canvas);
  }

  void _renderChordLabel(Canvas canvas) {
    final label = note.note.chordLabel;
    if (label == null || label.isEmpty) return;

    // Parse chord label into root and suffix for styled rendering
    // e.g., "Dm7" -> root="D", suffix="m7"; "Cmaj7" -> root="C", suffix="maj7"
    int rootEnd = 1;
    if (label.length > 1 &&
        (label[1] == '#' ||
            label[1] == 'b' ||
            label[1] == '♯' ||
            label[1] == '♭')) {
      rootEnd = 2;
    }
    final root = label.substring(0, rootEnd);
    final suffix = label.length > rootEnd ? label.substring(rootEnd) : '';

    final rootFontSize = Constants.staffSpace * 1.35;
    final suffixFontSize = Constants.staffSpace * 0.9;

    // Render root note letter
    final rootPainter = TextPainter(
      text: TextSpan(
        text: root,
        style: TextStyle(
          color: Colors.black,
          fontSize: rootFontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'serif',
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    rootPainter.layout();

    final x = symbolX + note.margin.left / canvasScale;
    final topStaffLine = staffLineCenterY - Constants.staffSpace * 2;
    final y = topStaffLine - Constants.staffSpace * 2.15;

    rootPainter.paint(canvas, Offset(x, y - rootPainter.height));

    if (suffix.isNotEmpty) {
      final suffixPainter = TextPainter(
        text: TextSpan(
          text: suffix,
          style: TextStyle(
            color: Colors.black,
            fontSize: suffixFontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'serif',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      suffixPainter.layout();

      final suffixX = x + rootPainter.width;
      // Position suffix at the top of the root (superscript style)
      final suffixY = y - rootPainter.height;
      suffixPainter.paint(canvas, Offset(suffixX, suffixY));
    }
  }

  void _renderNoteHead(Canvas canvas) {
    canvas.drawPath(noteHeadRenderPath,
        Paint()..color = note.note.noteHeadColor ?? note.color);
  }

  void _renderDot(Canvas canvas) {
    if (!note.note.isDotted) return;
    final headBounds = noteHeadRenderPath.getBounds();
    final dotRadius = Constants.staffSpace * 0.18;
    // Place dot to the right of the note head, vertically centered
    // If on a line (localPosition is even), shift dot up so it sits in a space
    final isOnLine = note.stavePosition.localPosition % 2 == 0;
    final yOffset = isOnLine ? -Constants.staffSpace * 0.5 : 0.0;
    final dotCenter = Offset(
      headBounds.right + Constants.staffSpace * 0.35,
      headBounds.center.dy + yOffset,
    );
    canvas.drawCircle(dotCenter, dotRadius, Paint()..color = note.color);
  }

  void _renderAccidental(Canvas canvas) {
    if (!note.hasAccidental) {
      return;
    }
    canvas.drawPath(
      renderAccidentalPath!,
      Paint()
        ..color = note.note.color
        ..strokeWidth = 2,
    );
  }

  /// Returns the path of the accidental, shifted by the render offset.
  Path? get renderAccidentalPath => note.accidentalPath?.shift(_renderOffset);

  void _renderStem(Canvas canvas) {
    if (!note.hasStem || note.note.isBeamed) {
      return;
    }
    canvas.drawLine(
      note.stemRootOffset + _renderOffset,
      note.stemTipOffset + _renderOffset,
      Paint()
        ..color = note.color
        ..strokeWidth = note.stemThickness,
    );
  }

  /// Returns the path of the note head, shifted by the render offset.
  Path get noteHeadRenderPath => note.noteHeadPath.shift(_renderOffset);

  void _renderFlag(Canvas canvas) {
    if (!note.hasFlag || note.note.isBeamed) {
      return;
    }
    canvas.drawPath(
      note.flagPath!.shift(_renderOffset),
      Paint()..color = note.color,
    );
  }

  /// Returns the render offset, which is the sum of the symbol X position and the staff line center Y position.
  Offset get renderOffset => Offset(symbolX, staffLineCenterY) + _marginOffset;
  Offset get _renderOffset => renderOffset;

  /// Returns the margin offset, which is the left margin of the note divided by the canvas scale.
  Offset get _marginOffset => Offset(note.margin.left / canvasScale, 0);

  /// Returns the render area of the note, shifted by the render offset.
  Rect get _renderArea => note.bbox.shift(_renderOffset);

  /// Returns the width of the leger line, which is twice the leger line extension plus the note head width.
  double get _legerLineWidth => note.legerLineExtension * 2 + _noteHeadWidth;

  /// Returns the thickness of the leger line.
  double get _legerLineThickness => note.legerLineThickness;

  /// Renders the leger line.
  void _renderLegerLine(Canvas canvas) => LegerLineRenderer(
        layout.lineColor,
        _notePosition,
        staffLineCenterY: staffLineCenterY,
        noteCenterX: _noteHeadCenterX,
        legerLineWidth: _legerLineWidth,
        legerLineThickness: _legerLineThickness,
      ).render(canvas);

  /// Returns the position of the note on the stave.
  StavePosition get _notePosition => note.stavePosition;

  /// Returns the width of the note head.
  double get _noteHeadWidth => note.noteHeadWidth;

  /// Returns the left X position of the note head.
  double get _noteHeadLeftX => _renderOffset.dx + note.noteHeadLeftX;

  /// Returns the center X position of the note head.
  double get _noteHeadCenterX => _noteHeadLeftX + note.noteHeadWidth / 2;

  /// Public note head bounds for higher-level renderers such as ties.
  Rect get noteHeadBounds => noteHeadRenderPath.getBounds();

  /// Public center point of the rendered note head.
  Offset get noteHeadCenter => noteHeadBounds.center;

  double get noteHeadLeft => noteHeadBounds.left;

  double get noteHeadRight => noteHeadBounds.right;
}
