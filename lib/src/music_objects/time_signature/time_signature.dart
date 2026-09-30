import 'package:flutter/material.dart';

import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';

/// C and ¢ instead of the numbers.
enum TimeSignatureSymbol { common, cut }

/// A time signature: [beats] over [beatType] in the font's time-signature
/// digits (SMuFL timeSig0–9, each two staff spaces tall and centred on its
/// baseline), or the common / cut-time sign. It holds no musical time.
class TimeSignature implements MusicalSymbol {
  const TimeSignature(
    this.beats,
    this.beatType, {
    this.symbol,
    this.color = Colors.black,
    this.margin = const EdgeInsets.symmetric(horizontal: 8),
  });

  final int beats;
  final int beatType;
  final TimeSignatureSymbol? symbol;

  @override
  final Color color;

  @override
  final EdgeInsets margin;

  @override
  MusicalSymbolMetrics setContext(
    MusicalContext context,
    GlyphMetadata metadata,
    GlyphPaths paths,
  ) =>
      TimeSignatureMetrics(this, paths);
}

class TimeSignatureMetrics implements MusicalSymbolMetrics {
  TimeSignatureMetrics(this.timeSignature, GlyphPaths paths)
      : parts = _parts(timeSignature, paths);

  final TimeSignature timeSignature;

  /// Every glyph, already moved to where it sits: x from the symbol's left
  /// edge, y from the staff's middle line.
  final List<Path> parts;

  static String _digit(int d) => 'uniE08${d.clamp(0, 9)}';

  static List<Path> _row(String number, GlyphPaths paths, double y) {
    final glyphs = [
      for (final c in number.split('')) paths.parsePath(_digit(int.parse(c))),
    ];
    final out = <Path>[];
    var x = 0.0;
    for (final g in glyphs) {
      final b = g.getBounds();
      out.add(g.shift(Offset(x - b.left, y)));
      x += b.width + Constants.staffSpace * 0.05;
    }
    return out;
  }

  static List<Path> _parts(TimeSignature t, GlyphPaths paths) {
    final symbol = t.symbol;
    if (symbol != null) {
      final g = paths.parsePath(
        symbol == TimeSignatureSymbol.common ? 'uniE08A' : 'uniE08B',
      );
      return [g.shift(Offset(-g.getBounds().left, 0))];
    }
    // the numbers fill the upper and the lower half of the staff; the
    // narrower row is centred on the wider
    final top = _row('${t.beats}', paths, -Constants.staffSpace);
    final bottom = _row('${t.beatType}', paths, Constants.staffSpace);
    double widthOf(List<Path> row) => row.isEmpty
        ? 0
        : row.map((p) => p.getBounds().right).reduce((a, b) => a > b ? a : b);
    final wt = widthOf(top);
    final wb = widthOf(bottom);
    final w = wt > wb ? wt : wb;
    return [
      for (final p in top) p.shift(Offset((w - wt) / 2, 0)),
      for (final p in bottom) p.shift(Offset((w - wb) / 2, 0)),
    ];
  }

  Rect get bbox => parts.isEmpty
      ? Rect.zero
      : parts.map((p) => p.getBounds()).reduce((a, b) => a.expandToInclude(b));

  @override
  double get width => bbox.right;

  @override
  double get upperHeight => -bbox.top;

  @override
  double get lowerHeight => bbox.bottom;

  @override
  EdgeInsets get margin => timeSignature.margin;

  @override
  double get durationUnits => 0;

  @override
  double get leadingWidth => 0;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      TimeSignatureRenderer(
        this,
        layout,
        symbolX: symbolX,
        staffLineCenterY: staffLineCenterY,
      );
}

class TimeSignatureRenderer implements MusicalSymbolRenderer {
  const TimeSignatureRenderer(
    this.metrics,
    this.layout, {
    required this.symbolX,
    required this.staffLineCenterY,
  });

  final TimeSignatureMetrics metrics;
  final SheetMusicLayout layout;
  final double staffLineCenterY;

  @override
  final double symbolX;

  Offset get renderOffset => Offset(
        symbolX + metrics.margin.left / layout.canvasScale,
        staffLineCenterY,
      );

  @override
  bool isHit(Offset position) =>
      metrics.bbox.shift(renderOffset).contains(position);

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = metrics.timeSignature.color
      ..style = PaintingStyle.fill;
    for (final p in metrics.parts) {
      canvas.drawPath(p.shift(renderOffset), paint);
    }
  }
}
