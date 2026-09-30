import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/sheet_music_renderer.dart';
import 'package:simple_sheet_music/src/measure/barline.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlyphMetadata metadata;
  late GlyphPaths paths;
  setUpAll(() async {
    final xml = await rootBundle.loadString(FontType.bravuraSvgPath);
    paths = GlyphPaths(XmlDocument.parse(xml).findAllElements('glyph').toSet());
    final json = await rootBundle.loadString(FontType.bravuraMetadataPath);
    metadata = GlyphMetadata(jsonDecode(json) as Map<String, dynamic>);
  });

  const context = MusicalContext(ClefType.treble, KeySignatureType.cMajor);
  const space = Constants.staffSpace;

  test('the numbers of a time signature fill the two halves of the staff', () {
    final four = const TimeSignature(3, 4).setContext(context, metadata, paths)
        as TimeSignatureMetrics;
    expect(four.upperHeight, closeTo(2 * space, 0.05 * space));
    expect(four.lowerHeight, closeTo(2 * space, 0.05 * space));
    final twelve = const TimeSignature(12, 8)
        .setContext(context, metadata, paths) as TimeSignatureMetrics;
    expect(twelve.width, greaterThan(1.5 * four.width));
    expect(twelve.durationUnits, 0);
    final common = const TimeSignature(4, 4, symbol: TimeSignatureSymbol.common)
        .setContext(context, metadata, paths) as TimeSignatureMetrics;
    expect(common.parts, hasLength(1));
    expect(common.upperHeight, closeTo(space, 0.05 * space));
  });

  test('a start repeat is set after the clef, key and time, before the notes',
      () {
    final symbols = [
      const Clef(ClefType.treble),
      const KeySignature(KeySignatureType.dMajor),
      const TimeSignature(3, 4),
      const Note(Pitch.d4),
      const Note(Pitch.e4),
    ];
    final metrics = Measure(symbols, startRepeat: true)
        .setContext(context, metadata, paths);
    expect(metrics, hasLength(6));
    expect(metrics[3], isA<RepeatStartMetrics>());
    expect(metrics.last.durationUnits, greaterThan(0));

    final bare = Measure([const Note(Pitch.d4)], startRepeat: true)
        .setContext(context, metadata, paths);
    expect(bare.first, isA<RepeatStartMetrics>());
  });

  test('an end barline keeps room for itself; a single line keeps none', () {
    final notes = [const Note(Pitch.d4)];
    int count(BarlineType? type) => Measure(notes, endBarline: type)
        .setContext(context, metadata, paths)
        .length;
    expect(count(null), 1);
    expect(count(BarlineType.single), 1);
    expect(count(BarlineType.doubleLine), 2);
    expect(count(BarlineType.finalLine), 2);
    expect(count(BarlineType.repeatEnd), 2);
    final painter = BarlinePainter(metadata.staffLineThickness);
    expect(
      painter.roomFor(BarlineType.repeatEnd),
      greaterThan(painter.roomFor(BarlineType.finalLine)),
    );
  });

  // Paints a line of music the way the widget does and returns its ink: how
  // many pixels are drawn at all.
  Future<int> inkOf(List<Measure> measures) async {
    const size = Size(600, 120);
    final layout = SheetMusicLayout(
      SheetMusicMetrics(
        measures,
        ClefType.treble,
        KeySignatureType.cMajor,
        metadata,
        paths,
      ),
      Colors.black,
      widgetHeight: size.height,
      widgetWidth: size.width,
    );
    final recorder = ui.PictureRecorder();
    SheetMusicRenderer(layout, repaintKey: 0).paint(Canvas(recorder), size);
    final image = await recorder
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt());
    final bytes = (await image.toByteData())!;
    var ink = 0;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 128) ink++;
    }
    return ink;
  }

  test('typed barlines draw: more ink than plain ones, and a line of each kind',
      () async {
    List<Measure> two({BarlineType? end, bool repeat = false}) => [
          Measure(
            [const Note(Pitch.d4, noteDuration: NoteDuration.whole)],
            endBarline: end,
          ),
          Measure(
            [const Note(Pitch.d4, noteDuration: NoteDuration.whole)],
            startRepeat: repeat,
          ),
        ];
    final plain = await inkOf(two());
    expect(await inkOf(two(end: BarlineType.single)), plain);
    final doubled = await inkOf(two(end: BarlineType.doubleLine));
    final heavy = await inkOf(two(end: BarlineType.finalLine));
    final repeatEnd = await inkOf(two(end: BarlineType.repeatEnd));
    final both = await inkOf(two(end: BarlineType.repeatEnd, repeat: true));
    expect(doubled, greaterThan(plain));
    expect(heavy, greaterThan(doubled));
    expect(repeatEnd, greaterThan(heavy));
    // :‖: shares one thick line — less ink than two whole repeat signs
    final start = await inkOf(two(repeat: true));
    expect(both, lessThan(repeatEnd + start - plain));
    expect(both, greaterThan(repeatEnd));
  });
}
