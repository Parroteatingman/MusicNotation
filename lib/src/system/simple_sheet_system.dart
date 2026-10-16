import 'package:flutter/material.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/font_types.dart';
import 'package:simple_sheet_music/src/sheet_music_font.dart';
import 'package:simple_sheet_music/src/system/sheet_staff.dart';
import 'package:simple_sheet_music/src/system/staff_system_layout.dart';

/// Called with a note, chord or rest of a system: its staff, and its place
/// among that staff's notes, rests and chords.
typedef OnSystemSymbolTap = void Function(int staff, int index);

/// Several staffs drawn as one system — one line of a piano's two hands, or
/// of every part of a score — their notes lined up beat by beat.
///
/// Every staff ([SheetStaff]) holds the same measures. [groups] joins staffs
/// with a brace or a bracket and barlines through them; between staffs of
/// no common group the barlines break. The chord names, and the marks and
/// endings over them, are drawn only over [labelStaff].
///
/// The system is drawn at one size, [staffSpace] points between two staff
/// lines, across [width]: pulled out to fill it (see [justify]), or pulled
/// together when it holds more than fits. A caller breaking a score into
/// systems measures each with [measure] (or [lineWidth]) so that what it
/// puts on a line fits. The widget is as high as [measure] says, unless a
/// [height] is given.
///
/// ```dart
/// SimpleSheetSystem(
///   staffs: [
///     SheetStaff(rightHand),                      // treble
///     SheetStaff(leftHand, clef: ClefType.bass),  // bass
///   ],
///   groups: const [StaffGroup.grandStaff(0, 1)],
///   width: 390,
///   staffSpace: 7.5,
///   lineColor: ink.line,
///   inkColor: ink.ink,
/// )
/// ```
class SimpleSheetSystem extends StatefulWidget {
  const SimpleSheetSystem({
    super.key,
    required this.staffs,
    required this.width,
    required this.staffSpace,
    this.height,
    this.groups = const [],
    this.labelStaff = 0,
    this.lineColor = Colors.black54,
    this.inkColor,
    this.fontType = FontType.bravura,
    this.horizontalPadding = 0,
    this.verticalPadding = 0,
    this.justify = true,
    this.extendStaffToFullWidth = true,
    this.showBarlines = true,
    this.showEndBarline = false,
    this.showFinalBarline = false,
    this.grandStaffGap = 5.0,
    this.partGap = 6.0,
    this.symbolColor,
    this.repaint,
    this.onLayout,
    this.onSymbolTap,
  });

  /// The staffs, top to bottom.
  final List<SheetStaff> staffs;

  /// The width the system is drawn across, in points.
  final double width;

  /// The distance between two staff lines, in points.
  final double staffSpace;

  /// The height of the widget; the staffs are centred in it. Null: as high
  /// as the system needs ([measure]).
  final double? height;

  final List<StaffGroup> groups;

  /// The staff the chord names (and marks, endings) are drawn over; null
  /// draws none.
  final int? labelStaff;

  /// Staff lines and barlines.
  final Color lineColor;

  /// Braces, brackets and the line joining the staffs at the start; the
  /// [lineColor] when null.
  final Color? inkColor;

  final FontType fontType;

  /// Room left of the system and right of its end, in points.
  final double horizontalPadding;

  /// Room over the first staff's notes and under the last's, in points.
  final double verticalPadding;

  /// Pull the notes apart (never past 2.5 times their room) so the system
  /// fills [width]. Off, a system shorter than [width] keeps its natural
  /// room. A system longer than [width] is pulled together either way.
  final bool justify;

  /// Draw the staff lines on to the right edge even when the notes end
  /// sooner.
  final bool extendStaffToFullWidth;

  /// Draw the plain barlines between measures (a measure's own
  /// `endBarline` is drawn either way).
  final bool showBarlines;

  /// At the system's end, when its last measure asks for no barline of its
  /// own: a thin barline, or the final double barline. A row of a longer
  /// score is better closed by its last measure's
  /// `endBarline: BarlineType.single`, as the score writer's rows are.
  final bool showEndBarline;
  final bool showFinalBarline;

  /// The gap between two staffs of a braced group (a piano's), and between
  /// staffs of different parts, in staff spaces from one staff's bottom line
  /// to the next one's top line. Notes reaching into the gap widen it.
  final double grandStaffGap;
  final double partGap;

  /// A colour for a note, chord or rest by its staff and its place among
  /// that staff's notes, rests and chords — a note lit while it sounds;
  /// null for the symbol's own colour. Read when the system is painted, so
  /// with [repaint] it changes without the system being laid out again.
  /// (A colour that never changes — a note the transcriber was unsure of —
  /// is better given to the symbol itself.)
  final SheetSymbolColor? symbolColor;

