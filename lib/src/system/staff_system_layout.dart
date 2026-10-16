import 'dart:math';

import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/layout/note_spacing.dart';
import 'package:simple_sheet_music/src/measure/barline.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/measure/measure_metrics.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_metrics.dart';
import 'package:simple_sheet_music/src/music_objects/interface/musical_symbol_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/key_signature.dart';
import 'package:simple_sheet_music/src/music_objects/notes/chord_note/chord_note.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';
import 'package:simple_sheet_music/src/music_objects/time_signature/time_signature.dart';
import 'package:simple_sheet_music/src/sheet_music_layout.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/sheet_symbol_box.dart';
import 'package:simple_sheet_music/src/staff/staff_metrics.dart';
import 'package:simple_sheet_music/src/staff/staff_renderer.dart';
import 'package:simple_sheet_music/src/system/sheet_staff.dart';

/// A colour for the note, chord or rest [index] (counted among the notes,
/// rests and chords of its staff) on [staff], or null for its own.
typedef SheetSymbolColor = Color? Function(int staff, int index);

/// Several staffs set as one system: one line of music read top to bottom
/// at once — a piano's two hands, or every part of a score.
///
/// Every staff has the same measures, and within a measure whatever starts
/// at the same moment on any staff stands at the same place across the
/// line. The moments every staff starts something are pooled, and each gap
/// between one and the next is given the room the spacing model gives a
/// note that long ([SpacingReference], measured against the shortest value
/// in the system); then every staff's notes are fitted around them, each
/// note keeping at least the room it would have on a staff of its own. A
/// single staff set this way lands where [SheetMusicLayout] puts it.
///
/// Everything is in canvas units (a staff space is 250) at [canvasScale];
/// widths and paddings handed in are in points.
class StaffSystemLayout {
  StaffSystemLayout({
    required List<SheetStaff> staffs,
    required this.metadata,
    required this.paths,
    required this.canvasScale,
    required this.width,
    this.height,
    this.groups = const [],
    this.labelStaff = 0,
    this.lineColor = Colors.black54,
    Color? inkColor,
    this.horizontalPadding = 0,
    this.verticalPadding = 0,
    this.justify = true,
    this.extendStaffToFullWidth = true,
    this.showBarlines = true,
    this.showEndBarline = false,
    this.showFinalBarline = false,
    this.grandStaffGap = 5.0,
    this.partGap = 6.0,
    this.clearance = 0.8,
  })  : inkColor = inkColor ?? lineColor,
        _sources = staffs {
    if (staffs.isEmpty) {
      throw ArgumentError.value(staffs, 'staffs', 'A system needs a staff');
    }
    final count = staffs.first.measures.length;
    if (count == 0 || staffs.any((staff) => staff.measures.length != count)) {
      throw ArgumentError.value(
        [for (final staff in staffs) staff.measures.length],
        'staffs',
        'Every staff of a system holds the same measures',
      );
    }
  }

  final List<SheetStaff> _sources;
  final GlyphMetadata metadata;
  final GlyphPaths paths;

  /// Font units to points: a staff space is 250 font units.
  final double canvasScale;

  /// The width the system is drawn in, in points.
  final double width;

  /// The height it is drawn in, in points; the staffs are centred in it.
  /// Null: as high as the staffs need.
  final double? height;

  final List<StaffGroup> groups;

  /// The staff that carries the chord names, and the marks and endings over
  /// them; the other staffs draw none. Null: no staff does.
  final int? labelStaff;

  /// Staff lines and barlines.
  final Color lineColor;

  /// Braces, brackets and the system's opening line.
  final Color inkColor;

  /// Room left of the system's first sign and right of its end, in points.
  final double horizontalPadding;

  /// Room over the first staff's notes and under the last's, in points.
  final double verticalPadding;

  /// Pull the notes apart (never more than 2.5 times their room) so the
  /// system fills [width]. A system too long for [width] is pulled together
  /// either way, first the room beyond each glyph, then part of the
  /// margins.
  final bool justify;

  /// Draw the staff lines on to the right edge even when the notes end
  /// sooner.
  final bool extendStaffToFullWidth;

  final bool showBarlines;
  final bool showEndBarline;
  final bool showFinalBarline;

  /// The gap between two staffs of a group (a piano's), in staff spaces
  /// from one's bottom line to the next one's top line, before the notes
  /// between them ask for more.
  final double grandStaffGap;

  /// The gap between two staffs of different parts, in staff spaces.
  final double partGap;

  /// Room kept, in staff spaces, between the lowest ink of one staff and
  /// the highest of the next.
  final double clearance;

  static const double _space = Constants.staffSpace;

  /// A line is never pulled out further than this (as on a single staff).
  static const double maxStretch = 2.5;

  /// How much of their margins symbols may lose when a system too long for
  /// its width is pulled together (as on a single staff).
  static const double minMarginScale = SheetMusicLayout.minMarginScale;

  int get staffCount => _sources.length;
  int get measureCount => _sources.first.measures.length;

  // ---------------------------------------------------------------------
  // The staffs as metrics.

  late final List<_Staff> _staffs = _buildStaffs();

