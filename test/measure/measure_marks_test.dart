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

  const space = Constants.staffSpace;

  SheetMusicLayout layout(List<Measure> measures) => SheetMusicLayout(
        SheetMusicMetrics(
          measures,
          ClefType.treble,
          KeySignatureType.cMajor,
          metadata,
          paths,
        ),
        Colors.black,
        widgetHeight: 120,
        widgetWidth: 600,
      );

  List<MusicalSymbol> bar() => [
        const Note(Pitch.c5, noteDuration: NoteDuration.half, chordLabel: 'Cmaj7'),
        const Note(Pitch.e5, noteDuration: NoteDuration.half, chordLabel: 'A7'),
      ];

  test('marks over a line raise it by their band; a line without them is as it was', () {
    final plain = layout([Measure(bar()), Measure(bar())]);
    final marked = layout([
      Measure(bar(), marks: const [MeasureMark.rehearsal('A'), MeasureMark.segno()]),
      Measure(bar(), volta: const Volta('1.')),
    ]);
    final upperPlain = plain.metrics.staffUpperHeight;
    expect(upperPlain, closeTo(5.4 * space, 0.01 * space));
    expect(marked.metrics.staffUpperHeight,
        closeTo((5.4 + MeasureMark.bandSpaces) * space, 0.01 * space));
    expect(plain.markBoxes(), isEmpty);
  });

  test('marks sit side by side over the chord names, an ending over them all', () {
    final l = layout([
      Measure([const Clef(ClefType.treble), ...bar()],
          marks: const [MeasureMark.rehearsal('A'), MeasureMark.segno(), MeasureMark.words('Fine')]),
      Measure(bar(), volta: const Volta('1.', ends: false)),
      Measure(bar(), volta: const Volta('1.', starts: false), marks: const [MeasureMark.words('D.S. al Coda')]),
      Measure(bar(), volta: const Volta('2.', closed: false), marks: const [MeasureMark.coda(at: 1)]),
    ]);
    final boxes = l.markBoxes();
    final kinds = boxes.map((b) => b.kind).toSet();
    expect(kinds, containsAll(SheetMarkKind.values));
    // one label per ending, where it starts
    expect([for (final b in boxes) if (b.kind == SheetMarkKind.voltaLabel) b.measure], [1, 3]);
    final band = [for (final b in boxes) if (b.kind != SheetMarkKind.voltaLine) b.rect];
    for (var i = 0; i < band.length; i++) {
      for (var j = i + 1; j < band.length; j++) {
        expect(band[i].overlaps(band[j]), isFalse, reason: '${boxes[i].kind} / ${boxes[j].kind}');
      }
    }
    // above every chord name, under the endings' brackets
    final chordTop = l.symbolBoxes().map((b) => b.chordLabel!.top).reduce((a, b) => a < b ? a : b);
    final bracket = boxes
        .where((b) => b.kind == SheetMarkKind.voltaLine && b.rect.width > b.rect.height)
        .map((b) => b.rect.bottom)
        .reduce((a, b) => a > b ? a : b);
    for (final r in band) {
      expect(r.bottom, lessThan(chordTop));
      expect(r.top, greaterThan(bracket));
    }
    // and it draws
    final recorder = ui.PictureRecorder();
    SheetMusicRenderer(l, repaintKey: 0).paint(Canvas(recorder), const Size(600, 120));
    recorder.endRecording().dispose();
  });
}
