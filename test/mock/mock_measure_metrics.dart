import 'package:flutter_test/flutter_test.dart';
import 'package:simple_sheet_music/src/measure/measure_marks.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';

class MockMeasureMetrics extends Fake implements MeasureMetrics {
  MockMeasureMetrics({
    this.upperHeight = 0.0,
    this.lowerHeight = 0.0,
    this.objectsWidth = 0.0,
    this.horizontalMarginSum = 0.0,
  });

  @override
  final double upperHeight;
  @override
  final double lowerHeight;
  @override
  final double objectsWidth;
  @override
  final double horizontalMarginSum;

  @override
  List<MusicalSymbolMetrics> get musicalSymbolsMetricses => const [];

  @override
  List<MeasureMark> get marks => const [];

  @override
  Volta? get volta => null;
}
