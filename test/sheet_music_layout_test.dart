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
          maxCanvasScale: 1,
        );

    final staff = _FakeStaffMetrics(objectsWidth: 40, symbolCount: 4);

    test('a line that is not the last is pulled out to the full width', () {
      final layout = layoutOf();
      expect(layout.canvasScale, 1);
      expect(layout.stretchFor(staff, isLast: false), closeTo(100 / 40, 1e-9));
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

    test('a line already wider than the page is not squeezed', () {
      final full = _FakeStaffMetrics(objectsWidth: 400, symbolCount: 8);
      expect(layoutOf().stretchFor(full, isLast: false), 1);
    });
  });
}

class _FakeStaffMetrics extends Fake implements StaffMetrics {
  _FakeStaffMetrics({required this.objectsWidth, required this.symbolCount});

  @override
  final double objectsWidth;

  @override
  final int symbolCount;

  @override
  double get horizontalMarginSum => 0;
}
