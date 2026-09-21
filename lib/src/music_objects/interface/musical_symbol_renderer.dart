import 'package:flutter/rendering.dart';

/// An abstract class representing a renderer for a musical symbol.
abstract class MusicalSymbolRenderer {
  MusicalSymbolRenderer();

  /// Where the symbol starts on the line, in canvas coordinates. The caret
  /// is drawn against this.
  double get symbolX;

  /// Checks if the symbol is hit at the given position.
  bool isHit(Offset position);

  /// Renders the symbol on the given canvas.
  void render(Canvas canvas);
}