  List<_Staff> _buildStaffs() {
    List<Measure> prepared(int index) {
      final carries = labelStaff == index;
      return [
        for (final measure in _sources[index].measures)
          carries ? measure.withNewLine(false) : _withoutLabels(measure),
      ];
    }

    // Spaced first on their own, to find the shortest value of the system.
    final own = [
      for (var i = 0; i < staffCount; i++)
        SheetMusicMetrics(
          prepared(i),
          _sources[i].clef,
          _sources[i].keySignature,
          metadata,
          paths,
        ),
    ];
    var units = double.infinity;
    for (final sheet in own) {
      final reference = sheet.spacing;
      if (reference.units > 0 && reference.units < units) {
        units = reference.units;
      }
    }
    var natural = 0.0;
    for (final sheet in own) {
      final reference = sheet.spacing;
      if (reference.units == units && reference.naturalWidth > natural) {
        natural = reference.naturalWidth;
      }
    }
    final spacing = units.isFinite
        ? SpacingReference(units: units, naturalWidth: natural)
        : SpacingReference.none;
    return [
      for (var i = 0; i < staffCount; i++)
        _Staff(
          i,
          SheetMusicMetrics(
            own[i].measures,
            _sources[i].clef,
            _sources[i].keySignature,
            metadata,
            paths,
            spacing: spacing,
          ),
        ),
    ];
  }

  /// [measure] with no chord names, marks or endings: a staff that isn't
  /// [labelStaff] draws none.
  static Measure _withoutLabels(Measure measure) {
    MusicalSymbol strip(MusicalSymbol symbol) {
      if (symbol is Note) {
        final label = symbol.chordLabel;
        return label == null || label.isEmpty
            ? symbol
            : symbol.withoutChordLabel();
      }
      if (symbol is Rest) {
        final label = symbol.chordLabel;
        return label == null || label.isEmpty
            ? symbol
            : symbol.withoutChordLabel();
      }
      return symbol;
    }

    return Measure(
      [for (final symbol in measure.musicalSymbols) strip(symbol)],
      startRepeat: measure.startRepeat,
      endBarline: measure.endBarline,
    );
  }

  /// What every symbol is spaced against.
  SpacingReference get spacing => _staffs.first.measures.first.spacing;

  // ---------------------------------------------------------------------
  // Across the line.

  /// The symbols of the system, set at their natural room: what the system
  /// needs (see [naturalWidth]).
  late final _Placement _natural = _place(contentStart: _contentStart);

  /// Where the system's first measure starts (its opening line), in canvas
  /// units: the padding, and the room a brace or bracket takes.
  late final double _contentStart =
      horizontalPadding / canvasScale + _decorationWidth;

  /// The width the system needs with nothing squeezed, in points.
  double get naturalWidth =>
      _natural.end * canvasScale + horizontalPadding;

  /// The placement the system is drawn with: pulled out to [width], or
  /// pulled together into it.
  late final _Placement _placement = _fit();

  _Placement _fit() {
    if (staffCount == 1) return _fitSingle();
    final target = (width - horizontalPadding) / canvasScale;
    final natural = _natural;
    if (natural.end > target + 1e-6) {
      final tight = _place(contentStart: _contentStart, squeeze: 0);
      if (tight.end <= target) {
        final q = _solve(
          (q) => _place(contentStart: _contentStart, squeeze: q),
          target,
          lo: 0,
          hi: 1,
          atLo: tight,
          atHi: natural,
        );
        return q;
      }
      final cut = _place(
        contentStart: _contentStart,
        squeeze: 0,
        marginScale: minMarginScale,
      );
      if (cut.end >= target) return cut;
      return _solve(
        (m) => _place(contentStart: _contentStart, squeeze: 0, marginScale: m),
        target,
        lo: minMarginScale,
        hi: 1,
        atLo: cut,
        atHi: tight,
      );
    }
    if (!justify || _symbolCount < 2) return natural;
    final widest =
        _place(contentStart: _contentStart, stretch: maxStretch);
    if (widest.end <= target) return widest;
    return _solve(
      (s) => _place(contentStart: _contentStart, stretch: s),
      target,
      lo: 1,
      hi: maxStretch,
      atLo: natural,
      atHi: widest,
    );
  }

  /// A system of one staff is fitted to the width as [SheetMusicLayout]
  /// fits a line drawn at a fixed size, by the same sums in the same order,
  /// so that it lands on the same pixels.
  _Placement _fitSingle() {
    final staff = _staffs.first.staffMetrics;
    final scale = canvasScale;
    final padding = horizontalPadding / scale * scale;
    final fixed = staff.fixedWidth;
    final room = (width - padding * 2) / scale - fixed;
    final margins = staff.horizontalMarginSum / scale;
    final claimed = staff.objectsWidth - fixed;
    if (claimed + margins > room + 1e-6) {
      final glyphs = staff.glyphWidth - fixed;
      final spare = claimed - glyphs;
      if (spare > 0 && glyphs + margins <= room) {
        return _place(
          contentStart: _contentStart,
          squeeze: (room - margins - glyphs) / spare,
        );
      }
      final marginScale = margins <= 0
          ? 1.0
          : ((room - glyphs) / margins).clamp(minMarginScale, 1.0);
      return _place(
        contentStart: _contentStart,
        squeeze: 0,
        marginScale: marginScale,
      );
    }
    if (!justify || staff.symbolCount < 2) return _natural;
    final content = staff.objectsWidth - fixed;
    if (content <= 0) return _natural;
    final available =
        (width - padding * 2 - staff.horizontalMarginSum) / scale - fixed;
    if (available <= content) return _natural;
    return _place(
      contentStart: _contentStart,
      stretch: min(maxStretch, available / content),
    );
  }

