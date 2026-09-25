import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/src/font_types.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_pitch.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest_type.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';
import 'package:xml/xml.dart';

import '../mock/mock_sheet_music_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlyphMetadata metadata;
  late GlyphPaths paths;
  setUpAll(() async {
    final xml = await rootBundle.loadString(FontType.bravuraSvgPath);
    paths =
        GlyphPaths(XmlDocument.parse(xml).findAllElements('glyph').toSet());
    final json = await rootBundle.loadString(FontType.bravuraMetadataPath);
    metadata = GlyphMetadata(jsonDecode(json) as Map<String, dynamic>);
  });

  const context = MusicalContext(ClefType.treble, KeySignatureType.cMajor);
  final layout = SheetMusicLayout(
    MockSheetMusicMetrics(maximumStaffWidth: 100, staffsHeightSum: 1),
    Colors.black,
    widgetHeight: 100,
    widgetWidth: 100,
  );

  // Paints one symbol at a tenth of its size and returns every opaque colour
  // in it. The test font draws each letter as a solid box, so a chord label
  // leaves plenty of pixels in exactly its own colour.
  Future<Set<Color>> colorsOf(MusicalSymbol symbol) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(0.1);
    symbol
        .setContext(context, metadata, paths)
        .renderer(layout, staffLineCenterY: 1500, symbolX: 200)
        .render(canvas);
    final image = await recorder.endRecording().toImage(200, 200);
    final bytes = (await image.toByteData())!;
    final colors = <Color>{};
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 3) != 255) {
        continue;
      }
      colors.add(Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1),
          bytes.getUint8(i + 2)));
    }
    return colors;
  }

  const ink = Color(0xFF0000FF);
  const label = Color(0xFFFF0000);
  const black = Color(0xFF000000);

  group('a chord label', () {
    test('above a note is black unless told otherwise', () async {
      final colors = await colorsOf(
          const Note(Pitch.b4, color: ink, chordLabel: 'Dm7'));
      expect(colors, contains(black));
      expect(colors, isNot(contains(label)));
    });

    test('above a note takes its own colour, not the note\'s', () async {
      final colors = await colorsOf(const Note(Pitch.b4,
          color: ink, chordLabel: 'Dm7', chordLabelColor: label));
      expect(colors, contains(label));
      expect(colors, contains(ink));
      expect(colors, isNot(contains(black)));
    });

    test('above a rest is black unless told otherwise', () async {
      final colors = await colorsOf(
          const Rest(RestType.quarter, color: ink, chordLabel: 'G7'));
      expect(colors, contains(black));
      expect(colors, isNot(contains(label)));
    });

    test('above a rest takes its own colour, not the rest\'s', () async {
      final colors = await colorsOf(const Rest(RestType.quarter,
          color: ink, chordLabel: 'G7', chordLabelColor: label));
      expect(colors, contains(label));
      expect(colors, contains(ink));
      expect(colors, isNot(contains(black)));
    });
  });
}