  /// Repaints the system (and asks [symbolColor] again) when it notifies.
  final Listenable? repaint;

  /// Where everything was drawn: the staffs, the measures and every note,
  /// rest and chord with its staff. Called after the frame that first draws
  /// a layout, and again whenever the layout changes.
  final ValueChanged<SheetSystemGeometry>? onLayout;

  /// A tap on (or near) a note, chord or rest.
  final OnSystemSymbolTap? onSymbolTap;

  /// How big [staffs] are as one system at [staffSpace]: the width it
  /// needs with every note given the room its value asks for (drawn in that
  /// width or more, nothing is squeezed), and its height. Null until
  /// [fontType] has loaded (see [preloadFont]).
  static SheetSystemExtent? measure(
    List<SheetStaff> staffs, {
    required double staffSpace,
    List<StaffGroup> groups = const [],
    int? labelStaff = 0,
    double horizontalPadding = 0,
    double verticalPadding = 0,
    double grandStaffGap = 5.0,
    double partGap = 6.0,
    FontType fontType = FontType.bravura,
  }) {
    final font = SheetMusicFont.ready(fontType);
    if (font == null || staffs.isEmpty || staffs.first.measures.isEmpty) {
      return null;
    }
    final layout = StaffSystemLayout(
      staffs: staffs,
      metadata: font.metadata,
      paths: font.glyphPath,
      canvasScale: staffSpace / Constants.staffSpace,
      width: 0,
      groups: groups,
      labelStaff: labelStaff,
      horizontalPadding: horizontalPadding,
      verticalPadding: verticalPadding,
      grandStaffGap: grandStaffGap,
      partGap: partGap,
    );
    return SheetSystemExtent(layout.naturalWidth, layout.naturalHeight);
  }

  /// The width [measure] gives: what a caller breaks a score into systems
  /// by, putting a measure on the next system when the line would not fit.
  static double? lineWidth(
    List<SheetStaff> staffs, {
    required double staffSpace,
    List<StaffGroup> groups = const [],
    double horizontalPadding = 0,
    FontType fontType = FontType.bravura,
  }) =>
      measure(
        staffs,
        staffSpace: staffSpace,
        groups: groups,
        horizontalPadding: horizontalPadding,
        fontType: fontType,
      )?.width;

  /// Reads the music font ahead of the first system (the same font, read
  /// once, as `SimpleSheetMusic.preloadFont`).
  static Future<void> preloadFont([FontType fontType = FontType.bravura]) =>
      SheetMusicFont.load(fontType);

  @override
  State<SimpleSheetSystem> createState() => _SimpleSheetSystemState();
}

