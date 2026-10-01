import 'dart:ui';

/// What kind of symbol a [SheetSymbolBox] is.
enum SheetSymbolKind { note, rest, chord }

/// Where a note, a rest or a chord was drawn, in the widget's own
/// coordinates.
///
/// A caller writes under a note (a degree, a note name) or lights one up
/// while it sounds from these, on a layer of its own, without asking the
/// staff to lay itself out again.
class SheetSymbolBox {
  const SheetSymbolBox({
    required this.order,
    required this.line,
    required this.kind,
    required this.heads,
    required this.staffTop,
    required this.staffBottom,
    required this.inkBottom,
    this.measure = -1,
    this.measureLeft = 0,
    this.measureRight = 0,
    this.chordLabel,
  });

  /// The symbol's place among the page's notes, rests and chords, from 0.
  /// On a page without chords it is the index [SimpleSheetMusic.onSymbolTap]
  /// reports.
  final int order;

  /// The line of the page the symbol is on, from 0.
  final int line;

  final SheetSymbolKind kind;

  /// The heads as drawn: one for a note, one for each note of a chord, the
  /// glyph itself for a rest.
  final List<Path> heads;

  /// The top and the bottom line of the symbol's staff.
  final double staffTop;
  final double staffBottom;

  /// How far down the symbol's ink reaches: its stem and flag, the beam
  /// under it, a tuplet bracket under it. Anything written under the note
  /// starts below this.
  final double inkBottom;

  /// The measure the symbol is in, counted from 0 across the page.
  final int measure;

  /// Where that measure starts and ends across the page — barline to
  /// barline as drawn — so a caller can tint a bar, or line it up with
  /// something drawn beside the staff.
  final double measureLeft;
  final double measureRight;

  /// Around the chord name written over the symbol, if any.
  final Rect? chordLabel;

  /// Around all the heads.
  Rect get headBounds {
    var bounds = heads.first.getBounds();
    for (final head in heads.skip(1)) {
      bounds = bounds.expandToInclude(head.getBounds());
    }
    return bounds;
  }

  /// Across the middle of the heads: where a label under the note centres.
  double get centerX => headBounds.center.dx;
}