  /// One staff placed symbol after symbol, as [MeasureMetrics] places a
  /// line's: each symbol's room and margins added to the last.
  _Placement _placeSingle({
    required double contentStart,
    required double stretch,
    required double squeeze,
    required double marginScale,
  }) {
    final scale = canvasScale;
    final measureXs = <double>[contentStart];
    final xs = <List<double>>[];
    var currentX = contentStart;
    for (final measure in _staffs.first.measures) {
      var x = currentX;
      final at = <double>[];
      var advances = 0.0;
      for (final symbol in measure.musicalSymbolsMetricses) {
        final cutLeft = symbol.margin.left * (1 - marginScale) / scale;
        at.add(x - cutLeft);
        final advance = measure.advanceIn(
          symbol,
          spreadOnlyNotes: true,
          stretch: stretch,
          squeeze: squeeze,
        );
        advances += advance;
        x += advance + symbol.margin.horizontal * marginScale / scale;
      }
      xs.add(at);
      currentX += advances + measure.horizontalMarginSum * marginScale / scale;
      measureXs.add(currentX);
    }
    return _Placement(
      measureXs,
      [xs],
      stretch: stretch,
      squeeze: squeeze,
      marginScale: marginScale,
    );
  }

  int get _symbolCount => _staffs
      .map((staff) => staff.measures
          .fold<int>(0, (sum, m) => sum + m.musicalSymbolsMetricses.length))
      .reduce(max);

  /// The placement whose end is [target], between [lo] and [hi] of the
  /// parameter [place] takes. A placement's end grows with the parameter
  /// in straight pieces (exactly straight on a single staff), so false
  /// position finds it in a step or a few.
  _Placement _solve(
    _Placement Function(double) place,
    double target, {
    required double lo,
    required double hi,
    required _Placement atLo,
    required _Placement atHi,
  }) {
    var a = lo;
    var b = hi;
    var fa = atLo.end - target;
    var fb = atHi.end - target;
    var best = fa.abs() < fb.abs() ? atLo : atHi;
    var side = 0;
    for (var i = 0; i < 40; i++) {
      if (fb == fa) break;
      final x = (a * fb - b * fa) / (fb - fa);
      final at = place(x);
      final fx = at.end - target;
      if (fx.abs() < (best.end - target).abs()) best = at;
      if (fx.abs() < 1e-6) return at;
      if ((fx < 0) == (fa < 0)) {
        a = x;
        fa = fx;
        if (side == -1) fb /= 2;
        side = -1;
      } else {
        b = x;
        fb = fx;
        if (side == 1) fa /= 2;
        side = 1;
      }
    }
    return best;
  }

