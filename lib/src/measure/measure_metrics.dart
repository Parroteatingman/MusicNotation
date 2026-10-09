import 'dart:math';

import 'package:simple_sheet_music/src/extension/list_extension.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/measure/barline.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// Represents the metrics of a measure in sheet music.
class MeasureMetrics {
  /// The [musicalSymbolsMetricses] parameter is a list of [MusicalSymbolMetrics]
  /// representing the metrics of each musical symbol in the measure.
  ///
  /// The [metadata] parameter is a [GlyphMetadata] object containing metadata
  /// for the measure.
  ///
  /// The [isNewLine] parameter indicates whether a line break should occur in this measure.
  const MeasureMetrics(
    this.musicalSymbolsMetricses,
    this.metadata, {
    required this.isNewLine,
    this.spacing = SpacingReference.none,
    this.endBarline,
  });

  /// How the measure ends; null leaves it to the staff.
  final BarlineType? endBarline;

  /// The list of [MusicalSymbolMetrics] representing the metrics of each musical
  /// symbol in the measure.
  final List<MusicalSymbolMetrics> musicalSymbolsMetricses;

  /// The [GlyphMetadata] object containing metadata for the measure.
  final GlyphMetadata metadata;

  /// Indicates whether a line break should occur in this measure.
  final bool isNewLine;

  /// The shortest note on the page, which every symbol's width is measured
  /// against. See [SpacingReference].
  final SpacingReference spacing;

  /// Gets the total width claimed by the musical symbols in the measure —
  /// each symbol's glyph, or the room its note value asks for, whichever is
  /// wider. See [SpacingReference].
  double get objectsWidth => musicalSymbolsMetricses.map(spacing.advanceOf).sum;

  /// The part of [objectsWidth] held by symbols that carry no time — clefs,
  /// key and time signatures, barlines — which a layout may keep at their
  /// own width when it spreads a line (see [SheetMusicLayout.spreadOnlyNotes]).
  double get fixedWidth => musicalSymbolsMetricses
      .where((symbol) => symbol.durationUnits <= 0)
      .map(spacing.advanceOf)
      .sum;

  /// The width of the symbols' own glyphs, before any room their note values
  /// ask for: what the measure takes with its notes set glyph to glyph.
  double get glyphWidth => musicalSymbolsMetricses.map(inkWidthOf).sum;

  /// How wide [symbol]'s ink is across the line (a beamed note's unseen
  /// flag left out; see [NoteMetrics.inkWidth]).
  static double inkWidthOf(MusicalSymbolMetrics symbol) =>
      symbol is NoteMetrics ? symbol.inkWidth : symbol.width;

  /// How far along the line [symbol] moves the next one, its margins aside.
  ///
  /// [stretch] scales the room the symbol claims (a justified line pulled
  /// out, or the old squeeze, [SheetMusicLayout.minStretch]). [squeeze]
  /// takes away only the room beyond the glyph — 0 sets glyph to glyph — so
  /// a busy line drawn at its full size pulls its notes together without
  /// ever running one into the next.
  double advanceIn(
    MusicalSymbolMetrics symbol, {
    required bool spreadOnlyNotes,
    double stretch = 1,
    double squeeze = 1,
  }) {
    final advance = spacing.advanceOf(symbol);
    if (spreadOnlyNotes && symbol.durationUnits <= 0) return advance;
    final stretched = advance * stretch;
    if (squeeze >= 1) return stretched;
    final glyph = min(inkWidthOf(symbol), stretched);
    return glyph + (stretched - glyph) * max(0.0, squeeze);
  }

  /// Gets the maximum upper height among all the musical symbols in the measure.
  double get _symbolMaximumUpperHeight =>
      musicalSymbolsMetricses.map((symbol) => symbol.upperHeight).max;

  /// Returns the height of the upper part of the measure.
  double get _measureUpperHeight => metadata.measureUpperHeight;

  /// Returns the maximum height of the measure upper part.
  double get upperHeight => max(_symbolMaximumUpperHeight, _measureUpperHeight);

  /// Gets the maximum lower height among all the musical symbols in the measure.
  double get _symbolMaximumLowerHeight =>
      musicalSymbolsMetricses.map((symbol) => symbol.lowerHeight).max;

  /// Returns the height of the lower part of the measure.
  double get _measureLowerHeight => metadata.measureLowerHeight;

  /// Returns the maximum height of the measure lower part.
  double get lowerHeight => max(_symbolMaximumLowerHeight, _measureLowerHeight);

  /// Gets the sum of the horizontal margins of all the musical symbols in the measure.
  double get horizontalMarginSum =>
      musicalSymbolsMetricses.map((symbol) => symbol.margin.horizontal).sum;

  /// Gets the thickness of the staff lines in the measure.
  double get staffLineThickness => metadata.staffLineThickness;

  /// Creates a [MeasureRenderer] object for rendering the measure.
  ///
  /// The [layout] parameter is a [SheetMusicLayout] object representing the layout
  /// of the sheet music.
  ///
  /// The [measureInitialX] parameter is the x-coordinate of the measure's origin.
  ///
  /// The [staffLineCenterY] parameter is the y-coordinate of the center of the staff lines.
  MeasureRenderer renderer(
    SheetMusicLayout layout, {
    required double measureInitialX,
    required double staffLineCenterY,
    double stretch = 1,
    double squeeze = 1,
    double marginScale = 1,
  }) {
    return MeasureRenderer(
      _symbolRenderers(
        layout,
        measureOriginX: measureInitialX,
        staffLineCenterY: staffLineCenterY,
        stretch: stretch,
        squeeze: squeeze,
        marginScale: marginScale,
      ),
      this,
      layout,
      measureOriginX: measureInitialX,
      staffLineCenterY: staffLineCenterY,
      stretch: stretch,
      squeeze: squeeze,
      marginScale: marginScale,
    );
  }

  List<MusicalSymbolRenderer> _symbolRenderers(
    SheetMusicLayout layout, {
    required double measureOriginX,
    required double staffLineCenterY,
    required double stretch,
    required double squeeze,
    required double marginScale,
  }) {
    final result = <MusicalSymbolRenderer>[];
    var x = measureOriginX;
    final scale = layout.canvasScale;
    for (final symbol in musicalSymbolsMetricses) {
      // A renderer sets its glyph its whole left margin in from symbolX; a
      // line whose margins are cut down hands it a symbolX moved back by
      // what was cut, so the glyph lands where the cut margin ends.
      final cutLeft = symbol.margin.left * (1 - marginScale) / scale;
      result.add(
        symbol.renderer(
          layout,
          staffLineCenterY: staffLineCenterY,
          symbolX: x - cutLeft,
        ),
      );
      // Stretching the width each symbol claims, rather than adding the same
      // gap everywhere, is what lets a short line fill the page without
      // flattening the difference between a whole note and a sixteenth.
      x += advanceIn(
            symbol,
            spreadOnlyNotes: layout.spreadOnlyNotes,
            stretch: stretch,
            squeeze: squeeze,
          ) +
          symbol.margin.horizontal * marginScale / scale;
    }
    return result;
  }
}