class _SimpleSheetSystemState extends State<SimpleSheetSystem> {
  SheetMusicFont? _font;
  late Future<void> _loading;
  Object? _key;
  StaffSystemLayout? _layout;
  Object? _reported;
  SheetSystemGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    _font = SheetMusicFont.ready(widget.fontType);
    _loading = _load();
  }

  Future<void> _load() async {
    final font = await SheetMusicFont.load(widget.fontType);
    if (!mounted) return;
    _font = font;
  }

  Object _layoutKey() => Object.hashAll([
        widget.width,
        widget.height,
        widget.staffSpace,
        widget.lineColor.toARGB32(),
        widget.inkColor?.toARGB32(),
        widget.fontType,
        widget.labelStaff,
        widget.horizontalPadding,
        widget.verticalPadding,
        widget.justify,
        widget.extendStaffToFullWidth,
        widget.showBarlines,
        widget.showEndBarline,
        widget.showFinalBarline,
        widget.grandStaffGap,
        widget.partGap,
        for (final group in widget.groups)
          Object.hash(group.first, group.last, group.kind, group.barlinesThrough),
        for (final staff in widget.staffs)
          Object.hash(
            staff.clef,
            staff.keySignature,
            Object.hashAll([
              for (final measure in staff.measures)
                Object.hash(
                  measure.startRepeat,
                  measure.endBarline,
                  Object.hashAll(measure.marks),
                  measure.volta,
                  Object.hashAll(measure.musicalSymbols.map(identityHashCode)),
                ),
            ]),
          ),
      ]);

  StaffSystemLayout _resolve(SheetMusicFont font) {
    final key = _layoutKey();
    final cached = _layout;
    if (cached != null && key == _key) return cached;
    _key = key;
    _geometry = null;
    return _layout = StaffSystemLayout(
      staffs: widget.staffs,
      metadata: font.metadata,
      paths: font.glyphPath,
      canvasScale: widget.staffSpace / Constants.staffSpace,
      width: widget.width,
      height: widget.height,
      groups: widget.groups,
      labelStaff: widget.labelStaff,
      lineColor: widget.lineColor,
      inkColor: widget.inkColor,
      horizontalPadding: widget.horizontalPadding,
      verticalPadding: widget.verticalPadding,
      justify: widget.justify,
      extendStaffToFullWidth: widget.extendStaffToFullWidth,
      showBarlines: widget.showBarlines,
      showEndBarline: widget.showEndBarline,
      showFinalBarline: widget.showFinalBarline,
      grandStaffGap: widget.grandStaffGap,
      partGap: widget.partGap,
    );
  }

  SheetSystemGeometry _geometryOf(StaffSystemLayout layout) =>
      _geometry ??= layout.geometry();

  void _report(StaffSystemLayout layout) {
    if (widget.onLayout == null) return;
    final key = _key;
    if (key == null || key == _reported) return;
    _reported = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _key != key) return;
      widget.onLayout?.call(_geometryOf(layout));
    });
  }

  void _tap(StaffSystemLayout layout, Offset position) {
    final onTap = widget.onSymbolTap;
    if (onTap == null) return;
    final geometry = _geometryOf(layout);
    final space = widget.staffSpace;
    var best = double.infinity;
    var staff = -1;
    var index = -1;
    for (final box in geometry.symbols) {
      final heads = box.headBounds.inflate(space * 0.9);
      if (!heads.contains(position)) continue;
      final distance = (heads.center - position).distance;
      if (distance < best) {
        best = distance;
        staff = box.staff;
        index = box.order;
      }
    }
    if (staff >= 0) onTap(staff, index);
  }

  @override
  Widget build(BuildContext context) {
    final font = _font;
    if (font == null) {
      return FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: Center(
                child: Text(
                  'Error loading music fonts: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            );
          }
          final ready = _font;
          if (ready == null) {
            // The music font is still loading: the system's room, empty —
            // no spinner.
            return SizedBox(
              key: const ValueKey('simple-sheet-music-loading'),
              width: widget.width,
              height: widget.height ??
                  widget.staffSpace * (10 * widget.staffs.length),
            );
          }
          return _drawn(ready);
        },
      );
    }
    return _drawn(font);
  }

  Widget _drawn(SheetMusicFont font) {
    final layout = _resolve(font);
    _report(layout);
    final size = Size(widget.width, widget.height ?? layout.naturalHeight);
    final painted = RepaintBoundary(
      child: CustomPaint(
        size: size,
        isComplex: true,
        painter: _SystemPainter(
          layout,
          key: _key!,
          symbolColor: widget.symbolColor,
          repaint: widget.repaint,
        ),
      ),
    );
    if (widget.onSymbolTap == null) return painted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _tap(layout, details.localPosition),
      child: painted,
    );
  }
}

class _SystemPainter extends CustomPainter {
  _SystemPainter(
    this.layout, {
    required this.key,
    this.symbolColor,
    super.repaint,
  });

  final StaffSystemLayout layout;
  final Object key;
  final SheetSymbolColor? symbolColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(layout.canvasScale);
    layout.render(canvas, size, symbolColor: symbolColor);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SystemPainter old) =>
      old.key != key || old.symbolColor != symbolColor;
}

/// For tests: the layout a [SimpleSheetSystem] would draw.
@visibleForTesting
StaffSystemLayout debugSystemLayout(SimpleSheetSystem widget) {
  final font = SheetMusicFont.ready(widget.fontType);
  if (font == null) throw StateError('The music font has not loaded');
  return StaffSystemLayout(
    staffs: widget.staffs,
    metadata: font.metadata,
    paths: font.glyphPath,
    canvasScale: widget.staffSpace / Constants.staffSpace,
    width: widget.width,
    height: widget.height,
    groups: widget.groups,
    labelStaff: widget.labelStaff,
    lineColor: widget.lineColor,
    inkColor: widget.inkColor,
    horizontalPadding: widget.horizontalPadding,
    verticalPadding: widget.verticalPadding,
    justify: widget.justify,
    extendStaffToFullWidth: widget.extendStaffToFullWidth,
    showBarlines: widget.showBarlines,
    showEndBarline: widget.showEndBarline,
    showFinalBarline: widget.showFinalBarline,
    grandStaffGap: widget.grandStaffGap,
    partGap: widget.partGap,
  );
}