  /// Every symbol of the system placed across the line, the first measure
  /// starting at [contentStart]. [stretch], [squeeze] and [marginScale]
  /// are what a single staff's line is set with (see
  /// [MeasureMetrics.advanceIn]); clefs, key and time signatures are never
  /// pulled apart.
  _Placement _place({
    required double contentStart,
    double stretch = 1,
    double squeeze = 1,
    double marginScale = 1,
  }) {
    if (staffCount == 1) {
      return _placeSingle(
        contentStart: contentStart,
        stretch: stretch,
        squeeze: squeeze,
        marginScale: marginScale,
      );
    }
    final scale = canvasScale;
    final measureXs = <double>[contentStart];
    final xs = [
      for (var s = 0; s < staffCount; s++) <List<double>>[],
    ];
    var x0 = contentStart;
    for (var m = 0; m < measureCount; m++) {
      final columns = <_Column>[
        for (var s = 0; s < staffCount; s++)
          _Column.of(_staffs[s].measures[m]),
      ];
      MeasureMetrics metricsOf(int s) => _staffs[s].measures[m];
      double advance(int s, MusicalSymbolMetrics symbol) =>
          metricsOf(s).advanceIn(
            symbol,
            spreadOnlyNotes: true,
            stretch: stretch,
            squeeze: squeeze,
          );
      double left(MusicalSymbolMetrics symbol) =>
          symbol.margin.left * marginScale / scale;
      double right(MusicalSymbolMetrics symbol) =>
          symbol.margin.right * marginScale / scale;
      double whole(int s, MusicalSymbolMetrics symbol) =>
          advance(s, symbol) + symbol.margin.horizontal * marginScale / scale;

      // What opens the measure — clef, key, time signature, ‖: — set in
      // columns of their own when every staff opens with the same kinds,
      // so the key signatures line up; one after another otherwise.
      final slots = <int, List<double>>{};
      double prefixEnd;
      final kinds = [
        for (var s = 0; s < staffCount; s++)
          [
            for (var k = 0; k < columns[s].prefix; k++)
              _kindOf(metricsOf(s).musicalSymbolsMetricses[k]),
          ],
      ];
      final aligned = kinds.every((k) => _sameKinds(k, kinds.first));
      if (aligned) {
        final widths = List<double>.filled(kinds.first.length, 0);
        for (var s = 0; s < staffCount; s++) {
          final symbols = metricsOf(s).musicalSymbolsMetricses;
          for (var k = 0; k < columns[s].prefix; k++) {
            widths[k] = max(widths[k], whole(s, symbols[k]));
          }
        }
        for (var s = 0; s < staffCount; s++) {
          var x = x0;
          final at = <double>[];
          for (var k = 0; k < columns[s].prefix; k++) {
            at.add(x);
            x += widths[k];
          }
          slots[s] = at;
        }
        var end = x0;
        for (final w in widths) {
          end += w;
        }
        prefixEnd = end;
      } else {
        prefixEnd = x0;
        for (var s = 0; s < staffCount; s++) {
          final symbols = metricsOf(s).musicalSymbolsMetricses;
          var x = x0;
          final at = <double>[];
          for (var k = 0; k < columns[s].prefix; k++) {
            at.add(x);
            x += whole(s, symbols[k]);
          }
          slots[s] = at;
          prefixEnd = max(prefixEnd, x);
        }
      }

      // The moments anything starts, on any staff.
      final onsetKeys = <int>{};
      var end = 0.0;
      for (final c in columns) {
        for (final item in c.items) {
          onsetKeys.add(_key(item.onset));
        }
        end = max(end, c.total);
      }
      final onsets = onsetKeys.toList()..sort();
      final columnOf = {
        for (var i = 0; i < onsets.length; i++) onsets[i]: i + 1,
      };
      final endColumn = onsets.length + 1;
      final times = [for (final k in onsets) k / _keyScale, end];

      // Gaps between neighbouring columns (0: the opening to the first
      // moment; the last: the last moment to the measure's end), and what
      // each staff needs from one of its notes to the next.
      final gaps = List<double>.filled(endColumn, -1);
      final spans = <_Span>[];
      void need(int from, int to, double room) {
        if (to == from + 1) {
          if (room > gaps[from]) gaps[from] = room;
        } else {
          spans.add(_Span(from, to, room));
        }
      }

      for (var s = 0; s < staffCount; s++) {
        final c = columns[s];
        final symbols = metricsOf(s).musicalSymbolsMetricses;
        for (var k = 0; k < c.items.length; k++) {
          final item = c.items[k];
          final symbol = symbols[item.index];
          final from = columnOf[_key(item.onset)]!;
          var room = advance(s, symbol) - symbol.leadingWidth + right(symbol);
          for (final a in item.attached) {
            room += whole(s, symbols[a]);
          }
          if (k == 0) {
            need(0, from, left(symbol) + symbol.leadingWidth);
          }
          if (k + 1 < c.items.length) {
            final next = symbols[c.items[k + 1].index];
            final to = columnOf[_key(c.items[k + 1].onset)]!;
            need(from, to, room + left(next) + next.leadingWidth);
          } else {
            need(from, endColumn, room);
          }
        }
      }
      // A gap no staff speaks for (every staff holding a longer note over
      // it) gets the room its stretch of time asks for.
      for (var i = 0; i < gaps.length; i++) {
        if (gaps[i] >= 0) continue;
        if (i == 0) {
          gaps[i] = 0;
          continue;
        }
        final floor = max(
          spacing.spaceFor(times[i] - times[i - 1]),
          _space * 0.5,
        );
        gaps[i] = floor * stretch;
      }
      // A note held over several moments keeps its own room: what the
      // moments between leave short is shared among them.
      spans.sort((a, b) => (a.to - a.from).compareTo(b.to - b.from));
      for (final span in spans) {
        var sum = 0.0;
        for (var i = span.from; i < span.to; i++) {
          sum += gaps[i];
        }
        if (span.room <= sum + 1e-9) continue;
        final excess = span.room - sum;
        final count = span.to - span.from;
        for (var i = span.from; i < span.to; i++) {
          gaps[i] += sum > 0 ? excess * gaps[i] / sum : excess / count;
        }
      }
      final anchors = List<double>.filled(endColumn + 1, prefixEnd);
      for (var i = 0; i < endColumn; i++) {
        anchors[i + 1] = anchors[i] + gaps[i];
      }

      // Every symbol where the renderer wants it: the x it is handed, with
      // what a cut margin took off its left (see MeasureMetrics).
      for (var s = 0; s < staffCount; s++) {
        final c = columns[s];
        final symbols = metricsOf(s).musicalSymbolsMetricses;
        final at = List<double>.filled(symbols.length, x0);
        final opening = slots[s]!;
        for (var k = 0; k < opening.length; k++) {
          at[k] = opening[k];
        }
        for (final item in c.items) {
          final symbol = symbols[item.index];
          final head = anchors[columnOf[_key(item.onset)]!];
          var x = head - left(symbol) - symbol.leadingWidth;
          at[item.index] = x;
          x += whole(s, symbol);
          for (final a in item.attached) {
            at[a] = x;
            x += whole(s, symbols[a]);
          }
        }
        for (var k = 0; k < symbols.length; k++) {
          at[k] -= symbols[k].margin.left * (1 - marginScale) / scale;
        }
        xs[s].add(at);
      }
      x0 = anchors[endColumn];
      measureXs.add(x0);
    }
    return _Placement(
      measureXs,
      xs,
      stretch: stretch,
      squeeze: squeeze,
      marginScale: marginScale,
    );
  }

