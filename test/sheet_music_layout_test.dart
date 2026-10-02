import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';
import 'package:simple_sheet_music/src/staff/staff_metrics.dart';

import 'mock/mock_sheet_music_metrics.dart';

void main() {
  test(
      'SheetMusicLayout.canvasScale should be the minimum scale factor to fit the sheet music in the widget',
      () {
    // Arrange
    const maximumStaffWidth = 100.0;
    final metrics = MockSheetMusicMetrics(
      maximumStaffWidth: maximumStaffWidth,
      staffsHeightSum: 1,
    );
    const widgetWidth = 100.0;
    final layout = SheetMusicLayout(
      metrics,
      Colors.black,
      widgetHeight: 100,
      widgetWidth: widgetWidth,
    );

    // Act
    final canvasScale = layout.canvasScale;

    // Assert
    expect(canvasScale, maximumStaffWidth / widgetWidth);
  });

  group('justification', () {
    SheetMusicLayout layoutOf({
      bool distributeSymbolsToFullWidth = false,
      bool justifyLines = true,
      bool spreadOnlyNotes = false,
      bool alignLeft = true,
    }) =>
        SheetMusicLayout(
          MockSheetMusicMetrics(
            maximumStaffWidth: 40,
            maximumStaffObjectsWidth: 40,
            staffsHeightSum: 1,
          ),
          Colors.black,
          widgetHeight: 100,
          widgetWidth: 100,
          distributeSymbolsToFullWidth: distributeSymbolsToFullWidth,
          justifyLines: justifyLines,
          spreadOnlyNotes: spreadOnlyNotes,
          alignLeft: alignLeft,
          maxCanvasScale: 1,
        );

    final staff = _FakeStaffMetrics(objectsWidth: 40, symbolCount: 4);

    test('a line that is not the last is pulled out to the full width', () {
      final layout = layoutOf();
      expect(layout.canvasScale, 1);
      expect(layout.stretchFor(staff, isLast: false), closeTo(100 / 40, 1e-9));
    });

    test('a centred page pulls a line out to its widest line, no further',
        () {
      // Drawn at a capped size, the page is 40 wide in a 100 wide widget and
      // starts 30 in. Pulled out to 100 from there, a line ran off the right.
      final layout = layoutOf(alignLeft: false);
      expect(layout.stretchFor(staff, isLast: false), 1);
      final narrow = _FakeStaffMetrics(objectsWidth: 20, symbolCount: 4);
      expect(layout.stretchFor(narrow, isLast: false), closeTo(2, 1e-9));
    });

    test('the last line keeps its natural width', () {
      expect(layoutOf().stretchFor(staff, isLast: true), 1);
    });

    test('distributing to full width justifies the last line too', () {
      final layout = layoutOf(distributeSymbolsToFullWidth: true);
      expect(layout.stretchFor(staff, isLast: true), closeTo(100 / 40, 1e-9));
    });

    test('justification can be turned off', () {
      expect(layoutOf(justifyLines: false).stretchFor(staff, isLast: false), 1);
    });

    test('a line is never pulled out past the cap', () {
      final wide = _FakeStaffMetrics(objectsWidth: 4, symbolCount: 2);
      expect(layoutOf().stretchFor(wide, isLast: false), 2.5);
    });

    test('a line holding one symbol is left alone', () {
      final lonely = _FakeStaffMetrics(objectsWidth: 10, symbolCount: 1);
      expect(layoutOf().stretchFor(lonely, isLast: false), 1);
    });

    test('signatures and barlines can keep their width while notes spread', () {
      // 20 of the 60 are a clef, a key signature and a barline
      final signed =
          _FakeStaffMetrics(objectsWidth: 60, symbolCount: 6, fixedWidth: 20);
      expect(
        layoutOf(spreadOnlyNotes: true).stretchFor(signed, isLast: false),
        closeTo((100 - 20) / 40, 1e-9),
      );
      expect(
        layoutOf().stretchFor(signed, isLast: false),
        closeTo(100 / 60, 1e-9),
      );
    });

    test('a line already wider than the page is not squeezed', () {
      final full = _FakeStaffMetrics(objectsWidth: 400, symbolCount: 8);
      expect(layoutOf().stretchFor(full, isLast: false), 1);
    });
  });

  group('squeezing', () {
    // 20 of a line's width are its clef and barlines; the notes claim the
    // rest. The page is 100 wide and drawn at most at scale 1.
    SheetMusicLayout layoutOf(double objectsWidth, {double minStretch = 0.7}) {
      final staff = _FakeStaffMetrics(
        objectsWidth: objectsWidth,
        symbolCount: 8,
        fixedWidth: 20,
      );
      return SheetMusicLayout(
        MockSheetMusicMetrics(
          maximumStaffWidth: objectsWidth,
          maximumStaffObjectsWidth: objectsWidth,
          staffsHeightSum: 1,
          staffsMetricses: [staff],
        ),
        Colors.black,
        widgetHeight: 100,
        widgetWidth: 100,
        distributeSymbolsToFullWidth: true,
        spreadOnlyNotes: true,
        maxCanvasScale: 1,
        minStretch: minStretch,
      );
    }

    test('a busy line keeps its size and pulls its notes together', () {
      // Notes claim 100; 80 is left for them.
      final layout = layoutOf(120);
      expect(layout.canvasScale, 1);
      final staff = layout.metrics.staffsMetricses.single;
      expect(layout.stretchFor(staff, isLast: true), closeTo(0.8, 1e-9));
    });

    test('past the squeeze allowed, the page is drawn smaller', () {
      // Squeezed to 0.7 the line is 20 + 200 * 0.7 = 160 wide.
      final layout = layoutOf(220);
      expect(layout.canvasScale, closeTo(100 / 160, 1e-9));
      final staff = layout.metrics.staffsMetricses.single;
      expect(layout.stretchFor(staff, isLast: true), closeTo(0.7, 1e-9));
    });

    test('without a squeeze a busy line makes the page smaller', () {
      final layout = layoutOf(120, minStretch: 1);
      expect(layout.canvasScale, closeTo(100 / 120, 1e-9));
      final staff = layout.metrics.staffsMetricses.single;
      expect(layout.stretchFor(staff, isLast: true), 1);
    });
  });
}

class _FakeStaffMetrics extends Fake implements StaffMetrics {
  _FakeStaffMetrics({
    required this.objectsWidth,
    required this.symbolCount,
    this.fixedWidth = 0,
  });

  @override
  final double objectsWidth;

  @override
  final int symbolCount;

  @override
  final double fixedWidth;

  @override
  double get horizontalMarginSum => 0;
}
