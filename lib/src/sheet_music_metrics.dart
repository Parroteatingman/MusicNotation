import 'package:simple_sheet_music/src/extension/list_extension.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';

import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/musical_context.dart';
import 'package:simple_sheet_music/src/staff/staff_metrics.dart';

/// Represents the metrics of a sheet music.
class SheetMusicMetrics {
  SheetMusicMetrics(
    this.measures,
    this.initialClefType,
    this.initialKeySignatureType,
    this.metadata,
    this.paths, {
    SpacingReference? spacing,
  }) : _spacingOverride = spacing;

  /// The reference to space against instead of this page's own shortest
  /// note: a line measured on its own for a page that holds more.
  final SpacingReference? _spacingOverride;

  /// What every symbol on the page is spaced against.
  SpacingReference get spacing {
    _measuresMetricses;
    return _spacing!;
  }

  SpacingReference? _spacing;

  List<MeasureMetrics>? _measuresMetricsesCache;

  /// Gets the metrics of each measure in the sheet music.
  List<MeasureMetrics> get _measuresMetricses {
    if (_measuresMetricsesCache != null) {
      return _measuresMetricsesCache!;
    }
    final symbolsPerMeasure = <List<MusicalSymbolMetrics>>[];
    var context = MusicalContext(initialClefType, initialKeySignatureType);
    for (final measure in measures) {
      symbolsPerMeasure.add(measure.setContext(context, metadata, paths));
      context = measure.updateContext(context);
    }

    // Every staff on the page is spaced against the same shortest note, so
    // note heads keep one size from the first line to the last.
    final spacing = _spacing = _spacingOverride ??
        SpacingReference.of(symbolsPerMeasure.expand((symbols) => symbols));

    final result = <MeasureMetrics>[
      for (var index = 0; index < measures.length; index++)
        MeasureMetrics(
          symbolsPerMeasure[index],
          metadata,
          isNewLine: measures[index].isNewLine,
          spacing: spacing,
          endBarline: measures[index].endBarline,
        ),
    ];

    return _measuresMetricsesCache ??= result;
  }

  List<StaffMetrics>? _staffsMetricses;

  /// Gets the metrics of each staff in the sheet music.
  List<StaffMetrics> get staffsMetricses {
    if (_staffsMetricses != null) {
      return _staffsMetricses!;
    }
    final staffs = <StaffMetrics>[];
    var sameStaffMeasures = <MeasureMetrics>[];
    for (final measure in _measuresMetricses) {
      if (measure.isNewLine && sameStaffMeasures.isNotEmpty) {
        staffs.add(StaffMetrics(sameStaffMeasures));
        sameStaffMeasures = [measure];
      } else {
        sameStaffMeasures.add(measure);
      }
    }
    if (sameStaffMeasures.isNotEmpty) {
      staffs.add(StaffMetrics(sameStaffMeasures));
    }
    return _staffsMetricses ??= staffs;
  }

  final List<Measure> measures;
  final ClefType initialClefType;
  final KeySignatureType initialKeySignatureType;
  final GlyphMetadata metadata;
  final GlyphPaths paths;

  /// Gets the staff with the maximum width in the sheet music.
  StaffMetrics get _maximumWidthStaff {
    if (staffsMetricses.isEmpty) {
      throw StateError(
          'No staffs to compute metrics from (empty measures list)');
    }
    var result = staffsMetricses.first;
    for (final staff in staffsMetricses) {
      if (staff.width > result.width) {
        result = staff;
      }
    }
    return result;
  }

  /// Gets the maximum width of a staff in the sheet music.
  double get maximumStaffWidth => _maximumWidthStaff.width;

  /// Gets the unscaled glyph width of the widest staff, excluding margins.
  double get maximumStaffObjectsWidth =>
      staffsMetricses.map((staff) => staff.objectsWidth).max;

  double get maximumStaffHorizontalMarginSum =>
      _maximumWidthStaff.horizontalMarginSum;

  /// Gets the upper height of all the staffs in the sheet music.
  double get staffUpperHeight =>
      staffsMetricses.map((staff) => staff.upperHeight).max;

  /// Gets the lower height of all the staffs in the sheet music.
  double get staffLowerHeight =>
      staffsMetricses.map((staff) => staff.lowerHeight).max;

  /// Gets the sum of the heights of all the staffs in the sheet music.
  double get staffsHeightSum =>
      staffsMetricses.map((staff) => staff.height).sum;
}