  static bool _sameKinds(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Moments, in quarter notes, as whole numbers, so that the same moment
  /// reached by different sums is the same moment (a triplet's thirds).
  static const double _keyScale = 1e6;
  static int _key(double units) => (units * _keyScale).round();

  // ---------------------------------------------------------------------
  // Down the page.

  /// Where each staff's middle line is, in canvas units.
  late final List<double> staffCenters = _stack();

  /// How far each staff's ink reaches above and below its middle line.
  late final List<double> _uppers;
  late final List<double> _lowers;

  /// The height the staffs take, padding included, in canvas units.
  late final double _contentHeight;

  List<double> _stack() {
    final uppers = <double>[];
    final lowers = <double>[];
    // The ink is read off the notes set at their natural room: beams and
    // tuplet brackets reach where the notes stand, and a system drawn wider
    // moves them by no more than the clearance.
    final natural = _place(contentStart: 0);
    for (var s = 0; s < staffCount; s++) {
      final staff = _staffs[s];
      var upper = staff.staffMetrics.upperHeight;
      var lower = staff.staffMetrics.lowerHeight;
      final measures = _measureRenderers(s, natural, 0);
      var top = 0.0;
      var bottom = 0.0;
      for (final measure in measures) {
        for (final y in measure.symbolInkTops()) {
          if (y.isFinite && y < top) top = y;
        }
        for (final y in measure.symbolInkBottoms()) {
          if (y.isFinite && y > bottom) bottom = y;
        }
      }
      // Only a side that faces another staff reads the ink: the outside of
      // the system is held as a single staff holds it.
      if (s > 0) upper = max(upper, -top);
      if (s < staffCount - 1) lower = max(lower, bottom);
      uppers.add(upper);
      lowers.add(lower);
    }
    // A bracket's hooks reach over the first staff and under the last.
    final hook = _space * 1.3;
    for (final group in groups) {
      if (group.kind != StaffGroupKind.bracket) continue;
      uppers[group.first] = max(uppers[group.first], _space * 2 + hook);
      lowers[group.last] = max(lowers[group.last], _space * 2 + hook);
    }
    _uppers = uppers;
    _lowers = lowers;

    final pad = verticalPadding / canvasScale;
    final centers = <double>[pad + uppers.first];
    for (var s = 1; s < staffCount; s++) {
      final together = groups.any((g) =>
          g.kind != StaffGroupKind.bracket && g.contains(s - 1) && g.contains(s));
      final gap = (together ? grandStaffGap : partGap) * _space;
      final apart = max(
        _space * 4 + gap,
        lowers[s - 1] + uppers[s] + clearance * _space,
      );
      centers.add(centers.last + apart);
    }
    _contentHeight = centers.last + lowers.last + pad;
    final given = height;
    if (given != null && staffCount == 1 && verticalPadding == 0) {
      // Centred as a single staff is, by the same sums.
      final staff = _staffs.first.staffMetrics;
      final padding = (given - staff.height * canvasScale) / canvasScale / 2;
      return [padding + staff.upperHeight];
    }
    if (given != null) {
      final room = given / canvasScale;
      final shift = (room - _contentHeight) / 2;
      if (shift > 0) {
        for (var s = 0; s < centers.length; s++) {
          centers[s] += shift;
        }
      }
    }
    return centers;
  }

  /// The height the system needs, in points.
  double get naturalHeight {
    // The heights are worked out with the staffs' places.
    if (staffCenters.isEmpty) return 0;
    return _contentHeight * canvasScale;
  }

  // ---------------------------------------------------------------------
  // Signs at the system's start.

  /// The room the braces and brackets take left of the opening line.
  late final double _decorationWidth = _measureDecorations();

  static const double _braceGap = _space * 0.25;
  static const double _bracketGap = _space * 0.4;
  static const double _bracketThickness = _space * 0.5;

  double _measureDecorations() {
    var width = 0.0;
    final brackets =
        groups.where((g) => g.kind == StaffGroupKind.bracket).toList();
    final braces = groups.where((g) => g.kind == StaffGroupKind.brace);
    if (brackets.isNotEmpty) {
      width += _bracketGap + _bracketHookWidth;
    }
    if (braces.isNotEmpty) {
      var widest = 0.0;
      for (final group in braces) {
        widest = max(widest, _braceSize(group).width);
      }
      width += _braceGap + widest;
    }
    return width;
  }

  double get _bracketHookWidth {
    final hook = paths.parsePath('uniE003').getBounds();
    return max(hook.width, _bracketThickness);
  }

  /// A brace's glyph is drawn one staff high; it is stretched to the
  /// group, and widened with it as an engraver's brace is.
  Size _braceSize(StaffGroup group) {
    final glyph = paths.parsePath('uniE000').getBounds();
    final tall = _groupHeight(group);
    final sy = tall / glyph.height;
    final wide = min(glyph.width * sy, _space * 1.1);
    return Size(wide, tall);
  }

  /// The distances between staff middles don't depend on the brace, so
  /// the brace can be sized before the line is placed.
  double _groupHeight(StaffGroup group) =>
      staffCenters[group.last] - staffCenters[group.first] + _space * 4;

  // ---------------------------------------------------------------------
  // Drawing.

  late final List<_StaffLayout> _layouts = [
    for (var s = 0; s < staffCount; s++)
      _StaffLayout(
        _staffs[s].sheet,
        lineColor,
        canvasScale,
        _staffs[s].staffMetrics.chordLift,
      ),
  ];

  List<MeasureRenderer> _measureRenderers(
    int s,
    _Placement at,
    double centerY,
  ) {
    final layout = _layouts[s];
    final measures = _staffs[s].measures;
    return [
      for (var m = 0; m < measures.length; m++)
        MeasureRenderer(
          [
            for (var k = 0; k < measures[m].musicalSymbolsMetricses.length; k++)
              measures[m].musicalSymbolsMetricses[k].renderer(
                    layout,
                    staffLineCenterY: centerY,
                    symbolX: at.xs[s][m][k],
                  ),
          ],
          measures[m],
          layout,
          measureOriginX: at.measureXs[m],
          staffLineCenterY: centerY,
          stretch: at.stretch,
          squeeze: at.squeeze,
          marginScale: at.marginScale,
          // A single staff's measures are as wide as their own symbols.
          widthOverride: staffCount == 1
              ? null
              : at.measureXs[m + 1] - at.measureXs[m],
        ),
    ];
  }

  /// The right edge the staff lines run to.
  double get _lineEnd => extendStaffToFullWidth
      ? max(_placement.end, width / canvasScale)
      : _placement.end;

  /// Every staff, ready to draw.
  late final List<StaffRenderer> staffRenderers = [
    for (var s = 0; s < staffCount; s++)
      StaffRenderer(
        _measureRenderers(s, _placement, staffCenters[s]),
        // A staff on its own draws its barlines itself, as a single staff
        // does; across a run of staffs they are drawn once, through all.
        showBarlines: showBarlines && _alone(s),
        showEndBarline: showEndBarline && !showFinalBarline,
        showFinalBarline: showFinalBarline,
        staffExtendWidth: extendStaffToFullWidth ? _lineEnd : null,
        staffLinesFrom: _contentStart,
        paths: s == labelStaff ? paths : null,
        chordLift: _staffs[s].staffMetrics.chordLift,
      ),
  ];

  /// Where the system's notes, rests and chords stand among their staff's:
  /// for each staff, measure and symbol, its place (or -1 for a clef, a
  /// key signature…).
  late final List<List<List<int>>> _orders = [
    for (final staff in staffRenderers) _ordersOf(staff),
  ];

  static List<List<int>> _ordersOf(StaffRenderer staff) {
    var order = 0;
    return [
      for (final measure in staff.measureRendereres)
        [
          for (final symbol in measure.symbolRenderers)
            _isCounted(symbol) ? order++ : -1,
        ],
    ];
  }

  static bool _isCounted(MusicalSymbolRenderer symbol) =>
      symbol is NoteRenderer ||
      symbol is ChordNoteRenderer ||
      symbol is RestRenderer;

  /// The runs of staffs a barline is drawn through, top to bottom.
  late final List<_Run> _barRuns = _buildRuns();

  List<_Run> _buildRuns() {
    final runs = <_Run>[];
    var s = 0;
    while (s < staffCount) {
      var last = s;
      for (final group in groups) {
        if (group.barlinesThrough && group.first == s) {
          last = max(last, min(group.last, staffCount - 1));
        }
      }
      runs.add(_Run(s, last));
      s = last + 1;
    }
    return runs;
  }

  /// Whether staff [s] has its barlines to itself.
  bool _alone(int s) => _barRuns.any((run) => run.first == s && run.last == s);

  double _top(int s) => staffCenters[s] - _space * 2;
  double _bottom(int s) => staffCenters[s] + _space * 2;

  /// Draws the system on [canvas], already scaled to [canvasScale].
  void render(Canvas canvas, Size size, {SheetSymbolColor? symbolColor}) {
    for (var s = 0; s < staffCount; s++) {
      final orders = _orders[s];
      staffRenderers[s].render(
        canvas,
        size,
        inkOf: symbolColor == null
            ? null
            : (m, k) {
                final order = orders[m][k];
                return order < 0 ? null : symbolColor(s, order);
              },
      );
    }
    _renderBarlines(canvas);
    _renderOpening(canvas);
  }

  double get _thickness => metadata.staffLineThickness;

  void _renderBarlines(Canvas canvas) {
    final painter = BarlinePainter(_thickness);
    final measures = [
      for (final staff in staffRenderers) staff.measureRendereres,
    ];
    for (var m = 0; m < measureCount - 1; m++) {
      final x = _placement.measureXs[m + 1];
      for (final run in _barRuns) {
        final first = run.first;
        final last = run.last;
        if (first == last) continue;
        final type = measures[first][m].measureMetrics.endBarline;
        final repeatNext = measures[first][m + 1].startsWithRepeat;
        if (type != null && type != BarlineType.single) {
          for (var s = first; s < last; s++) {
            painter.connect(canvas, lineColor, type, x, _bottom(s), _top(s + 1),
                shareThick: type == BarlineType.repeatEnd && repeatNext);
          }
          continue;
        }
        if (!showBarlines || repeatNext) continue;
        canvas.drawLine(
          Offset(x, _top(first)),
          Offset(x, _bottom(last)),
          Paint()
            ..color = lineColor
            ..strokeWidth = _thickness * 1.5,
        );
      }
    }
    // The system's end, through each run's gaps (each staff draws its own
    // part).
    final endX = extendStaffToFullWidth ? _lineEnd : _placement.end;
    for (final run in _barRuns) {
      final first = run.first;
      final last = run.last;
      if (first == last) continue;
      final type = measures[first].last.measureMetrics.endBarline;
      for (var s = first; s < last; s++) {
        final top = _bottom(s);
        final bottom = _top(s + 1);
        if (type != null) {
          painter.connect(canvas, lineColor, type, endX, top, bottom);
        } else if (showFinalBarline) {
          final paint = Paint()..color = lineColor;
          canvas.drawLine(
            Offset(endX - _thickness * 6, top),
            Offset(endX - _thickness * 6, bottom),
            paint..strokeWidth = _thickness * 1.5,
          );
          canvas.drawLine(
            Offset(endX - _thickness * 1.5, top),
            Offset(endX - _thickness * 1.5, bottom),
            Paint()
              ..color = lineColor
              ..strokeWidth = _thickness * 4,
          );
        } else if (showEndBarline) {
          final x = endX - _thickness * 0.75;
          canvas.drawLine(
            Offset(x, top),
            Offset(x, bottom),
            Paint()
              ..color = lineColor
              ..strokeWidth = _thickness * 1.5,
          );
        }
      }
    }
  }

  /// The opening line joining every staff, and the braces and brackets
  /// left of it.
  void _renderOpening(Canvas canvas) {
    if (staffCount < 2) return;
    final x = _contentStart;
    final thin = _thickness * 1.5;
    canvas.drawRect(
      Rect.fromLTRB(x, _top(0), x + thin, _bottom(staffCount - 1)),
      Paint()..color = inkColor,
    );
    final hasBracket = groups.any((g) => g.kind == StaffGroupKind.bracket);
    var braceRight = x - _braceGap;
    if (hasBracket) {
      final lineLeft = x - _bracketGap - _bracketThickness;
      braceRight = x - _bracketGap - _bracketHookWidth - _braceGap;
      for (final group in groups) {
        if (group.kind != StaffGroupKind.bracket) continue;
        _drawBracket(canvas, group, lineLeft);
      }
    }
    for (final group in groups) {
      if (group.kind != StaffGroupKind.brace) continue;
      _drawBrace(canvas, group, braceRight);
    }
  }

  void _drawBrace(Canvas canvas, StaffGroup group, double right) {
    final glyph = paths.parsePath('uniE000');
    final bounds = glyph.getBounds();
    final size = _braceSize(group);
    final sy = size.height / bounds.height;
    final sx = size.width / bounds.width;
    final top = _top(group.first);
    final matrix = Matrix4.diagonal3Values(sx, sy, 1)
      ..setTranslationRaw(
          right - size.width - bounds.left * sx, top - bounds.top * sy, 0);
    canvas.drawPath(
      glyph.transform(matrix.storage),
      Paint()..color = inkColor,
    );
  }

  void _drawBracket(Canvas canvas, StaffGroup group, double lineLeft) {
    final top = _top(group.first) - _space * 0.25;
    final bottom = _bottom(group.last) + _space * 0.25;
    final paint = Paint()..color = inkColor;
    canvas.drawRect(
      Rect.fromLTRB(lineLeft, top, lineLeft + _bracketThickness, bottom),
      paint,
    );
    // The hooks: SMuFL's bracket ends, their left edge on the line's.
    final upper = paths.parsePath('uniE003');
    final lower = paths.parsePath('uniE004');
    final ub = upper.getBounds();
    final lb = lower.getBounds();
    canvas.drawPath(
      upper.shift(Offset(lineLeft - ub.left, top - ub.bottom)),
      paint,
    );
    canvas.drawPath(
      lower.shift(Offset(lineLeft - lb.left, bottom - lb.top)),
      paint,
    );
  }

  // ---------------------------------------------------------------------
  // Where things are.

  /// Everything as drawn, in the widget's coordinates.
  SheetSystemGeometry geometry() {
    final scale = canvasScale;
    final toWidget = Matrix4.diagonal3Values(scale, scale, 1).storage;
    final boxes = <SheetSymbolBox>[];
    final staffBoxes = <SheetStaffBox>[];
    for (var s = 0; s < staffCount; s++) {
      final center = staffCenters[s];
      final staffTop = (center - _space * 2) * scale;
      final staffBottom = (center + _space * 2) * scale;
      staffBoxes.add(SheetStaffBox(
        staff: s,
        top: staffTop,
        bottom: staffBottom,
        inkTop: (center - max(_uppers[s], _space * 2)) * scale,
        inkBottom: (center + max(_lowers[s], _space * 2)) * scale,
      ));
      var order = 0;
      final measures = staffRenderers[s].measureRendereres;
      for (var m = 0; m < measures.length; m++) {
        final measure = measures[m];
        final inks = measure.symbolInkBottoms();
        final measureLeft = measure.measureOriginX * scale;
        final measureRight = (measure.measureOriginX + measure.width) * scale;
        for (var i = 0; i < measure.symbolRenderers.length; i++) {
          final symbol = measure.symbolRenderers[i];
          SheetSymbolKind kind;
          List<Path> heads;
          Rect? label;
          if (symbol is NoteRenderer) {
            kind = SheetSymbolKind.note;
            heads = [symbol.noteHeadRenderPath];
            label = symbol.chordLabelRect;
          } else if (symbol is ChordNoteRenderer) {
            kind = SheetSymbolKind.chord;
            heads = symbol.noteHeadRenderPaths;
          } else if (symbol is RestRenderer) {
            kind = SheetSymbolKind.rest;
            heads = [symbol.renderPath];
            label = symbol.chordLabelRect;
          } else {
            continue;
          }
          final drawn = [for (final head in heads) head.transform(toWidget)];
          var inkBottom = inks[i] * scale;
          for (final head in drawn) {
            final bottom = head.getBounds().bottom;
            if (bottom > inkBottom) inkBottom = bottom;
          }
          boxes.add(SheetSymbolBox(
            order: order++,
            line: 0,
            staff: s,
            kind: kind,
            heads: drawn,
            staffTop: staffTop,
            staffBottom: staffBottom,
            inkBottom: inkBottom,
            measure: m,
            measureLeft: measureLeft,
            measureRight: measureRight,
            chordLabel: label == null
                ? null
                : Rect.fromLTRB(label.left * scale, label.top * scale,
                    label.right * scale, label.bottom * scale),
          ));
        }
      }
    }
    final xs = _placement.measureXs;
    return SheetSystemGeometry(
      size: Size(width, height ?? naturalHeight),
      contentLeft: _contentStart * scale,
      staffs: staffBoxes,
      measureLefts: [for (var m = 0; m < measureCount; m++) xs[m] * scale],
      measureRights: [
        for (var m = 0; m < measureCount; m++)
          (m == measureCount - 1 && extendStaffToFullWidth
                  ? _lineEnd
                  : xs[m + 1]) *
              scale,
      ],
      symbols: boxes,
    );
  }
}

/// A staff of the system as metrics.
class _Staff {
  _Staff(this.index, this.sheet);

