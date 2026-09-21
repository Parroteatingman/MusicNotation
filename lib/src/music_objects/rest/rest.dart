import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest_type.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// Represents a rest in sheet music.
class Rest implements MusicalSymbol {
  const Rest(
    this.restType, {
    this.margin = const EdgeInsets.all(10),
    this.color = Colors.black,
    this.isDotted = false,
    this.tuplet,
    this.chordLabel,
  });

  @override
  final Color color;

  @override
  final EdgeInsets margin;

  final RestType restType;

  /// Whether this rest has a dot (extends duration by 50%).
  final bool isDotted;

  /// Tuplet grouping (e.g., 3 for triplet). Null means no tuplet.
  final int? tuplet;

  /// Optional chord label displayed above the rest.
  final String? chordLabel;

  @override
  MusicalSymbolMetrics setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) =>
      RestMetrics(
        this,
        context,
        metadata,
        paths,
      );
}

/// Represents the metrics of a rest in sheet music.
class RestMetrics implements MusicalSymbolMetrics {
  const RestMetrics(
    this.rest,
    this.context,
    this.metadata,
    this.paths,
  );

  final MusicalContext context;
  final GlyphMetadata metadata;
  final GlyphPaths paths;
  final Rest rest;

  RestType get restType => rest.restType;

  Offset get defaultOffset =>
      Offset(0, -1 * restType.offsetSpace * Constants.staffSpace);

  Path get path => paths.parsePath(rest.restType.pathKey).shift(defaultOffset);
  Rect get bbox => path.getBounds();

  /// A rest has nothing in front of it.
  @override
  double get leadingWidth => 0;

  @override
  double get durationUnits => NoteSpacing.unitsOf(
        rest.restType.quarterUnits,
        isDotted: rest.isDotted,
        tuplet: rest.tuplet,
      );

  @override
  double get lowerHeight => bbox.bottom;

  double get leftMargin => rest.margin.left;

  @override
  double get upperHeight {
    final baseUpperHeight = -bbox.top;
    if (rest.chordLabel == null || rest.chordLabel!.isEmpty) {
      return baseUpperHeight;
    }
    return baseUpperHeight > Constants.staffSpace * 5.4
        ? baseUpperHeight
        : Constants.staffSpace * 5.4;
  }

  @override
  double get width =>
      bbox.width + (rest.isDotted ? Constants.staffSpace * 0.8 : 0);

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      RestRenderer(
        this,
        layout,
        staffLineCenterY: staffLineCenterY,
        symbolX: symbolX,
      );

  @override
  EdgeInsets get margin => rest.margin;
}

/// Renders a rest in sheet music.
class RestRenderer implements MusicalSymbolRenderer {
  const RestRenderer(
    this.restMetrics,
    this.layout, {
    required this.staffLineCenterY,
    required this.symbolX,
  });

  final double staffLineCenterY;
  final double symbolX;
  final RestMetrics restMetrics;
  final SheetMusicLayout layout;

  Offset get renderOffset => Offset(symbolX, staffLineCenterY) + marginOffset;
  Offset get marginOffset =>
      Offset(restMetrics.leftMargin, 0) / layout.canvasScale;

  @override
  bool isHit(Offset position) =>
      renderArea.inflate(Constants.staffSpace * 0.6).contains(position);

  @override
  void render(Canvas canvas) {
    _renderChordLabel(canvas);
    canvas.drawPath(renderPath, Paint()..color = restMetrics.rest.color);
    _renderDot(canvas);
  }

  void _renderChordLabel(Canvas canvas) {
    final label = restMetrics.rest.chordLabel;
    if (label == null || label.isEmpty) return;

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
    )..layout();

    TextPainter? suffixPainter;
    if (suffix.isNotEmpty) {
      suffixPainter = TextPainter(
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
      )..layout();
    }

    final x = symbolX + restMetrics.leftMargin / layout.canvasScale;
    final topStaffLine = staffLineCenterY - Constants.staffSpace * 2;
    final y = topStaffLine - Constants.staffSpace * 2.15;

    rootPainter.paint(canvas, Offset(x, y - rootPainter.height));

    if (suffixPainter != null) {
      final suffixX = x + rootPainter.width;
      final suffixY = y - rootPainter.height;
      suffixPainter.paint(canvas, Offset(suffixX, suffixY));
    }
  }

  void _renderDot(Canvas canvas) {
    if (!restMetrics.rest.isDotted) return;
    final bounds = renderPath.getBounds();
    final dotRadius = Constants.staffSpace * 0.18;
    // Place dot to the right of the rest, vertically at the 3rd staff space (above center)
    final dotCenter = Offset(
      bounds.right + Constants.staffSpace * 0.35,
      staffLineCenterY - Constants.staffSpace * 0.5,
    );
    canvas.drawCircle(
        dotCenter, dotRadius, Paint()..color = restMetrics.rest.color);
  }

  Path get renderPath => restMetrics.path.shift(renderOffset);

  Rect get renderArea => renderPath.getBounds();
}
