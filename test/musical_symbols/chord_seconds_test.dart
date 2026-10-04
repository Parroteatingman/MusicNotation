import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/src/font_types.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/chord_note.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/chord_note_part.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_pitch.dart';
import 'package:simple_sheet_music/src/music_objects/notes/stem_direction.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:xml/xml.dart';

/// Seconds in a chord sit on opposite sides of the stem, a run of them
/// alternating (Gould, Behind Bars; Wikipedia "Stem (music)").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlyphMetadata metadata;
  late GlyphPaths paths;
  setUpAll(() async {
    final json = await rootBundle.loadString(FontType.bravuraMetadataPath);
    metadata = GlyphMetadata(jsonDecode(json) as Map<String, dynamic>);
    final xml = await rootBundle.loadString(FontType.bravuraSvgPath);
    paths = GlyphPaths(XmlDocument.parse(xml).findAllElements('glyph').toSet());
  });

  ChordNoteMetrics chord(
    List<Pitch> pitches, {
    NoteDuration duration = NoteDuration.quarter,
    StemDirection? stem,
  }) =>
      ChordNote(
        [for (final p in pitches) ChordNotePart(p)],
        noteDuration: duration,
        stemDirection: stem,
      ).setContext(
        const MusicalContext(ClefType.treble, KeySignatureType.cMajor),
        metadata,
        paths,
      ) as ChordNoteMetrics;

  /// The left x of each head, rounded, in the order the pitches were given.
  List<double> lefts(ChordNoteMetrics m) => [
        for (final p in m.noteHeadsPaths)
          (p.getBounds().left * 1000).roundToDouble() / 1000,
      ];

  /// Which heads are in the right-hand column.
  List<bool> onRight(ChordNoteMetrics m) {
    final xs = lefts(m);
    final left = xs.reduce((a, b) => a < b ? a : b);
    return [for (final x in xs) x > left + 0.01];
  }

  test('C–D–E stem up: bottom and top left, D right of the stem', () {
    final m = chord([Pitch.c4, Pitch.d4, Pitch.e4], stem: StemDirection.up);
    expect(onRight(m), [false, true, false]);
    // The stem runs between the columns, both heads touching it.
    final stemX = m.stemRootOffset.dx;
    final heads = m.noteHeadsPaths.map((p) => p.getBounds()).toList();
    expect(stemX, inInclusiveRange(heads[1].left, heads[0].right));
  });

  test('C–D–E stem down: top and bottom right, D left of the stem', () {
    final m = chord([Pitch.c5, Pitch.d5, Pitch.e5], stem: StemDirection.down);
    expect(onRight(m), [true, false, true]);
    final stemX = m.stemRootOffset.dx;
    final heads = m.noteHeadsPaths.map((p) => p.getBounds()).toList();
    expect(stemX, inInclusiveRange(heads[0].left, heads[1].right));
    // The displaced head counts as width in front of the chord.
    expect(m.leadingWidth, greaterThan(0));
  });

  test('C–D–E–F stem down alternates from the top', () {
    final m = chord(
      [Pitch.c5, Pitch.d5, Pitch.e5, Pitch.f5],
      stem: StemDirection.down,
    );
    // F normal (right), E left, D right, C left.
    expect(onRight(m), [false, true, false, true]);
  });

  test('G B C D E whole notes: G B D left, C E right, heads touching', () {
    final m = chord(
      [Pitch.g4, Pitch.b4, Pitch.c5, Pitch.d5, Pitch.e5],
      duration: NoteDuration.whole,
    );
    expect(onRight(m), [false, false, true, false, true]);
    final heads = m.noteHeadsPaths.map((p) => p.getBounds()).toList();
    // C sits right next to B and D, not on top of them.
    expect(heads[2].left, closeTo(heads[1].right, 0.05));
    expect(heads[2].overlaps(heads[1].deflate(0.01)), isFalse);
    expect(heads[4].overlaps(heads[3].deflate(0.01)), isFalse);
  });

  test('G B C D E stem up and stem down', () {
    final up = chord(
      [Pitch.g4, Pitch.b4, Pitch.c5, Pitch.d5, Pitch.e5],
      stem: StemDirection.up,
    );
    expect(onRight(up), [false, false, true, false, true]);
    final down = chord(
      [Pitch.g4, Pitch.b4, Pitch.c5, Pitch.d5, Pitch.e5],
      stem: StemDirection.down,
    );
    // E normal, D displaced, C normal, B displaced, G normal.
    expect(onRight(down), [true, false, true, false, true]);
  });

  test('a chord with no seconds keeps one column', () {
    final m = chord([Pitch.c4, Pitch.e4, Pitch.g4]);
    expect(onRight(m), [false, false, false]);
    expect(m.leadingWidth, 0);
  });
}
