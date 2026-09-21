import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/music_objects/notes/note_duration.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest_type.dart';

void main() {
  group('note values', () {
    test('a quarter note is the unit', () {
      expect(NoteDuration.quarter.quarterUnits, 1);
      expect(RestType.quarter.quarterUnits, 1);
    });

    test('each step down halves the value', () {
      expect(NoteDuration.whole.quarterUnits, 4);
      expect(NoteDuration.half.quarterUnits, 2);
      expect(NoteDuration.eighth.quarterUnits, 0.5);
      expect(NoteDuration.sixteenth.quarterUnits, 0.25);
    });

    test('a dot adds half again', () {
      expect(NoteSpacing.unitsOf(1, isDotted: true), 1.5);
      expect(NoteSpacing.unitsOf(0.5, isDotted: true), 0.75);
    });

    test('a triplet fits three notes into two', () {
      expect(NoteSpacing.unitsOf(0.5, tuplet: 3), closeTo(1 / 3, 1e-9));
    });

    test('five and seven fit into four', () {
      expect(NoteSpacing.unitsOf(1, tuplet: 5), closeTo(0.8, 1e-9));
      expect(NoteSpacing.unitsOf(1, tuplet: 7), closeTo(4 / 7, 1e-9));
    });
  });

  group('spacing', () {
    const eighthWidth = 300.0;
    const reference =
        SpacingReference(units: 0.5, naturalWidth: eighthWidth);

    double spaces(double units) =>
        (reference.spaceFor(units) - eighthWidth) / Constants.staffSpace;

    test('the shortest note keeps the width it already had', () {
      expect(reference.spaceFor(0.5), eighthWidth);
    });

    test('a longer note is given more room', () {
      expect(spaces(4), greaterThan(spaces(2)));
      expect(spaces(2), greaterThan(spaces(1)));
      expect(spaces(1), greaterThan(spaces(0.5)));
    });

    test('each doubling adds the same increment', () {
      expect(spaces(1) - spaces(0.5), closeTo(NoteSpacing.incrementSpaces, 1e-9));
      expect(spaces(2) - spaces(1), closeTo(NoteSpacing.incrementSpaces, 1e-9));
      expect(spaces(4) - spaces(2), closeTo(NoteSpacing.incrementSpaces, 1e-9));
    });

    test('a symbol with no duration asks for nothing', () {
      expect(reference.spaceFor(0), 0);
      expect(reference.spaceFor(-1), 0);
    });

    test('with nothing to measure, a symbol falls back to its glyph', () {
      expect(SpacingReference.none.spaceFor(4), 0);
      expect(
        SpacingReference.none.advanceOf(_FakeSymbol(width: 210, units: 4)),
        210,
      );
    });

    test('an accidental is given room of its own', () {
      final plain = reference.advanceOf(_FakeSymbol(width: 300, units: 1));
      final withFlat = reference.advanceOf(
        _FakeSymbol(width: 380, units: 1, leading: 80),
      );
      expect(withFlat - plain, 80);
    });

    test('a symbol never sets tighter than its own glyph', () {
      // A wide glyph on a short value keeps its width.
      expect(
        reference.advanceOf(_FakeSymbol(width: 900, units: 0.5)),
        900,
      );
    });
  });

  group('reading the reference off a page', () {
    test('the shortest value on the page sets the unit', () {
      final reference = SpacingReference.of([
        _FakeSymbol(width: 300, units: 1),
        _FakeSymbol(width: 280, units: 0.25),
        _FakeSymbol(width: 400, units: 4),
        _FakeSymbol(width: 120, units: 0), // a clef
      ]);
      expect(reference.units, 0.25);
      expect(reference.naturalWidth, 280);
    });

    test('the widest of the shortest sets the width, bar its accidental', () {
      final reference = SpacingReference.of([
        _FakeSymbol(width: 260, units: 0.5),
        _FakeSymbol(width: 340, units: 0.5, leading: 90),
      ]);
      expect(reference.units, 0.5);
      expect(reference.naturalWidth, 260);
    });

    test('a page with no notes has nothing to measure', () {
      final reference = SpacingReference.of([_FakeSymbol(width: 120, units: 0)]);
      expect(reference, SpacingReference.none);
    });
  });
}

class _FakeSymbol implements MusicalSymbolMetrics {
  _FakeSymbol({required this.width, required double units, double leading = 0})
      : durationUnits = units,
        leadingWidth = leading;

  @override
  final double width;

  @override
  final double durationUnits;

  @override
  final double leadingWidth;

  @override
  double get upperHeight => 0;

  @override
  double get lowerHeight => 0;

  @override
  EdgeInsets get margin => EdgeInsets.zero;

  @override
  MusicalSymbolRenderer renderer(
    SheetMusicLayout layout, {
    required double staffLineCenterY,
    required double symbolX,
  }) =>
      throw UnimplementedError();
}
