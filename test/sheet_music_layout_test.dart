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

  test('distributed spacing fills the width without changing glyph scale', () {
    final metrics = MockSheetMusicMetrics(
      maximumStaffWidth: 40,
      maximumStaffObjectsWidth: 40,
      staffsHeightSum: 1,
    );
    final layout = SheetMusicLayout(
      metrics,
      Colors.black,
      widgetHeight: 100,
      widgetWidth: 100,
      distributeSymbolsToFullWidth: true,
      contentHorizontalPadding: 5,
      maxCanvasScale: 1,
    );
    final staff = _FakeStaffMetrics(
      objectsWidth: 40,
      symbolCount: 4,
    );

    expect(layout.canvasScale, 1);
    expect(
      layout.distributedSymbolSpacingOnCanvasFor(staff),
      closeTo(50 / 3, 0.0001),
    );
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
