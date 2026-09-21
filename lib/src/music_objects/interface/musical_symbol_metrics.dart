import 'package:flutter/rendering.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// An abstract class representing the metrics of a musical symbol.
///
/// This class defines the properties and methods that should be implemented
/// by classes representing the metrics of different musical symbols.
abstract class MusicalSymbolMetrics {
  /// The width of the musical symbol.
  double get width;

  /// The height above centre line of the stave of the musical symbol.
  double get upperHeight;

  /// The height below centre line of the stave of the musical symbol.
  double get lowerHeight;

  /// The margin around the musical symbol. Vertical margin is not used.
  EdgeInsets get margin;

  /// The musical time this symbol occupies, counted in quarter notes, after
  /// dots and tuplets are taken into account. Symbols that carry no time —
  /// clefs, key and time signatures — report 0 and are spaced on their glyph
  /// width alone.
  double get durationUnits;

  /// The part of the glyph drawn before the note head — an accidental, mostly.
  /// It leans into the space the previous note was given, so the spacing model
  /// hands it room of its own rather than letting it crowd its neighbour.
  double get leadingWidth;

  /// Creates a renderer for the musical symbol.
  ///
  /// The [layout] parameter provides information about the sheet music layout.
  /// The [staffLineCenterY] parameter specifies the y-coordinate of the center
  /// of the staff line where the symbol should be rendered.
  /// The [symbolX] parameter specifies the x-coordinate where the symbol should be rendered.
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  });
}
