import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/system/staff_system_layout.dart';
import 'package:xml/xml.dart';

/// Several staffs set as one system: what starts together stands together,
/// the staffs keep clear of each other, and one staff sets as it always did.
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

  const scale = 7.5 / 250;
  StaffSystemLayout system(
    List<SheetStaff> staffs, {
    double width = 400,
    List<StaffGroup> groups = const [],
    bool justify = true,
  }) =>
      StaffSystemLayout(
        staffs: staffs,
        metadata: metadata,
        paths: paths,
        canvasScale: scale,
        width: width,
        groups: groups,
        justify: justify,
      );

  Note n(Pitch p, NoteDuration d, {bool dot = false, int? tuplet}) =>
      Note(p, noteDuration: d, isDotted: dot, tuplet: tuplet);

  test('a chord counts its dot and its tuplet', () {
    final dotted = const ChordNote(
      [ChordNotePart(Pitch.c4), ChordNotePart(Pitch.e4)],
      isDotted: true,
    ).setContext(
        const MusicalContext(ClefType.treble, KeySignatureType.cMajor),
        metadata,
        paths);
    expect(dotted.durationUnits, 1.5);
    final triplet = const ChordNote(
      [ChordNotePart(Pitch.c4), ChordNotePart(Pitch.e4)],
      noteDuration: NoteDuration.eighth,
      tuplet: 3,
    ).setContext(
        const MusicalContext(ClefType.treble, KeySignatureType.cMajor),
        metadata,
        paths);
    expect(triplet.durationUnits, closeTo(1 / 3, 1e-9));
  });

  test('what starts at the same moment stands at the same place', () {
    final layout = system(
      [
        SheetStaff([
          Measure([
            const Clef(ClefType.treble),
            n(Pitch.c5, NoteDuration.quarter, dot: true),
            n(Pitch.d5, NoteDuration.eighth),
            n(Pitch.e5, NoteDuration.half),
          ]),
        ]),
        SheetStaff([
          Measure([
            const Clef(ClefType.bass),
            n(Pitch.c3, NoteDuration.quarter),
            n(Pitch.e3, NoteDuration.quarter),
            n(Pitch.g3, NoteDuration.eighth, tuplet: 3),
            n(Pitch.a3, NoteDuration.eighth, tuplet: 3),
            n(Pitch.b3, NoteDuration.eighth, tuplet: 3),
            n(Pitch.c4, NoteDuration.quarter),
          ]),
        ], clef: ClefType.bass),
      ],
      groups: const [StaffGroup.grandStaff(0, 1)],
    );
    final geometry = layout.geometry();
    final upper = geometry.symbolsOn(0).map((b) => b.headBounds.left).toList();
    final lower = geometry.symbolsOn(1).map((b) => b.headBounds.left).toList();
    // Beat 1 on both; beat 3 (the half note, the first triplet note).
    expect(upper[0], closeTo(lower[0], 0.5));
    expect(upper[2], closeTo(lower[2], 0.5));
    // The eighth on beat 2½ falls between the lower staff's beats 2 and 3.
    expect(upper[1], greaterThan(lower[1]));
    expect(upper[1], lessThan(lower[2]));
    // Moments in time order across the line, on each staff.
    for (final xs in [upper, lower]) {
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]));
      }
    }
  });

  test('a note held over several moments keeps its own room', () {
    final layout = system(
      [
        SheetStaff([
          Measure([
            n(Pitch.c5, NoteDuration.quarter),
            n(Pitch.d5, NoteDuration.half),
            n(Pitch.e5, NoteDuration.quarter),
          ]),
        ]),
        SheetStaff([
          Measure([
            n(Pitch.c4, NoteDuration.half),
            n(Pitch.d4, NoteDuration.half),
          ]),
        ]),
      ],
      justify: false,
    );
    final geometry = layout.geometry();
    final upper = geometry.symbolsOn(0).map((b) => b.headBounds.left).toList();
    final lower = geometry.symbolsOn(1).map((b) => b.headBounds.left).toList();
    expect(upper[0], closeTo(lower[0], 0.5));
    // The lower half note on beat 3 sits inside the upper one's half note.
    expect(lower[1], greaterThan(upper[1]));
    expect(lower[1], lessThan(upper[2]));
  });

  test('every staff holds the same measures', () {
    expect(
      () => system([
        SheetStaff([Measure([n(Pitch.c5, NoteDuration.whole)])]),
        SheetStaff([
          Measure([n(Pitch.c4, NoteDuration.whole)]),
          Measure([n(Pitch.c4, NoteDuration.whole)]),
        ]),
      ]),
      throwsArgumentError,
    );
  });

  test('the brace takes room before the opening line', () {
    final staffs = [
      SheetStaff([Measure([n(Pitch.c5, NoteDuration.whole)])]),
      SheetStaff([Measure([n(Pitch.c3, NoteDuration.whole)])],
          clef: ClefType.bass),
    ];
    final plain = system(staffs).geometry();
    final braced = system(
      staffs,
      groups: const [StaffGroup.grandStaff(0, 1)],
    ).geometry();
    expect(plain.contentLeft, 0);
    expect(braced.contentLeft, greaterThan(7.5 * 0.5));
    // A bracket's hooks reach over the first staff: room is kept for them.
    final bracketed = system(
      staffs,
      groups: const [StaffGroup(0, 1, kind: StaffGroupKind.bracket)],
    );
    expect(bracketed.naturalHeight, greaterThan(system(staffs).naturalHeight));
  });

  test('a lit note keeps its place and its chord name its colour', () {
    const note = Note(Pitch.c5, chordLabel: 'C', chordLabelColor: Colors.blue);
    final lit = note.withColor(Colors.red);
    expect(lit.color, Colors.red);
    expect(lit.chordLabelColor, Colors.blue);
    expect(lit.pitch, note.pitch);
    expect(note.withoutChordLabel().chordLabel, isNull);
  });
}
