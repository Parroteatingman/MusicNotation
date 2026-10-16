import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:simple_sheet_music/src/font_types.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:xml/xml.dart';

/// The font's glyphs and metrics, read and parsed once per font for the
/// life of the process. The SVG is close to 2 MB, so a page holding a
/// dozen staffs (a sheet of all twelve keys) used to parse it a dozen
/// times over and stall while it did.
class SheetMusicFont {
  const SheetMusicFont._(this.glyphPath, this.metadata);

  final GlyphPaths glyphPath;
  final GlyphMetadata metadata;

  static final Map<FontType, Future<SheetMusicFont>> _loading = {};
  static final Map<FontType, SheetMusicFont> _ready = {};

  /// The parsed font, already there for every staff after the first.
  static SheetMusicFont? ready(FontType fontType) => _ready[fontType];

  static Future<SheetMusicFont> load(FontType fontType) {
    return _loading.putIfAbsent(fontType, () async {
      try {
        final xml = await rootBundle.loadString(fontType.svgPath);
        final json = await rootBundle.loadString(fontType.metadataPath);
        final parsed = await _parse(xml, json);
        final font = SheetMusicFont._(
          GlyphPaths(parsed.glyphs),
          GlyphMetadata(parsed.metadata),
        );
        _ready[fontType] = font;
        return font;
      } catch (_) {
        // A failed read must not poison later attempts.
        _loading.removeWhere((key, _) => key == fontType);
        rethrow;
      }
    });
  }

  /// The glyphs and the metadata, parsed off the UI thread: the SVG is
  /// about 2 MB and the metadata 0.75 MB, and parsing them on the main
  /// isolate stalled the first staff shown (a hitch on the first 琶音 or
  /// 音阶 layer, chord card, lick…). `compute` hands the result back
  /// without copying it (the worker exits with it); should the worker
  /// fail, the parse runs here as it always did.
  static Future<_ParsedFont> _parse(String xml, String json) async {
    try {
      return await compute(_parseInWorker, <String>[xml, json]);
    } on Object catch (_) {
      return _parseNow(xml, json);
    }
  }

  static _ParsedFont _parseInWorker(List<String> sources) =>
      _parseNow(sources[0], sources[1]);

  static _ParsedFont _parseNow(String xml, String json) => _ParsedFont(
        XmlDocument.parse(xml).findAllElements('glyph').toSet(),
        jsonDecode(json) as Map<String, dynamic>,
      );
}

/// A font as parsed, before it is wrapped for drawing.
class _ParsedFont {
  const _ParsedFont(this.glyphs, this.metadata);

  final Set<XmlElement> glyphs;
  final Map<String, dynamic> metadata;
}
