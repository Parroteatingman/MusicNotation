import 'dart:math';

import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';

/// Horizontal spacing by note value, the way engravers set music.
///
/// Laying symbols out end to end gives a whole note and a sixteenth the same
/// width, so a page reads as though the rhythm were even. Engraved music
/// widens a note by a fixed increment for every doubling of its value rather
/// than in proportion to it: a half note is wider than a quarter, but nowhere
/// near twice as wide. That is LilyPond's `spacing-increment` model, and the
/// same curve underlies Gould's spacing tables in *Behind Bars*.
///
/// The measurement is relative, not absolute: the shortest note on the page
/// keeps the width it would have had anyway, and everything longer is widened
/// from there. A run of even eighths is therefore set exactly as tightly as it
/// was before this model existed, and only mixed rhythm opens up.
class NoteSpacing {
  const NoteSpacing._();

  /// Width added per doubling of the note value, in staff spaces.
  static const double incrementSpaces = 1.3;

  /// The musical time a written symbol occupies, counted in quarter notes.
  ///
  /// [base] is the value as written (4 for a whole note, 1 for a quarter, 0.5
  /// for an eighth). A dot adds half of it again. A tuplet of [tuplet] notes
  /// fits them into the space of the next power of two below — three into two,
  /// five or seven into four — so each note is shortened by that ratio.
  static double unitsOf(
    double base, {
    bool isDotted = false,
    int? tuplet,
  }) {
    var units = base;
    if (isDotted) units *= 1.5;
    if (tuplet != null && tuplet > 1) {
      units *= _tupletNormalCount(tuplet) / tuplet;
    }
    return units;
  }

  /// How many notes of the written value a tuplet of [actual] notes replaces.
  static double _tupletNormalCount(int actual) {
    var normal = 1;
    while (normal * 2 < actual) {
      normal *= 2;
    }
    return normal.toDouble();
  }
}

/// What the spacing model measures against: the shortest note on the page and
/// the width it takes on its own.
///
/// Holding the shortest note to its natural width is what keeps this from
/// shrinking the notation. The page only grows where a longer value earns the
/// room, and a page of one value does not grow at all.
class SpacingReference {
  const SpacingReference({required this.units, required this.naturalWidth});

  /// No note values to measure — every symbol falls back to its glyph width.
  static const SpacingReference none =
      SpacingReference(units: 0, naturalWidth: 0);

  /// The shortest value written on the page, in quarter notes.
  final double units;

  /// The width that shortest value takes, not counting anything drawn in
  /// front of the note head.
  final double naturalWidth;

  /// Reads the reference off everything that will be set on the page.
  factory SpacingReference.of(Iterable<MusicalSymbolMetrics> symbols) {
    var shortest = double.infinity;
    for (final symbol in symbols) {
      final units = symbol.durationUnits;
      if (units > 0 && units < shortest) shortest = units;
    }
    if (!shortest.isFinite) return none;

    var width = 0.0;
    for (final symbol in symbols) {
      if (symbol.durationUnits != shortest) continue;
      final bare = symbol.width - symbol.leadingWidth;
      if (bare > width) width = bare;
    }
    return SpacingReference(units: shortest, naturalWidth: width);
  }

  /// The room a note lasting [units] quarter notes asks for.
  ///
  /// Symbols with no duration of their own — clefs, key and time signatures —
  /// ask for nothing and are set on their glyph width alone.
  double spaceFor(double units) {
    if (units <= 0 || this.units <= 0) return 0;
    final doublings = log(units / this.units) / ln2;
    return naturalWidth +
        NoteSpacing.incrementSpaces * Constants.staffSpace * doublings;
  }

  /// How much of the line [symbol] claims: never less than its own glyph, and
  /// never less than its value asks for. Whatever it carries in front of its
  /// head is added on top, since that is width its neighbour cannot share.
  double advanceOf(MusicalSymbolMetrics symbol) => max(
        symbol.width,
        spaceFor(symbol.durationUnits) + symbol.leadingWidth,
      );
}
