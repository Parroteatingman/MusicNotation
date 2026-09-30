import 'dart:math';

import 'package:simple_sheet_music/src/extension/list_extension.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/measure/barline.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
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
  }) {
    return MeasureRenderer(
      _symbolRenderers(
        layout,
        measureOriginX: measureInitialX,
        staffLineCenterY: staffLineCenterY,
        stretch: stretch,
      ),
      this,
      layout,
      measureOriginX: measureInitialX,
      staffLineCenterY: staffLineCenterY,
      stretch: stretch,
    );
  }

  List<MusicalSymbolRenderer> _symbolRenderers(
    SheetMusicLayout layout, {
    required double measureOriginX,
    required double staffLineCenterY,
    required double stretch,
  }) {
    final result = <MusicalSymbolRenderer>[];
    var x = measureOriginX;
    for (final symbol in musicalSymbolsMetricses) {
      result.add(
        symbol.renderer(
          layout,
          staffLineCenterY: staffLineCenterY,
          symbolX: x,
        ),
      );
      // Stretching the width each symbol claims, rather than adding the same
      // gap everywhere, is what lets a short line fill the page without
      // flattening the difference between a whole note and a sixteenth.
      final spread =
          layout.spreadOnlyNotes && symbol.durationUnits <= 0 ? 1 : stretch;
      x += spacing.advanceOf(symbol) * spread +
          symbol.margin.horizontal / layout.canvasScale;
    }
    return result;
  }
}