  final int index;
  final SheetMusicMetrics sheet;

  /// One line: the staff's measures, spaced against the whole system.
  late final StaffMetrics staffMetrics = sheet.staffsMetricses.single;

  List<MeasureMetrics> get measures => staffMetrics.measuresMetricses;
}

/// What a staff's symbols ask of the layout they are drawn in: the size the
/// system is drawn at, and how high the staff's chord names are raised.
class _StaffLayout extends SheetMusicLayout {
  _StaffLayout(
    SheetMusicMetrics metrics,
    Color lineColor,
    this._scale,
    this._lift,
  ) : super(
          metrics,
          lineColor,
          widgetHeight: 0,
          widgetWidth: 0,
          spreadOnlyNotes: true,
        );

  final double _scale;
  final double _lift;

  @override
  double get canvasScale => _scale;

  @override
  double chordLiftAt(double staffLineCenterY) => _lift;
}

/// One staff's measure, cut into what opens it and the notes, each with
/// what follows it before the next (a clef change, an end barline's room).
class _Column {
  _Column(this.prefix, this.items, this.total);

  /// How many symbols open the measure before its first note.
  final int prefix;
  final List<_Item> items;

  /// The time the measure's notes and rests fill, in quarter notes.
  final double total;

  factory _Column.of(MeasureMetrics measure) {
    final symbols = measure.musicalSymbolsMetricses;
    var i = 0;
    while (i < symbols.length && symbols[i].durationUnits <= 0) {
      i++;
    }
    final prefix = i;
    final items = <_Item>[];
    var onset = 0.0;
    for (; i < symbols.length; i++) {
      final symbol = symbols[i];
      if (symbol.durationUnits > 0) {
        items.add(_Item(i, onset));
        onset += symbol.durationUnits;
      } else {
        items.last.attached.add(i);
      }
    }
    return _Column(prefix, items, onset);
  }
}

class _Item {
  _Item(this.index, this.onset);

  final int index;
  final double onset;
  final List<int> attached = [];
}

/// Staffs [first] to [last], a barline drawn through them.
class _Run {
  const _Run(this.first, this.last);

  final int first;
  final int last;
}

class _Span {
  const _Span(this.from, this.to, this.room);

  final int from;
  final int to;
  final double room;
}

/// Where every symbol of the system is set across the line.
class _Placement {
  const _Placement(
    this.measureXs,
    this.xs, {
    required this.stretch,
    required this.squeeze,
    required this.marginScale,
  });

  /// Where each measure starts, and (last) where the last one ends.
  final List<double> measureXs;

  /// For each staff, measure and symbol, the x its renderer is handed.
  final List<List<List<double>>> xs;
  final double stretch;
  final double squeeze;
  final double marginScale;

  double get end => measureXs.last;
}

/// What kind of opening symbol [symbol] is, so staffs opening alike can be
/// lined up sign by sign.
Object _kindOf(MusicalSymbolMetrics symbol) {
  if (symbol is ClefMetrics) return 'clef';
  if (symbol is KeySignatureMetrics) return 'key';
  if (symbol is TimeSignatureMetrics) return 'time';
  if (symbol is RepeatStartMetrics) return 'repeat';
  return symbol.runtimeType;
}
